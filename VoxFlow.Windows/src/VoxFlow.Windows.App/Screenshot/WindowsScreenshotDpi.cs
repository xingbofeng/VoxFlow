using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

internal static class WindowsScreenshotDpi
{
    private const uint MonitorDefaultToNearest = 2;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private static readonly nint PerMonitorAwareV2 = new(-4);
    private static readonly nint Topmost = new(-1);

    public static void EnablePerMonitorV2()
    {
        if (SetProcessDpiAwarenessContext(PerMonitorAwareV2))
        {
            return;
        }

        // WPF or an application manifest may already have established the same
        // (or a stronger) process context. Windows reports ACCESS_DENIED then.
        const int accessDenied = 5;
        var error = Marshal.GetLastWin32Error();
        if (error != accessDenied)
        {
            throw new Win32Exception(error);
        }
    }

    public static (double DpiX, double DpiY) ReadMonitorDpi(CapturePixelRect bounds)
    {
        var point = new NativePoint
        {
            X = bounds.Left + (bounds.Width / 2),
            Y = bounds.Top + (bounds.Height / 2),
        };
        var monitor = MonitorFromPoint(point, MonitorDefaultToNearest);
        if (monitor != nint.Zero
            && GetDpiForMonitor(monitor, MonitorDpiType.Effective, out var dpiX, out var dpiY) == 0
            && dpiX > 0
            && dpiY > 0)
        {
            return (dpiX, dpiY);
        }

        return (96, 96);
    }

    public static void ApplyPhysicalBounds(Window window, CapturePixelRect bounds)
    {
        ArgumentNullException.ThrowIfNull(window);
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == nint.Zero)
        {
            throw new InvalidOperationException("The screenshot overlay handle is unavailable.");
        }

        if (!SetWindowPos(
                handle,
                Topmost,
                bounds.Left,
                bounds.Top,
                bounds.Width,
                bounds.Height,
                SwpNoActivate | SwpShowWindow))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    private enum MonitorDpiType
    {
        Effective = 0,
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetProcessDpiAwarenessContext(nint dpiContext);

    [DllImport("user32.dll")]
    private static extern nint MonitorFromPoint(
        NativePoint point,
        uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(
        nint monitor,
        MonitorDpiType dpiType,
        out uint dpiX,
        out uint dpiY);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint windowHandle,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
