using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

public enum ForegroundTargetCaptureStatus
{
    Captured,
    NoForegroundWindow,
    SelfWindow,
    SecureDesktop,
    SecureElement,
    ProcessExited,
}

public sealed record ForegroundTargetCaptureResult(
    ForegroundTargetCaptureStatus Status,
    ForegroundTargetSnapshot? Target);

public sealed record ForegroundWindowProbe
{
    public ForegroundWindowProbe(
        long windowHandle,
        int processId,
        string processName,
        string windowTitle,
        WindowBounds bounds,
        ProcessIntegrityLevel integrityLevel,
        IReadOnlyList<int> focusedElementRuntimeId,
        bool isSecureDesktop,
        bool isPasswordElement,
        bool isProcessAlive)
    {
        if (windowHandle == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(windowHandle));
        }
        if (processId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(processId));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(processName);
        ArgumentNullException.ThrowIfNull(windowTitle);
        ArgumentNullException.ThrowIfNull(bounds);
        if (!Enum.IsDefined(integrityLevel))
        {
            throw new ArgumentOutOfRangeException(
                nameof(integrityLevel),
                integrityLevel,
                null);
        }
        ArgumentNullException.ThrowIfNull(focusedElementRuntimeId);

        WindowHandle = windowHandle;
        ProcessId = processId;
        ProcessName = processName;
        WindowTitle = windowTitle;
        Bounds = bounds;
        IntegrityLevel = integrityLevel;
        FocusedElementRuntimeId = focusedElementRuntimeId.ToArray();
        IsSecureDesktop = isSecureDesktop;
        IsPasswordElement = isPasswordElement;
        IsProcessAlive = isProcessAlive;
    }

    public long WindowHandle { get; }

    public int ProcessId { get; }

    public string ProcessName { get; }

    public string WindowTitle { get; }

    public WindowBounds Bounds { get; }

    public ProcessIntegrityLevel IntegrityLevel { get; }

    public IReadOnlyList<int> FocusedElementRuntimeId { get; }

    public bool IsSecureDesktop { get; }

    public bool IsPasswordElement { get; }

    public bool IsProcessAlive { get; }
}

public interface IWin32ForegroundSelectionApi
{
    ForegroundWindowProbe? ReadForeground();
}

/// <summary>
/// Boundary behind the real Win32/UIA target reader.  Keeping this narrow lets
/// the trigger-time snapshot rule be verified without a live desktop.
/// </summary>
internal interface IWindowsForegroundSelectionNativeApi
{
    ForegroundWindowProbe? ReadForegroundProbe();
}

/// <summary>
/// Reads the foreground target synchronously at a hotkey boundary, before any
/// VoxFlow panel is allowed to take focus.  The returned probe is immutable so
/// later focus changes cannot alter the captured target.
/// </summary>
public sealed class WindowsForegroundSelectionApi : IWin32ForegroundSelectionApi
{
    private readonly IWindowsForegroundSelectionNativeApi native;

    public WindowsForegroundSelectionApi()
        : this(Win32ForegroundSelectionNativeApi.Instance)
    {
    }

    internal WindowsForegroundSelectionApi(IWindowsForegroundSelectionNativeApi native)
    {
        this.native = native ?? throw new ArgumentNullException(nameof(native));
    }

    public ForegroundWindowProbe? ReadForeground()
    {
        var probe = native.ReadForegroundProbe();
        return probe is null
            ? null
            : new ForegroundWindowProbe(
                probe.WindowHandle,
                probe.ProcessId,
                probe.ProcessName,
                probe.WindowTitle,
                new WindowBounds(
                    probe.Bounds.Left,
                    probe.Bounds.Top,
                    probe.Bounds.Width,
                    probe.Bounds.Height),
                probe.IntegrityLevel,
                probe.FocusedElementRuntimeId.ToArray(),
                probe.IsSecureDesktop,
                probe.IsPasswordElement,
                probe.IsProcessAlive);
    }
}

public sealed class Win32ForegroundSelectionTargetProvider
{
    private readonly IWin32ForegroundSelectionApi api;
    private readonly int ownProcessId;
    private readonly TimeProvider timeProvider;

