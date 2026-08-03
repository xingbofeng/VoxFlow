using System.Runtime.InteropServices;
using System.Text;

namespace VoxFlow.Windows.Platform.Screenshot;

public sealed record WindowCaptureTarget(
    long WindowHandle,
    int ProcessId,
    CapturePixelRect Bounds,
    int ZOrder,
    string? Title = null);

internal sealed record WindowTargetProbe(
    long WindowHandle,
    int ProcessId,
    CapturePixelRect? Bounds,
    bool IsVisible,
    bool IsMinimized,
    bool IsCloaked,
    bool IsToolWindow,
    bool IsTransparent,
    bool IsProtected,
    string ClassName,
    int ZOrder,
    string? Title = null);

internal interface IWindowTargetNative
{
    IReadOnlyList<WindowTargetProbe> EnumerateTopLevelWindows();
}

/// <summary>Discovers capturable top-level windows in Win32 Z-order.</summary>
public sealed class WindowTargetCatalog
{
    public const int MinimumWindowEdgePixels = 50;

    private static readonly HashSet<string> ShellWindowClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "DV2ControlHost",
    };

    private readonly IWindowTargetNative native;
    private readonly int ownProcessId;

    public WindowTargetCatalog()
        : this(Win32WindowTargetNative.Instance, Environment.ProcessId)
    {
    }

    internal WindowTargetCatalog(IWindowTargetNative native, int ownProcessId)
    {
        this.native = native ?? throw new ArgumentNullException(nameof(native));
        if (ownProcessId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(ownProcessId));
        }
        this.ownProcessId = ownProcessId;
    }

    public IReadOnlyList<WindowCaptureTarget> GetTargets(
        IReadOnlySet<long>? excludedWindowHandles = null) =>
        native.EnumerateTopLevelWindows()
            .Where(probe => IsEligible(probe, excludedWindowHandles))
            .OrderBy(probe => probe.ZOrder)
            .Select(probe => new WindowCaptureTarget(
                probe.WindowHandle,
                probe.ProcessId,
                probe.Bounds!.Value,
                probe.ZOrder,
                probe.Title))
            .ToArray();

    public WindowCaptureTarget? FindTopmostAt(
        CapturePixelPoint point,
        IReadOnlySet<long>? excludedWindowHandles = null) =>
        GetTargets(excludedWindowHandles)
            .FirstOrDefault(target => target.Bounds.Contains(point));

    private bool IsEligible(
        WindowTargetProbe probe,
        IReadOnlySet<long>? excludedWindowHandles)
    {
        if (probe.WindowHandle == 0
            || probe.ProcessId <= 0
            || probe.ProcessId == ownProcessId
            || excludedWindowHandles?.Contains(probe.WindowHandle) == true
            || !probe.IsVisible
            || probe.IsMinimized
            || probe.IsCloaked
            || probe.IsToolWindow
            || probe.IsTransparent
            || probe.IsProtected
            || probe.Bounds is not { } bounds
            || bounds.Width <= MinimumWindowEdgePixels
            || bounds.Height <= MinimumWindowEdgePixels
            || ShellWindowClasses.Contains(probe.ClassName))
        {
            return false;
        }
        return true;
    }
}

internal sealed class Win32WindowTargetNative : IWindowTargetNative
{
    private const int GwlExtendedStyle = -20;
    private const long WsExTransparent = 0x00000020L;
    private const long WsExToolWindow = 0x00000080L;
    private const uint DwmwaExtendedFrameBounds = 9;
    private const uint DwmwaCloaked = 14;
    private const uint WdaMonitor = 1;
    private const uint WdaExcludeFromCapture = 0x11;

    public static Win32WindowTargetNative Instance { get; } = new();

    private Win32WindowTargetNative()
    {
    }

    public IReadOnlyList<WindowTargetProbe> EnumerateTopLevelWindows()
    {
        var probes = new List<WindowTargetProbe>();
        var zOrder = 0;
        var callback = new WindowEnumerationCallback((handle, _) =>
        {
            var probe = ReadProbe(handle, zOrder++);
            if (probe is not null)
            {
                probes.Add(probe);
            }
            return true;
        });
        if (!EnumWindowsNative(callback, nint.Zero))
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        return probes;
    }

    private static WindowTargetProbe? ReadProbe(nint handle, int zOrder)
    {
        if (handle == nint.Zero || !IsWindowNative(handle))
        {
            return null;
        }

        _ = GetWindowThreadProcessIdNative(handle, out var nativeProcessId);
        if (nativeProcessId == 0 || nativeProcessId > int.MaxValue)
        {
            return null;
        }

        var extendedStyle = GetWindowLongPtrNative(handle, GwlExtendedStyle).ToInt64();
        var isCloaked = DwmGetWindowAttributeIntNative(
                handle,
                DwmwaCloaked,
                out var cloaked,
                sizeof(int)) == 0
            && cloaked != 0;
        var isProtected = GetWindowDisplayAffinityNative(handle, out var affinity)
            && affinity is WdaMonitor or WdaExcludeFromCapture;
        CapturePixelRect? bounds = null;
        if (DwmGetWindowAttributeRectNative(
                handle,
                DwmwaExtendedFrameBounds,
                out var rectangle,
                Marshal.SizeOf<NativeRect>()) == 0)
        {
            var width = rectangle.Right - rectangle.Left;
            var height = rectangle.Bottom - rectangle.Top;
            if (width > 0 && height > 0)
            {
                bounds = new CapturePixelRect(rectangle.Left, rectangle.Top, width, height);
            }
        }

        return new WindowTargetProbe(
            handle.ToInt64(),
            (int)nativeProcessId,
            bounds,
            IsWindowVisibleNative(handle),
            IsIconicNative(handle),
            isCloaked,
            (extendedStyle & WsExToolWindow) != 0,
            (extendedStyle & WsExTransparent) != 0,
            isProtected,
            GetClassName(handle),
            zOrder,
            GetWindowTitle(handle));
    }

    private static string GetClassName(nint handle)
    {
        var name = new StringBuilder(256);
        return GetClassNameNative(handle, name, name.Capacity) > 0
            ? name.ToString()
            : string.Empty;
    }

    private static string? GetWindowTitle(nint handle)
    {
        var length = GetWindowTextLengthNative(handle);
        if (length <= 0)
        {
            return null;
        }

        var title = new StringBuilder(Math.Min(length + 1, 2048));
        return GetWindowTextNative(handle, title, title.Capacity) > 0
            ? title.ToString()
            : null;
    }

    private delegate bool WindowEnumerationCallback(nint windowHandle, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", EntryPoint = "EnumWindows", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindowsNative(WindowEnumerationCallback callback, nint data);

    [DllImport("user32.dll", EntryPoint = "IsWindow", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "IsWindowVisible", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisibleNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "IsIconic", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconicNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId", SetLastError = true)]
    private static extern uint GetWindowThreadProcessIdNative(nint handle, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtrNative(nint handle, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowDisplayAffinity", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowDisplayAffinityNative(nint handle, out uint affinity);

    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetClassNameNative(nint handle, StringBuilder className, int maximumCount);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextLengthW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextLengthNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextNative(nint handle, StringBuilder title, int maximumCount);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int DwmGetWindowAttributeRectNative(
        nint handle,
        uint attribute,
        out NativeRect value,
        int valueSize);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int DwmGetWindowAttributeIntNative(
        nint handle,
        uint attribute,
        out int value,
        int valueSize);
}
