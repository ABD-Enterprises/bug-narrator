using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>
/// The real server process behind <see cref="LocalServerLaunch"/> (WIN-039, #1181). The verified
/// executable is created suspended in its own hidden console, assigned to
/// a KILL_ON_JOB_CLOSE <see cref="WindowsJobObject"/> before it runs a single instruction (so it can
/// never outlive BugNarrator, not even across a crash), then resumed with its working directory and
/// model cache in the install directory. stdout is discarded; stderr goes to <c>server.stderr.log</c>
/// in the install directory and its last 4 KB (bytes) become the exit message. Stop is graceful first —
/// Ctrl+C on the server's own console, which uvicorn handles as SIGINT and drains an in-flight
/// request — then, after the grace period, the whole process tree is killed (the macOS
/// TERM → 2 s → KILL contract, #1128).
/// </summary>
public sealed class LocalServerProcess : ILocalServerProcess, IDisposable
{
    public static readonly TimeSpan DefaultGrace = TimeSpan.FromSeconds(2);
    public const int StderrTailBytes = 4096;
    public const string StderrLogName = "server.stderr.log";

    private readonly Process process;
    private readonly WindowsJobObject job;
    private readonly TimeSpan grace;
    private readonly string stderrLogPath;
    private readonly TaskCompletionSource exited = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int terminateRequested;

    private LocalServerProcess(Process process, WindowsJobObject job, TimeSpan grace, string stderrLogPath)
    {
        this.process = process;
        this.job = job;
        this.grace = grace;
        this.stderrLogPath = stderrLogPath;
    }

    public int ProcessId => process.Id;

    public bool HasExited => process.HasExited;

    public bool IsInJob => job.Contains(process.Handle);

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
        if (!File.Exists(executablePath))
        {
            throw new LocalServerFailure("The local server executable is missing");
        }

