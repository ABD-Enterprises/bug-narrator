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
            // Only the three standard handles cross into the server (PROC_THREAD_ATTRIBUTE_HANDLE_LIST);
            // every other inheritable handle BugNarrator happens to hold stays on this side.
            var inherited = new[] { nullInput.DangerousGetHandle(), nullOutput.DangerousGetHandle(), stderrHandle.DangerousGetHandle() };
            using var attributes = ProcThreadAttributeList.ForHandles(inherited);
            var startup = new StartupInfoEx
            {
                StartupInfo = new StartupInfo
                {
                    cb = Marshal.SizeOf<StartupInfoEx>(),
                    dwFlags = StartfUseStdHandles | StartfUseShowWindow,
                    wShowWindow = SwHide,
                    hStdInput = inherited[0],
                    hStdOutput = inherited[1],
                    hStdError = inherited[2],
                },
                lpAttributeList = attributes.Pointer,
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
                        CreateNewConsole | CreateSuspended | CreateUnicodeEnvironment | ExtendedStartupInfoPresent,
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

            // Exit observation is established while the process is still suspended, so a server that
            // dies on its first instruction still reports its exit code and stderr through onExit.
            var process = Process.GetProcessById(information.dwProcessId);
            process.EnableRaisingEvents = true;
            var wrapper = new LocalServerProcess(process, job, grace, stderrLogPath);
            process.Exited += (_, _) => wrapper.OnExited(onExit);

            if (ResumeThread(information.hThread) == unchecked((uint)-1))
            {
                throw new LocalServerFailure($"The local server process could not be resumed (error {Marshal.GetLastWin32Error()})");
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
                catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
                {
                    // Exited between the check and the kill, or the kill itself was refused: the job
                    // object ends everything in it so shutdown stays deterministic.
                    LastSignalOutcome += $"; kill failed ({exception.GetType().Name}), job terminated";
                    job.TerminateAll();
                }
            }
        });
    }

    public void Dispose()
    {
        job.Dispose();
        process.Dispose();
    }

    private int exitHandled;

    private void OnExited(Action<int, string> onExit)
    {
        if (Interlocked.Exchange(ref exitHandled, 1) == 1)
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

        try
        {
            onExit(code, ReadStderrTail(stderrLogPath));
        }
        finally
        {
            // Waiters are released only after the callback has run, so a caller that disposes on
            // WaitForExitAsync never races the exit handling.
            exited.TrySetResult();
        }
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

            var end = TrimIncompleteTrailingSequence(buffer, start);
            return Encoding.UTF8.GetString(buffer, start, end - start).Trim();
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

    /// <summary>The end index that excludes an unfinished multi-byte sequence, so no replacement character can push past the byte cap.</summary>
    private static int TrimIncompleteTrailingSequence(byte[] buffer, int start)
    {
        var end = buffer.Length;
        var lead = end - 1;
        while (lead >= start && (buffer[lead] & 0xC0) == 0x80)
        {
            lead--;
        }

        if (lead < start)
        {
            return end;
        }

        var expected = buffer[lead] switch
        {
            < 0x80 => 1,
            >= 0xC0 and < 0xE0 => 2,
            >= 0xE0 and < 0xF0 => 3,
            >= 0xF0 => 4,
            _ => 1,
        };
        return end - lead < expected ? lead : end;
    }

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
    private const uint ExtendedStartupInfoPresent = 0x00080000;
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
        ref StartupInfoEx startupInfo,
        out ProcessInformation processInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool InitializeProcThreadAttributeList(IntPtr attributeList, int attributeCount, int flags, ref IntPtr size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UpdateProcThreadAttribute(IntPtr attributeList, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previousValue, IntPtr returnSize);

    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(IntPtr attributeList);

    /// <summary>A PROC_THREAD_ATTRIBUTE_HANDLE_LIST naming exactly the handles the child may inherit.</summary>
    private sealed class ProcThreadAttributeList : IDisposable
    {
        private const uint ProcThreadAttributeHandleList = 0x00020002;

        private readonly IntPtr handles;

        public IntPtr Pointer { get; }

        private ProcThreadAttributeList(IntPtr pointer, IntPtr handles)
        {
            Pointer = pointer;
            this.handles = handles;
        }

        public static ProcThreadAttributeList ForHandles(IntPtr[] inherited)
        {
            var size = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
            var list = Marshal.AllocHGlobal(size);
            var handles = Marshal.AllocHGlobal(IntPtr.Size * inherited.Length);
            try
            {
                if (!InitializeProcThreadAttributeList(list, 1, 0, ref size))
                {
                    throw new LocalServerFailure($"Could not prepare the server's handle list (error {Marshal.GetLastWin32Error()})");
                }

                Marshal.Copy(inherited, 0, handles, inherited.Length);
                if (!UpdateProcThreadAttribute(list, 0, (IntPtr)ProcThreadAttributeHandleList, handles, (IntPtr)(IntPtr.Size * inherited.Length), IntPtr.Zero, IntPtr.Zero))
                {
                    DeleteProcThreadAttributeList(list);
                    throw new LocalServerFailure($"Could not restrict the server's inherited handles (error {Marshal.GetLastWin32Error()})");
                }

                return new ProcThreadAttributeList(list, handles);
            }
            catch
            {
                Marshal.FreeHGlobal(list);
                Marshal.FreeHGlobal(handles);
                throw;
            }
        }

        public void Dispose()
        {
            DeleteProcThreadAttributeList(Pointer);
            Marshal.FreeHGlobal(Pointer);
            Marshal.FreeHGlobal(handles);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct StartupInfoEx
    {
        public StartupInfo StartupInfo;
        public IntPtr lpAttributeList;
    }

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
