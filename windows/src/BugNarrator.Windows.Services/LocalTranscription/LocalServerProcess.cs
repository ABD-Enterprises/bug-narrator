using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>
/// The real server process behind <see cref="LocalServerLaunch"/> (WIN-039, #1181): the verified
/// executable started hidden with its working directory and model cache in the install directory,
/// stdout discarded, the last 4 KB of stderr kept for the exit message, and the process placed in a
/// <see cref="WindowsJobObject"/> so it cannot outlive BugNarrator. Stop is graceful first —
/// a console Ctrl+C that uvicorn handles as SIGINT and drains an in-flight request — then, after
/// the grace period, the whole process tree is killed (the macOS TERM → 2 s → KILL contract, #1128).
/// </summary>
public sealed class LocalServerProcess : ILocalServerProcess, IDisposable
{
    public static readonly TimeSpan DefaultGrace = TimeSpan.FromSeconds(2);
    public const int StderrTailBytes = 4096;

    private readonly Process process;
    private readonly WindowsJobObject job;
    private readonly TimeSpan grace;
    private readonly StringBuilder stderrTail = new();
    private readonly object tailGate = new();
    private readonly TaskCompletionSource exited = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int terminateRequested;

    private LocalServerProcess(Process process, WindowsJobObject job, TimeSpan grace)
    {
        this.process = process;
        this.job = job;
        this.grace = grace;
    }

    public int ProcessId => process.Id;

    public bool HasExited => process.HasExited;

    /// <summary>The server's command line: loopback only, fixed port, pinned model (design note §3.3).</summary>
    public static string ServerArguments =>
        $"--host 127.0.0.1 --port 8422 --model {Settings.WindowsAiProviderProfile.ParakeetTranscriptionModel}";

    /// <summary>The <see cref="LocalServerLaunch"/> the app composes.</summary>
    public static ILocalServerProcess LaunchServer(string executablePath, string modelsDirectory, Action<int, string> onExit) =>
        Launch(executablePath, ServerArguments, modelsDirectory, onExit, DefaultGrace);

    public static LocalServerProcess Launch(
        string executablePath,
        string arguments,
        string modelsDirectory,
        Action<int, string> onExit,
        TimeSpan grace)
    {
        Directory.CreateDirectory(modelsDirectory);
        var startInfo = new ProcessStartInfo(executablePath, arguments)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Path.GetDirectoryName(executablePath) ?? modelsDirectory,
        };
        startInfo.Environment["HF_HOME"] = modelsDirectory;
        startInfo.Environment["BUGNARRATOR_MODELS_DIR"] = modelsDirectory;

        var job = new WindowsJobObject();
        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        LocalServerProcess? wrapper = null;
        try
        {
            if (!process.Start())
            {
                throw new LocalServerFailure("The local server process did not start");
            }

            wrapper = new LocalServerProcess(process, job, grace);
            // Assigned immediately after start; a crash of BugNarrator from here on takes the server with it.
            job.Assign(process.Handle);
            process.OutputDataReceived += (_, _) => { }; // stdout discarded
            process.ErrorDataReceived += (_, args) => wrapper.AppendStderr(args.Data);
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.Exited += (_, _) => wrapper.OnExited(onExit);
            if (process.HasExited)
            {
                wrapper.OnExited(onExit);
            }

            return wrapper;
        }
        catch
        {
            if (wrapper is null)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                }
                catch
                {
                    // Best effort: the job object closes below and takes it down anyway.
                }

                process.Dispose();
                job.Dispose();
            }

            throw;
        }
    }

    public bool IsInJob => job.Contains(process.Handle);

    public Task WaitForExitAsync() => exited.Task;

    /// <summary>Graceful stop, then kill after the grace period. Idempotent.</summary>
    public void Terminate()
    {
        if (Interlocked.Exchange(ref terminateRequested, 1) == 1 || process.HasExited)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            TrySendCtrlC();
            try
            {
                await exited.Task.WaitAsync(grace);
            }
            catch (TimeoutException)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                }
                catch (InvalidOperationException)
                {
                    // Exited between the check and the kill.
                }
            }
        });
    }

    public void Dispose()
    {
        job.Dispose();
        process.Dispose();
    }

    private void AppendStderr(string? line)
    {
        if (line is null)
        {
            return;
        }

        lock (tailGate)
        {
            stderrTail.AppendLine(line);
            if (stderrTail.Length > StderrTailBytes)
            {
                stderrTail.Remove(0, stderrTail.Length - StderrTailBytes);
            }
        }
    }

    private void OnExited(Action<int, string> onExit)
    {
        if (!exited.TrySetResult())
        {
            return;
        }

        int code;
        try
        {
            process.WaitForExit(); // flushes the async stderr reader
            code = process.ExitCode;
        }
        catch (InvalidOperationException)
        {
            code = -1;
        }

        string tail;
        lock (tailGate)
        {
            tail = stderrTail.ToString().Trim();
        }

        onExit(code, tail);
    }

    /// <summary>
    /// Attaches to the child's hidden console, ignores the event in this process, and sends Ctrl+C
    /// to everything on that console — which is only the server. uvicorn treats it as SIGINT.
    /// </summary>
    private void TrySendCtrlC()
    {
        if (!AttachConsole((uint)process.Id))
        {
            return;
        }

        try
        {
            SetConsoleCtrlHandler(null, add: true);
            GenerateConsoleCtrlEvent(CtrlCEvent, 0);
        }
        finally
        {
            FreeConsole();
            SetConsoleCtrlHandler(null, add: false);
        }
    }

    private const uint CtrlCEvent = 0;

    private delegate bool ConsoleCtrlDelegate(uint ctrlType);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AttachConsole(uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate? handler, bool add);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
}