    public Win32ForegroundSelectionTargetProvider(
        IWin32ForegroundSelectionApi api,
        int ownProcessId,
        TimeProvider timeProvider)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
        if (ownProcessId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(ownProcessId));
        }
        this.ownProcessId = ownProcessId;
        this.timeProvider = timeProvider
            ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public ForegroundTargetCaptureResult Capture()
    {
        var probe = api.ReadForeground();
        if (probe is null)
        {
            return Failure(ForegroundTargetCaptureStatus.NoForegroundWindow);
        }
        if (probe.ProcessId == ownProcessId)
        {
            return Failure(ForegroundTargetCaptureStatus.SelfWindow);
        }
        if (probe.IsSecureDesktop)
        {
            return Failure(ForegroundTargetCaptureStatus.SecureDesktop);
        }
        if (probe.IsPasswordElement)
        {
            return Failure(ForegroundTargetCaptureStatus.SecureElement);
        }
        if (!probe.IsProcessAlive)
        {
            return Failure(ForegroundTargetCaptureStatus.ProcessExited);
        }

        return new ForegroundTargetCaptureResult(
            ForegroundTargetCaptureStatus.Captured,
            new ForegroundTargetSnapshot(
                probe.WindowHandle,
                probe.ProcessId,
                probe.ProcessName,
                probe.WindowTitle,
                probe.Bounds,
                probe.IntegrityLevel,
                probe.FocusedElementRuntimeId,
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds()));
    }

    private static ForegroundTargetCaptureResult Failure(
        ForegroundTargetCaptureStatus status) => new(status, Target: null);
}

