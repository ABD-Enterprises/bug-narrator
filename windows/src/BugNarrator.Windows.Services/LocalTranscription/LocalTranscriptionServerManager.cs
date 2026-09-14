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
    private TaskCompletionSource? installCompletion;
    private TaskCompletionSource? startCompletion;
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
            // Published under the lock so a concurrent ShutdownAsync always finds it; completed by
            // the work below, never left dangling.
            installCompletion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            installOperation = installCompletion.Task;
        }

        var completion = installCompletion;
        _ = Task.Run(async () =>
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
                lock (gate)
                {
                    installOperation = null;
                }

                completion.SetResult();
            }
        }, CancellationToken.None);
        Notify();
        return completion.Task;
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
            // Published under the lock and completed by the work below.
            startCompletion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            startOperation = startCompletion.Task;
        }

        var completion = startCompletion;
        _ = Task.Run(() =>
        {
            try
            {
                // Re-verified immediately before every launch, as macOS re-runs verifyBinary.
                verifier.Verify(ExecutablePath);
                token.ThrowIfCancellationRequested();
                LaunchVerifiedServer(token);
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
                lock (gate)
                {
                    startOperation = null;
                }

                completion.SetResult();
            }
        }, CancellationToken.None);
        Notify();
        return completion.Task;
    }

    private void LaunchVerifiedServer(CancellationToken token)
    {
        try
        {
            // The exit callback and the assignment below are ordered under the gate, so a process
            // that dies before launch() returns cannot be stored as a live server afterwards.
            var exited = false;
            var process = launch(ExecutablePath, ModelsDirectory, (status, detail) =>
            {
                lock (gate)
                {
                    exited = true;
                    server = null;
                }

                Update(s => s with
                {
                    Running = false,
                    Message = status == 0
                        ? "Local server stopped."
                        : $"Local server exited ({status}). {(string.IsNullOrWhiteSpace(detail) ? "Try starting it again." : detail)}",
                });
            });

            lock (gate)
            {
                if (exited)
                {
                    return;
                }

                // Stop() cancels under this same gate: a stop that landed between the cancellation
                // check and here terminates the just-launched process instead of orphaning it.
                if (token.IsCancellationRequested)
                {
                    process.Terminate();
                    return;
                }

                // Assignment and the Running transition are one step under the gate, so an exit
                // that lands right after cannot be overwritten by a stale "running" publication.
                server = process;
                state = state with
                {
                    Running = true,
                    Message = "Server starting. The first start downloads model weights; recording becomes ready when the server responds.",
                };
            }

            Notify();
        }
        catch (Exception exception)
        {
            Update(s => s with { Message = $"Could not start the server: {exception.Message}. Remove and reinstall it if verification failed." });
        }
    }

    public void Stop()
    {
        ILocalServerProcess? process;
        lock (gate)
        {
            installCancellation?.Cancel();
            startCancellation?.Cancel();
            process = server;
        }

        process?.Terminate();
    }

    /// <summary>
    /// Cancellation alone is not enough: awaits the in-flight install/start and then the bounded
    /// process exit, so nothing outlives the app (macOS shutdown()).
    /// </summary>
    public async Task ShutdownAsync()
    {
        lock (gate)
        {
            // Under the lock so no start or install can be reserved after this point.
            shuttingDown = true;
        }

        try
        {
            // A start that was already past its cancellation check may still assign a server after
            // the first snapshot, so re-read until nothing is in flight and no process is live.
            while (true)
            {
                Task? installing;
                Task? starting;
                ILocalServerProcess? process;
                lock (gate)
                {
                    installing = installOperation;
                    starting = startOperation;
                    process = server;
                }

                if (installing is null && starting is null && process is null)
                {
                    return;
                }

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
        }
        finally
        {
            lock (gate)
            {
                shuttingDown = false;
            }
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

        Notify();
        return true;
    }

    /// <summary>
    /// Subscriber failures are isolated: a throwing handler must not leave an operation reserved
    /// or a state transition half-applied.
    /// </summary>
    private void Notify()
    {
        try
        {
            StateChanged?.Invoke(this, State);
        }
        catch
        {
            // The state is already committed; a subscriber's failure is its own problem.
        }
    }

    private async Task<string> DownloadTextAsync(string url, CancellationToken cancellationToken)
    {
        using var response = await httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        RequireSuccess(response);
        // Streamed with a hard bound: release metadata is not trusted to size the manifest.
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        var buffer = new byte[LocalServerPackageCatalog.MaxChecksumBytes];
        var total = 0;
        int read;
        while ((read = await source.ReadAsync(buffer.AsMemory(total, buffer.Length - total), cancellationToken)) > 0)
        {
            total += read;
            if (total >= buffer.Length)
            {
                throw new LocalServerFailure("Invalid checksum manifest");
            }
        }

        return System.Text.Encoding.UTF8.GetString(buffer, 0, total);
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
        lock (gate)
        {
            state = change(state);
        }

        Notify();
    }
}
