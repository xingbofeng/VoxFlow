using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace VoxFlow.Windows.Infrastructure.Ocr;

internal interface ITesseractProcessJobFactory
{
    ITesseractProcessJob CreateAndAssign(nint processHandle);
}

internal interface ITesseractProcessJob : IDisposable
{
    bool TryTerminate();
}

/// <summary>
/// Owns the complete OCR process tree. Microsoft documents that child processes
/// join their parent's job by default and that closing the final handle with
/// JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE terminates every associated process.
/// https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
/// </summary>
internal sealed class WindowsTesseractProcessJobFactory : ITesseractProcessJobFactory
{
    public static WindowsTesseractProcessJobFactory Instance { get; } = new();

    private WindowsTesseractProcessJobFactory()
    {
    }

    public ITesseractProcessJob CreateAndAssign(nint processHandle) =>
        WindowsTesseractProcessJob.CreateAndAssign(processHandle);
}

internal sealed class WindowsTesseractProcessJob : ITesseractProcessJob
{
    private const uint JobObjectLimitKillOnJobClose = 0x00002000;
    private const int JobObjectExtendedLimitInformationClass = 9;
    private readonly SafeJobHandle handle;

    private WindowsTesseractProcessJob(SafeJobHandle handle)
    {
        this.handle = handle;
    }

    public static WindowsTesseractProcessJob CreateAndAssign(nint processHandle)
    {
        if (processHandle == nint.Zero || processHandle == new nint(-1))
        {
            throw new ArgumentException("A valid OCR process handle is required.", nameof(processHandle));
        }

        var handle = CreateJobObjectW(nint.Zero, null);
        if (handle.IsInvalid)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            var limits = new JobObjectExtendedLimitInformation
            {
                BasicLimitInformation = new JobObjectBasicLimitInformation
                {
                    LimitFlags = JobObjectLimitKillOnJobClose,
                },
            };
            if (!SetInformationJobObject(
                    handle,
                    JobObjectExtendedLimitInformationClass,
                    ref limits,
                    (uint)Marshal.SizeOf<JobObjectExtendedLimitInformation>()))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            if (!AssignProcessToJobObject(handle, processHandle))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return new WindowsTesseractProcessJob(handle);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    public bool TryTerminate()
    {
        if (handle.IsClosed || handle.IsInvalid)
        {
            return true;
        }
        return TerminateJobObject(handle, 1);
    }

    public void Dispose() => handle.Dispose();

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public nuint MinimumWorkingSetSize;
        public nuint MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public nuint Affinity;
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
        public nuint ProcessMemoryLimit;
        public nuint JobMemoryLimit;
        public nuint PeakProcessMemoryUsed;
        public nuint PeakJobMemoryUsed;
    }

    private sealed class SafeJobHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        private SafeJobHandle()
            : base(ownsHandle: true)
        {
        }

        protected override bool ReleaseHandle() => CloseHandle(handle);
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateJobObjectW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeJobHandle CreateJobObjectW(nint jobAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(
        SafeJobHandle job,
        int informationClass,
        ref JobObjectExtendedLimitInformation information,
        uint informationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(SafeJobHandle job, nint process);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TerminateJobObject(SafeJobHandle job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);
}
