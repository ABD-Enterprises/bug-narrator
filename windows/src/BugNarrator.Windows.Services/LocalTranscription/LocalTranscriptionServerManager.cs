namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>A running server process as the manager sees it; WIN-039 supplies the real one.</summary>
public interface ILocalServerProcess
{
    Task WaitForExitAsync();
    void Terminate();
}

/// <summary>
/// Launches the verified executable with the models directory; reports (exit status, stderr tail)
/// through <paramref name="onExit"/> when it ends.
/// </summary>
public delegate ILocalServerProcess LocalServerLaunch(string executablePath, string modelsDirectory, Action<int, string> onExit);

/// <summary>Observable state, the same shape as the macOS manager's published properties.</summary>
public sealed record LocalTranscriptionServerState(
    LocalServerPackage? Package,
    double? Progress,
    bool Busy,
    bool Installed,
    bool Running,
    string Message);

public interface ILocalTranscriptionServerManager
{
    LocalTranscriptionServerState State { get; }
    event EventHandler<LocalTranscriptionServerState>? StateChanged;
    string InstallDirectory { get; }
    Task DiscoverAsync(CancellationToken cancellationToken = default);
    Task InstallAndStartAsync(CancellationToken cancellationToken = default);
    Task StartAsync(CancellationToken cancellationToken = default);
    void Stop();
    Task ShutdownAsync();
    void Remove();
}

/// <summary>
/// Port of macOS LocalTranscriptionManager (Services/LocalTranscriptionManager.swift): discovery,
/// managed install, start/stop/remove with the same guards — no Remove while busy or running, Start
/// requires Installed and no live process, nothing runs unverified. Process launch is a delegate so
/// the real Job-Object-backed process (WIN-039) and the test fake plug in the same way.
/// Design: docs/architecture/windows-local-transcription.md (#1169).
/// </summary>
public sealed class LocalTranscriptionServerManager : ILocalTranscriptionServerManager
{
    private readonly LocalServerPackageCatalog catalog;
    private readonly HttpClient httpClient;
    private readonly LocalServerInstaller installer;
    private readonly IAuthenticodeVerifier verifier;
    private readonly LocalServerLaunch launch;
    private readonly object gate = new();

    private ILocalServerProcess? server;
    private Task? installOperation;
    private Task? startOperation;
    private CancellationTokenSource? installCancellation;
    private CancellationTokenSource? startCancellation;
    private bool shuttingDown;
    private LocalTranscriptionServerState state;

    public LocalTranscriptionServerManager(
        string installDirectory,
        LocalServerPackageCatalog catalog,
        HttpClient httpClient,
        IAuthenticodeVerifier verifier,
        LocalServerLaunch launch)
    {
        InstallDirectory = installDirectory;
        this.catalog = catalog;
        this.httpClient = httpClient;
        this.verifier = verifier;
        this.launch = launch;
        installer = new LocalServerInstaller(verifier);
        state = new LocalTranscriptionServerState(
            Package: null,
            Progress: null,
            Busy: false,
            Installed: File.Exists(ExecutablePath),
            Running: false,
            Message: string.Empty);
    }

    public static string DefaultInstallDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BugNarrator", "LocalTranscription");

    public string InstallDirectory { get; }

    public string ExecutablePath => Path.Combine(InstallDirectory, LocalServerInstaller.ExecutableName);

    public string ModelsDirectory => Path.Combine(InstallDirectory, "Models");

    public LocalTranscriptionServerState State
    {
        get { lock (gate) { return state; } }
    }

    public event EventHandler<LocalTranscriptionServerState>? StateChanged;

    public async Task DiscoverAsync(CancellationToken cancellationToken = default)
    {
        // Guard and reservation under one lock, so two callers cannot both pass the guard.
        if (!TryReserve(current => current.Package is null && !current.Busy && !shuttingDown))
        {
            return;
        }

        try
        {
            var (package, message) = await catalog.DiscoverAsync(cancellationToken);
            Update(current => current with { Package = package, Message = message });
        }
        finally
        {
            Update(current => current with { Busy = false });
        }
    }

    public Task InstallAndStartAsync(CancellationToken cancellationToken = default)
    {
        LocalServerPackage package;
        CancellationToken token;
        lock (gate)
        {
            if (state.Package is null || state.Busy || state.Installed || shuttingDown)
            {
                return Task.CompletedTask;
            }

            package = state.Package;
            installCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            token = installCancellation.Token;
            state = state with { Busy = true, Progress = 0, Message = "Downloading the local server…" };
        }

        StateChanged?.Invoke(this, State);
        installOperation = Task.Run(async () =>
        {
            try
            {
                var checksum = await DownloadTextAsync(package.Checksum.BrowserDownloadUrl, token);
                if (checksum.Length >= LocalServerPackageCatalog.MaxChecksumBytes)
                {
                    throw new LocalServerFailure("Invalid checksum manifest");
                }

                var temporary = Path.Combine(Path.GetTempPath(), $"BugNarrator-Server-{Guid.NewGuid():N}.zip");
                try
                {
                    await DownloadFileAsync(package.Image.BrowserDownloadUrl, temporary, package.Image.Size, token);
                    token.ThrowIfCancellationRequested();
                    Update(s => s with { Message = "Verifying and installing the signed server…" });
                    installer.Install(temporary, checksum, package.Image.Size, InstallDirectory, token);
                }
                finally
                {
                    if (File.Exists(temporary))
                    {
                        File.Delete(temporary);
                    }
                }

                Update(s => s with { Installed = true });
                token.ThrowIfCancellationRequested();
                Update(s => s with { Busy = false, Progress = null });
                await StartAsync(token);
            }
            catch (OperationCanceledException)
            {
                Update(s => s with { Message = "Installation canceled. You can retry." });
            }
            catch (Exception exception)
            {
                Update(s => s with { Message = $"Installation failed: {exception.Message}. You can retry." });
            }
            finally
            {
                Update(s => s with { Busy = startOperation is { IsCompleted: false }, Progress = null });
                installOperation = null;
            }
        }, CancellationToken.None);
        return installOperation;
    }

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        CancellationToken token;
        lock (gate)
        {
            if (!state.Installed || server is not null || startOperation is { IsCompleted: false } || shuttingDown)
            {
                return Task.CompletedTask;
            }

            startCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            token = startCancellation.Token;
            state = state with { Busy = true };
            // Reserved before the task exists so a concurrent StartAsync sees the operation as live.
            startOperation = new TaskCompletionSource().Task;
        }

