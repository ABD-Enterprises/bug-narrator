using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace BugNarrator.Windows.Services.LocalTranscription;

/// <summary>
/// A Job Object with KILL_ON_JOB_CLOSE: every process assigned to it dies when the handle closes,
/// which happens when BugNarrator exits — including a crash. The Windows replacement for the
/// macOS process-group trick that keeps uvicorn and its children from outliving the app.
/// </summary>
public sealed class WindowsJobObject : IDisposable
{
    private readonly SafeFileHandle handle;

    public WindowsJobObject()
    {
        handle = CreateJobObjectW(IntPtr.Zero, null);
        if (handle.IsInvalid)
        {
            throw new LocalServerFailure($"Could not create a job object (error {Marshal.GetLastWin32Error()})");
        }

        var limits = new JobObjectExtendedLimitInformation
        {
            BasicLimitInformation = { LimitFlags = JobObjectLimitKillOnJobClose },
        };
        var size = Marshal.SizeOf<JobObjectExtendedLimitInformation>();
        var buffer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(limits, buffer, fDeleteOld: false);
            if (!SetInformationJobObject(handle, JobObjectExtendedLimitInformationClass, buffer, (uint)size))
            {
                throw new LocalServerFailure($"Could not configure the job object (error {Marshal.GetLastWin32Error()})");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    public void Assign(IntPtr processHandle)
    {
        if (!AssignProcessToJobObject(handle, processHandle))
        {
            throw new LocalServerFailure($"Could not assign the server to the job object (error {Marshal.GetLastWin32Error()})");
        }
    }

    /// <summary>True when the process belongs to this job; used by the tests to prove containment.</summary>
    public bool Contains(IntPtr processHandle)
    {
        return IsProcessInJob(processHandle, handle, out var result) && result;
    }

    /// <summary>Ends every process in the job now — the last resort when a kill request itself fails.</summary>
    public void TerminateAll(uint exitCode = 1)
    {
        TerminateJobObject(handle, exitCode);
    }

    public void Dispose() => handle.Dispose();

    private const int JobObjectExtendedLimitInformationClass = 9;
    private const uint JobObjectLimitKillOnJobClose = 0x2000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateJobObjectW(IntPtr securityAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(SafeFileHandle job, int infoClass, IntPtr info, uint infoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool IsProcessInJob(IntPtr process, SafeFileHandle job, out bool result);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateJobObject(SafeFileHandle job, uint exitCode);

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }
}
