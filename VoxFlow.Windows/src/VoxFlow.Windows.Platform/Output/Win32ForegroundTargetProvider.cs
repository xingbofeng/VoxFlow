using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
using VoxFlow.Windows.Application.Output;

namespace VoxFlow.Windows.Platform.Output;

public interface IWin32ForegroundTargetApi
{
    nint GetForegroundWindow();

    bool TryGetWindowProcessId(nint windowHandle, out int processId);

    ProcessPathLookup LookupProcessPath(int processId);

    string GetWindowText(nint windowHandle);
}

public enum ProcessPathLookupStatus
{
    Found,
    Missing,
    Unavailable,
}

public sealed record ProcessPathLookup
{
    private ProcessPathLookup(ProcessPathLookupStatus status, string? path)
    {
        if (status == ProcessPathLookupStatus.Found)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(path);
        }
        else if (path is not null)
        {
            throw new ArgumentException(
                "Only a successful process-path lookup may carry a path.",
                nameof(path));
        }

        Status = status;
        Path = path;
    }

    public ProcessPathLookupStatus Status { get; }

    public string? Path { get; }

    public static ProcessPathLookup Found(string path) =>
        new(ProcessPathLookupStatus.Found, path);

    public static ProcessPathLookup Missing { get; } =
        new(ProcessPathLookupStatus.Missing, null);

    public static ProcessPathLookup Unavailable { get; } =
        new(ProcessPathLookupStatus.Unavailable, null);
}

public sealed class Win32ForegroundTargetProvider : IForegroundTargetProvider
{
    private readonly IWin32ForegroundTargetApi api;

    public Win32ForegroundTargetProvider()
        : this(Win32ForegroundTargetApi.Instance)
    {
    }

    public Win32ForegroundTargetProvider(IWin32ForegroundTargetApi api)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
    }

    public ForegroundTargetIdentity? CaptureCurrent()
    {
        nint windowHandle;
        int processId;
        string? processPath;
        try
        {
            windowHandle = api.GetForegroundWindow();
            if (windowHandle == nint.Zero
                || !api.TryGetWindowProcessId(windowHandle, out processId)
                || processId <= 0)
            {
                return null;
            }

            var lookup = api.LookupProcessPath(processId);
            processPath = lookup.Status == ProcessPathLookupStatus.Found
                ? lookup.Path
                : null;
            if (string.IsNullOrWhiteSpace(processPath))
            {
                return null;
            }
        }
        catch (Exception exception) when (IsExpectedBoundaryFailure(exception))
        {
            return null;
        }

        string windowTitle;
        try
        {
            windowTitle = api.GetWindowText(windowHandle) ?? string.Empty;
        }
        catch (Exception exception) when (IsExpectedBoundaryFailure(exception))
        {
            // A title is diagnostic-only. Access restrictions must not erase
            // otherwise reliable PID/path/HWND identity.
            windowTitle = string.Empty;
        }

        return new ForegroundTargetIdentity(
            processId,
            processPath,
            windowHandle,
            windowTitle);
    }

    public ForegroundTargetLiveness GetLiveness(ForegroundTargetIdentity target)
    {
        ArgumentNullException.ThrowIfNull(target);
        try
        {
            var lookup = api.LookupProcessPath(target.ProcessId);
            return lookup.Status switch
            {
                ProcessPathLookupStatus.Missing => ForegroundTargetLiveness.Missing,
                ProcessPathLookupStatus.Unavailable => ForegroundTargetLiveness.Unknown,
                ProcessPathLookupStatus.Found when string.Equals(
                    NormalizePath(target.ProcessPath),
                    NormalizePath(lookup.Path!),
                    StringComparison.OrdinalIgnoreCase) => ForegroundTargetLiveness.Exists,
                ProcessPathLookupStatus.Found => ForegroundTargetLiveness.Missing,
                _ => ForegroundTargetLiveness.Unknown,
            };
        }
        catch (Exception exception) when (IsExpectedBoundaryFailure(exception))
        {
            return ForegroundTargetLiveness.Unknown;
        }
    }

    private static string NormalizePath(string path) =>
        path.Replace('/', '\\').TrimEnd('\\');

    private static bool IsExpectedBoundaryFailure(Exception exception) => exception is
        ArgumentException or
        InvalidOperationException or
        NotSupportedException or
        UnauthorizedAccessException or
        Win32Exception or
        ExternalException or
        SecurityException or
        DllNotFoundException or
        EntryPointNotFoundException;
}