        StateChanged?.Invoke(this, State);
        startOperation = Task.Run(() =>
        {
            try
            {
                // Re-verified immediately before every launch, as macOS re-runs verifyBinary.
                verifier.Verify(ExecutablePath);
                token.ThrowIfCancellationRequested();
                LaunchVerifiedServer();
            }
            catch (OperationCanceledException)
            {
                Update(s => s with { Message = "Server start canceled." });
            }
            catch (Exception exception)
            {
                Update(s => s with { Message = $"Could not start the server: {exception.Message}. Remove and reinstall it if verification failed." });
            }
            finally
            {
                Update(s => s with { Busy = false });
                startOperation = null;
            }
        }, CancellationToken.None);
        return startOperation;
    }

    private void LaunchVerifiedServer()
    {
        try
        {
            var process = launch(ExecutablePath, ModelsDirectory, (status, detail) =>
            {
                server = null;
                Update(s => s with
                {
                    Running = false,
                    Message = status == 0
                        ? "Local server stopped."
                        : $"Local server exited ({status}). {(string.IsNullOrWhiteSpace(detail) ? "Try starting it again." : detail)}",
                });
            });
            server = process;
            Update(s => s with
            {
                Running = true,
                Message = "Server starting. The first start downloads model weights; recording becomes ready when the server responds.",
            });
        }
        catch (Exception exception)
        {
            Update(s => s with { Message = $"Could not start the server: {exception.Message}. Remove and reinstall it if verification failed." });
        }
    }

    public void Stop()
    {
        installCancellation?.Cancel();
        startCancellation?.Cancel();
        server?.Terminate();
    }

    /// <summary>
    /// Cancellation alone is not enough: awaits the in-flight install/start and then the bounded
    /// process exit, so nothing outlives the app (macOS shutdown()).
    /// </summary>
    public async Task ShutdownAsync()
    {
        shuttingDown = true;
        try
        {
            var installing = installOperation;
            var starting = startOperation;
            var process = server;
            Stop();
            if (installing is not null)
            {
                await installing;
            }

            if (starting is not null)
            {
                await starting;
            }

            if (process is not null)
            {
                await process.WaitForExitAsync();
            }
        }
        finally
        {
            shuttingDown = false;
        }
    }

    public void Remove()
    {
        lock (gate)
        {
            if (state.Busy || server is not null || startOperation is { IsCompleted: false })
            {
                return;
            }

            // Reserved so a Start racing this removal is refused until it finishes.
            state = state with { Busy = true };
        }

        try
        {
            if (Directory.Exists(InstallDirectory))
            {
                Directory.Delete(InstallDirectory, recursive: true);
            }

            Update(s => s with { Installed = false, Message = "Local server and its managed model cache removed." });
        }
        catch (Exception exception)
        {
            Update(s => s with { Message = $"Could not remove the local server: {exception.Message}" });
        }
        finally
        {
            Update(s => s with { Busy = false });
        }
    }

    private bool TryReserve(Func<LocalTranscriptionServerState, bool> guard)
    {
        lock (gate)
        {
            if (!guard(state))
            {
                return false;
            }

            state = state with { Busy = true };
        }

        StateChanged?.Invoke(this, State);
        return true;
    }

    private async Task<string> DownloadTextAsync(string url, CancellationToken cancellationToken)
    {
        using var response = await httpClient.GetAsync(url, cancellationToken);
        RequireSuccess(response);
        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private async Task DownloadFileAsync(string url, string destination, long expectedSize, CancellationToken cancellationToken)
    {
        using var response = await httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        RequireSuccess(response);
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var target = File.Create(destination);
        var buffer = new byte[81920];
        long written = 0;
        int read;
        while ((read = await source.ReadAsync(buffer, cancellationToken)) > 0)
        {
            await target.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            written += read;
            if (written > LocalServerPackageCatalog.MaxImageBytes)
            {
                throw new LocalServerFailure("The server download exceeded its size limit");
            }

            var fraction = expectedSize > 0 ? Math.Min(1.0, (double)written / expectedSize) : 0;
            Update(s => s with { Progress = fraction });
        }
    }

    private static void RequireSuccess(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new LocalServerFailure("The download server returned an unsuccessful response");
        }
    }

    private void Update(Func<LocalTranscriptionServerState, LocalTranscriptionServerState> change)
    {
        LocalTranscriptionServerState next;
        lock (gate)
        {
            next = change(state);
            state = next;
        }

        StateChanged?.Invoke(this, next);
    }
}