internal sealed class Win32ForegroundSelectionNativeApi
    : IWindowsForegroundSelectionNativeApi
{
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint TokenQuery = 0x0008;
    private const int TokenIntegrityLevel = 25;
    private const int SecurityMandatoryUntrustedRid = 0x0000;
    private const int SecurityMandatoryLowRid = 0x1000;
    private const int SecurityMandatoryMediumRid = 0x2000;
    private const int SecurityMandatoryMediumPlusRid = 0x2100;
    private const int SecurityMandatoryHighRid = 0x3000;
    private const int SecurityMandatorySystemRid = 0x4000;
    private const int SecurityMandatoryProtectedProcessRid = 0x5000;
    private const int MaximumWindowTitleLength = 32_767;

    public static Win32ForegroundSelectionNativeApi Instance { get; } = new();

    private Win32ForegroundSelectionNativeApi()
    {
    }

    public ForegroundWindowProbe? ReadForegroundProbe()
    {
        var handle = GetForegroundWindowNative();
        if (handle == nint.Zero)
        {
            return null;
        }

        _ = GetWindowThreadProcessIdNative(handle, out var nativeProcessId);
        if (nativeProcessId == 0 || nativeProcessId > int.MaxValue)
        {
            return null;
        }

        var processId = (int)nativeProcessId;
        var process = TryReadProcess(processId);
        if (process is null)
        {
            return null;
        }

        var processInfo = process.Value;
        try
        {
            if (!TryGetWindowRectNative(handle, out var rect))
            {
                return null;
            }

            var focus = ReadFocusedElement();
            return new ForegroundWindowProbe(
                handle.ToInt64(),
                processId,
                processInfo.Name,
                GetWindowText(handle),
                new WindowBounds(
                    rect.Left,
                    rect.Top,
                    Math.Max(1, rect.Right - rect.Left),
                    Math.Max(1, rect.Bottom - rect.Top)),
                ReadIntegrityLevel(processId),
                focus.RuntimeId,
                IsSecureDesktop(),
                focus.IsPassword,
                isProcessAlive: true);
        }
        finally
        {
            processInfo.Process.Dispose();
        }
    }

    private static (Process Process, string Name)? TryReadProcess(int processId)
    {
        try
        {
            var process = Process.GetProcessById(processId);
            if (process.HasExited)
            {
                process.Dispose();
                return null;
            }

            var name = process.ProcessName;
            return (process, name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                ? name
                : name + ".exe");
        }
        catch (Exception exception) when (exception is ArgumentException
            or InvalidOperationException
            or Win32Exception)
        {
            return null;
        }
    }

    private static (IReadOnlyList<int> RuntimeId, bool IsPassword) ReadFocusedElement()
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null)
            {
                return ([], false);
            }

            return (element.GetRuntimeId().ToArray(), element.Current.IsPassword);
        }
        catch (Exception exception) when (exception is ElementNotAvailableException
            or InvalidOperationException
            or COMException)
        {
            return ([], false);
        }
    }

    private static bool IsSecureDesktop()
    {
        var desktop = OpenInputDesktopNative(0, false, 0x0001);
        if (desktop == nint.Zero)
        {
            return false;
        }

        try
        {
            var bytes = 0u;
            _ = GetUserObjectInformationNative(desktop, 2, nint.Zero, 0, ref bytes);
            if (bytes < sizeof(char))
            {
                return false;
            }

            var buffer = Marshal.AllocHGlobal(checked((int)bytes));
            try
            {
                if (!GetUserObjectInformationNative(desktop, 2, buffer, bytes, ref bytes))
                {
                    return false;
                }

                var name = Marshal.PtrToStringUni(buffer);
                return !string.IsNullOrWhiteSpace(name)
                    && !string.Equals(name, "Default", StringComparison.OrdinalIgnoreCase);
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            _ = CloseDesktopNative(desktop);
        }
    }

    private static ProcessIntegrityLevel ReadIntegrityLevel(int processId)
    {
        var process = OpenProcessNative(
            ProcessQueryLimitedInformation,
            false,
            processId);
        if (process == nint.Zero)
        {
            return ProcessIntegrityLevel.Unknown;
        }

        nint token = nint.Zero;
        try
        {
            if (!OpenProcessTokenNative(process, TokenQuery, out token))
            {
                return ProcessIntegrityLevel.Unknown;
            }

            _ = GetTokenInformationNative(
                token,
                TokenIntegrityLevel,
                nint.Zero,
                0,
                out var bytes);
            if (bytes == 0)
            {
                return ProcessIntegrityLevel.Unknown;
            }

            var buffer = Marshal.AllocHGlobal(checked((int)bytes));
            try
            {
                if (!GetTokenInformationNative(
                        token,
                        TokenIntegrityLevel,
                        buffer,
                        bytes,
                        out _))
                {
                    return ProcessIntegrityLevel.Unknown;
                }

                var sid = Marshal.ReadIntPtr(buffer);
                var count = GetSidSubAuthorityCountNative(sid);
                if (count == nint.Zero)
                {
                    return ProcessIntegrityLevel.Unknown;
                }

                var subAuthority = GetSidSubAuthorityNative(sid, (uint)(Marshal.ReadByte(count) - 1));
                if (subAuthority == nint.Zero)
                {
                    return ProcessIntegrityLevel.Unknown;
                }

                return MapIntegrityLevel(Marshal.ReadInt32(subAuthority));
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            if (token != nint.Zero)
            {
                _ = CloseHandleNative(token);
            }

            _ = CloseHandleNative(process);
        }
    }

    private static ProcessIntegrityLevel MapIntegrityLevel(int rid) => rid switch
    {
        <= SecurityMandatoryUntrustedRid => ProcessIntegrityLevel.Untrusted,
        < SecurityMandatoryLowRid => ProcessIntegrityLevel.Untrusted,
        < SecurityMandatoryMediumRid => ProcessIntegrityLevel.Low,
        < SecurityMandatoryMediumPlusRid => ProcessIntegrityLevel.Medium,
        < SecurityMandatoryHighRid => ProcessIntegrityLevel.MediumPlus,
        < SecurityMandatorySystemRid => ProcessIntegrityLevel.High,
        < SecurityMandatoryProtectedProcessRid => ProcessIntegrityLevel.System,
        _ => ProcessIntegrityLevel.Protected,
    };

    private static string GetWindowText(nint windowHandle)
    {
        var length = Math.Clamp(GetWindowTextLengthNative(windowHandle) + 1, 1, MaximumWindowTitleLength + 1);
        var buffer = new StringBuilder(length);
        var copied = GetWindowTextNative(windowHandle, buffer, buffer.Capacity);
        return copied > 0 ? buffer.ToString(0, copied) : string.Empty;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    private static extern nint GetForegroundWindowNative();

    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId", SetLastError = true)]
    private static extern uint GetWindowThreadProcessIdNative(nint windowHandle, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowRect", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TryGetWindowRectNative(nint windowHandle, out Rect rect);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextLengthW", SetLastError = true)]
    private static extern int GetWindowTextLengthNative(nint windowHandle);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextNative(nint windowHandle, StringBuilder buffer, int maximumCount);

    [DllImport("user32.dll", EntryPoint = "OpenInputDesktop", SetLastError = true)]
    private static extern nint OpenInputDesktopNative(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint desiredAccess);

    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserObjectInformationNative(nint handle, int index, nint information, uint length, ref uint needed);

    [DllImport("user32.dll", EntryPoint = "CloseDesktop", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseDesktopNative(nint desktop);

    [DllImport("kernel32.dll", EntryPoint = "OpenProcess", SetLastError = true)]
    private static extern nint OpenProcessNative(uint desiredAccess, [MarshalAs(UnmanagedType.Bool)] bool inherit, int processId);

    [DllImport("advapi32.dll", EntryPoint = "OpenProcessToken", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessTokenNative(nint process, uint desiredAccess, out nint token);

    [DllImport("advapi32.dll", EntryPoint = "GetTokenInformation", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformationNative(nint token, int tokenInformationClass, nint tokenInformation, uint length, out uint requiredLength);

    [DllImport("advapi32.dll", EntryPoint = "GetSidSubAuthorityCount")]
    private static extern nint GetSidSubAuthorityCountNative(nint sid);

    [DllImport("advapi32.dll", EntryPoint = "GetSidSubAuthority")]
    private static extern nint GetSidSubAuthorityNative(nint sid, uint subAuthorityIndex);

    [DllImport("kernel32.dll", EntryPoint = "CloseHandle", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandleNative(nint handle);
}