internal sealed class Win32ForegroundTargetApi : IWin32ForegroundTargetApi
{
    private const int MaximumWindowTitleLength = 32_767;
    private const uint ProcessQueryLimitedInformation = 0x1000;

    public static Win32ForegroundTargetApi Instance { get; } = new();

    private Win32ForegroundTargetApi()
    {
    }

    public nint GetForegroundWindow() => GetForegroundWindowNative();

    public bool TryGetWindowProcessId(nint windowHandle, out int processId)
    {
        var threadId = GetWindowThreadProcessIdNative(windowHandle, out var nativeProcessId);
        processId = nativeProcessId <= int.MaxValue ? (int)nativeProcessId : 0;
        return threadId != 0 && processId > 0;
    }

    public ProcessPathLookup LookupProcessPath(int processId)
    {
        if (processId <= 0)
        {
            return ProcessPathLookup.Missing;
        }

        Process? process = null;
        nint processHandle = nint.Zero;
        try
        {
            process = Process.GetProcessById(processId);
            if (process.HasExited)
            {
                return ProcessPathLookup.Missing;
            }

            processHandle = OpenProcessNative(
                ProcessQueryLimitedInformation,
                inheritHandle: false,
                processId);
            if (processHandle == nint.Zero)
            {
                return HasExitedSafely(process)
                    ? ProcessPathLookup.Missing
                    : ProcessPathLookup.Unavailable;
            }

            var capacity = (uint)(MaximumWindowTitleLength + 1);
            var path = new StringBuilder((int)capacity);
            if (!QueryFullProcessImageNameNative(
                    processHandle,
                    flags: 0,
                    path,
                    ref capacity)
                || capacity == 0)
            {
                return HasExitedSafely(process)
                    ? ProcessPathLookup.Missing
                    : ProcessPathLookup.Unavailable;
            }

            return ProcessPathLookup.Found(path.ToString(0, (int)capacity));
        }
        catch (ArgumentException)
        {
            return ProcessPathLookup.Missing;
        }
        catch (Exception exception) when (IsExpectedProcessLookupFailure(exception))
        {
            return ProcessPathLookup.Unavailable;
        }
        finally
        {
            if (processHandle != nint.Zero)
            {
                _ = CloseHandleNative(processHandle);
            }

            process?.Dispose();
        }
    }

    private static bool HasExitedSafely(Process process)
    {
        try
        {
            return process.HasExited;
        }
        catch (Exception exception) when (IsExpectedProcessLookupFailure(exception))
        {
            return false;
        }
    }

    public string GetWindowText(nint windowHandle)
    {
        var reportedLength = GetWindowTextLengthNative(windowHandle);
        var capacity = Math.Clamp(reportedLength + 1, 1, MaximumWindowTitleLength + 1);
        var buffer = new StringBuilder(capacity);
        var copiedLength = GetWindowTextNative(windowHandle, buffer, buffer.Capacity);
        return copiedLength > 0 ? buffer.ToString(0, copiedLength) : string.Empty;
    }

    private static bool IsExpectedProcessLookupFailure(Exception exception) => exception is
        ArgumentException or
        InvalidOperationException or
        NotSupportedException or
        UnauthorizedAccessException or
        Win32Exception;

    [DllImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    private static extern nint GetForegroundWindowNative();

    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId", SetLastError = true)]
    private static extern uint GetWindowThreadProcessIdNative(
        nint windowHandle,
        out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextLengthW", SetLastError = true)]
    private static extern int GetWindowTextLengthNative(nint windowHandle);

    [DllImport(
        "user32.dll",
        EntryPoint = "GetWindowTextW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern int GetWindowTextNative(
        nint windowHandle,
        StringBuilder text,
        int maximumCount);

    [DllImport("kernel32.dll", EntryPoint = "OpenProcess", SetLastError = true)]
    private static extern nint OpenProcessNative(
        uint desiredAccess,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
        int processId);

    [DllImport(
        "kernel32.dll",
        EntryPoint = "QueryFullProcessImageNameW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageNameNative(
        nint processHandle,
        uint flags,
        StringBuilder executableName,
        ref uint size);

    [DllImport("kernel32.dll", EntryPoint = "CloseHandle", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandleNative(nint handle);
}