        Directory.CreateDirectory(modelsDirectory);
        // The install directory (parent of Models) is the working directory and holds the stderr log.
        var workingDirectory = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(modelsDirectory)) ?? modelsDirectory;
        var stderrLogPath = Path.Combine(workingDirectory, StderrLogName);

        var job = new WindowsJobObject();
        SafeFileHandle? stderrHandle = null;
        SafeFileHandle? nullInput = null;
        SafeFileHandle? nullOutput = null;
        var information = new ProcessInformation();
        try
        {
            stderrHandle = OpenInheritableLog(stderrLogPath);
            // Real NUL handles for stdin/stdout: a zero handle is not "no handle" to a console app.
            nullInput = OpenInheritableNul(FileAccess.Read);
            nullOutput = OpenInheritableNul(FileAccess.Write);
            var startup = new StartupInfo
            {
                cb = Marshal.SizeOf<StartupInfo>(),
                dwFlags = StartfUseStdHandles | StartfUseShowWindow,
                wShowWindow = SwHide,
                hStdInput = nullInput.DangerousGetHandle(),
                hStdOutput = nullOutput.DangerousGetHandle(),
                hStdError = stderrHandle.DangerousGetHandle(),
            };
            var commandLine = new StringBuilder($"\"{executablePath}\" {arguments}");
            var environment = BuildEnvironmentBlock(modelsDirectory);
            var environmentPointer = Marshal.StringToHGlobalUni(environment);
            try
            {
                if (!CreateProcessW(
                        null,
                        commandLine,
                        IntPtr.Zero,
                        IntPtr.Zero,
                        bInheritHandles: true,
                        CreateNewConsole | CreateSuspended | CreateUnicodeEnvironment,
                        environmentPointer,
                        workingDirectory,
                        ref startup,
                        out information))
                {
                    throw new LocalServerFailure($"The local server process did not start (error {Marshal.GetLastWin32Error()})");
                }
            }
            finally
            {
                Marshal.FreeHGlobal(environmentPointer);
            }

            // Contained before it runs: assignment failure terminates a process that never executed.
            job.Assign(information.hProcess);
            if (ResumeThread(information.hThread) == unchecked((uint)-1))
            {
                throw new LocalServerFailure($"The local server process could not be resumed (error {Marshal.GetLastWin32Error()})");
            }

            var process = Process.GetProcessById(information.dwProcessId);
            process.EnableRaisingEvents = true;
            var wrapper = new LocalServerProcess(process, job, grace, stderrLogPath);
            process.Exited += (_, _) => wrapper.OnExited(onExit);
            if (process.HasExited)
            {
                wrapper.OnExited(onExit);
            }

            return wrapper;
        }
        catch
        {
            // Every post-create failure ends the process and releases the job; nothing is left running.
            if (information.hProcess != IntPtr.Zero)
            {
                TerminateProcess(information.hProcess, 1);
            }

            job.Dispose();
            throw;
        }
        finally
        {
            stderrHandle?.Dispose();
            nullInput?.Dispose();
            nullOutput?.Dispose();
            if (information.hThread != IntPtr.Zero)
            {
                CloseHandle(information.hThread);
            }

            if (information.hProcess != IntPtr.Zero)
            {
                CloseHandle(information.hProcess);
            }
        }
    }

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

    private void OnExited(Action<int, string> onExit)
    {
        if (!exited.TrySetResult())
        {
            return;
        }

        int code;
        try
        {
            process.WaitForExit();
            code = process.ExitCode;
        }
        catch (InvalidOperationException)
        {
            code = -1;
        }

        onExit(code, ReadStderrTail(stderrLogPath));
    }

    /// <summary>The last <see cref="StderrTailBytes"/> bytes of the log, decoded as UTF-8 — a byte cap, as documented.</summary>
    public static string ReadStderrTail(string logPath)
    {
        try
        {
            using var stream = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var length = (int)Math.Min(stream.Length, StderrTailBytes);
            stream.Seek(-length, SeekOrigin.End);
            var buffer = new byte[length];
            stream.ReadExactly(buffer);
            // Skip a leading partial UTF-8 sequence so the decoded tail never exceeds the byte cap.
            var start = 0;
            while (start < buffer.Length && (buffer[start] & 0xC0) == 0x80)
            {
                start++;
            }

            return Encoding.UTF8.GetString(buffer, start, buffer.Length - start).Trim();
        }
        catch (IOException)
        {
            return string.Empty;
        }
        catch (UnauthorizedAccessException)
        {
            return string.Empty;
        }
    }

    /// <summary>
    /// Attaches to the child's hidden console — the server is the only other process on it — and
    /// sends Ctrl+C there. uvicorn handles it as SIGINT and shuts down gracefully.
    /// </summary>
    /// <summary>What the last graceful-stop attempt did; surfaced in diagnostics and tests.</summary>
    public string LastSignalOutcome { get; private set; } = "not attempted";

    /// <summary>Console attachment is process-wide state; two stops must never interleave.</summary>
    private static readonly object ConsoleGate = new();

    private void TrySendCtrlC()
    {
        lock (ConsoleGate)
        {
            SendCtrlCLocked();
        }
    }

    private void SendCtrlCLocked()
    {
        // BugNarrator has no console, so attaching succeeds directly. A host that already owns one
        // (the test runner) must release it first; it is re-attached to the parent afterwards.
        var releasedOwnConsole = false;
        if (!AttachConsole((uint)process.Id))
        {
            var error = Marshal.GetLastWin32Error();
            if (error != ErrorAccessDenied)
            {
                LastSignalOutcome = $"AttachConsole failed (error {error})";
                return;
            }

            FreeConsole();
            releasedOwnConsole = true;
            if (!AttachConsole((uint)process.Id))
            {
                LastSignalOutcome = $"AttachConsole failed after releasing own console (error {Marshal.GetLastWin32Error()})";
                AttachConsole(AttachParentProcess);
                return;
            }
        }

        try
        {
            // Sent to every process on that console (group 0): the server, and — while attached —
            // this process, which swallows it through the handler below.
            SetConsoleCtrlHandler(SwallowCtrlEvent, add: true);
            LastSignalOutcome = GenerateConsoleCtrlEvent(CtrlCEvent, 0)
                ? "Ctrl+C sent"
                : $"GenerateConsoleCtrlEvent failed (error {Marshal.GetLastWin32Error()})";
            // Give conhost time to deliver the event before this process leaves the console; once
            // detached, a late delivery would go nowhere.
            Thread.Sleep(300);
        }
        finally
        {
            FreeConsole();
            SetConsoleCtrlHandler(SwallowCtrlEvent, add: false);
            if (releasedOwnConsole)
            {
                AttachConsole(AttachParentProcess);
            }
        }
    }

    private static SafeFileHandle OpenInheritableNul(FileAccess access)
    {
        var handle = File.OpenHandle("NUL", FileMode.Open, access, FileShare.ReadWrite);
        if (!SetHandleInformation(handle, HandleFlagInherit, HandleFlagInherit))
        {
            handle.Dispose();
            throw new LocalServerFailure($"Could not prepare the server's standard handles (error {Marshal.GetLastWin32Error()})");
        }

        return handle;
    }

    private static SafeFileHandle OpenInheritableLog(string path)
    {
        var handle = File.OpenHandle(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
        if (!SetHandleInformation(handle, HandleFlagInherit, HandleFlagInherit))
        {
            handle.Dispose();
            throw new LocalServerFailure($"Could not prepare the server log (error {Marshal.GetLastWin32Error()})");
        }

        return handle;
    }

    /// <summary>Our environment plus the model cache variables, as a double-NUL-terminated Unicode block.</summary>
    private static string BuildEnvironmentBlock(string modelsDirectory)
    {
        var variables = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            variables[(string)entry.Key] = (string?)entry.Value ?? string.Empty;
        }

        variables["HF_HOME"] = modelsDirectory;
        variables["BUGNARRATOR_MODELS_DIR"] = modelsDirectory;

        var block = new StringBuilder();
        foreach (var (key, value) in variables)
        {
            block.Append(key).Append('=').Append(value).Append('\0');
        }

        return block.Append('\0').ToString();
    }

    private const uint CtrlCEvent = 0;
    private const uint AttachParentProcess = unchecked((uint)-1);
    private const int ErrorAccessDenied = 5;
    private const uint CreateNewConsole = 0x00000010;
    private const uint CreateSuspended = 0x00000004;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const int StartfUseShowWindow = 0x00000001;
    private const int StartfUseStdHandles = 0x00000100;
    private const short SwHide = 0;
    private const uint HandleFlagInherit = 0x00000001;

    private delegate bool ConsoleCtrlDelegate(uint ctrlType);

    /// <summary>Kept in a static so the unmanaged callback can never be collected while registered.</summary>
    private static readonly ConsoleCtrlDelegate SwallowCtrlEvent = _ => true;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(
        string? applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        bool bInheritHandles,
        uint creationFlags,
        IntPtr environment,
        string? currentDirectory,
        ref StartupInfo startupInfo,
        out ProcessInformation processInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr thread);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetHandleInformation(SafeFileHandle handle, uint mask, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AttachConsole(uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate? handler, bool add);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int cb;
        public string? lpReserved;
        public string? lpDesktop;
        public string? lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
}
