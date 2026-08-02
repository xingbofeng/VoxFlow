using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Platform.Screenshot;

public interface IScreenshotWindowActivation
{
    nint CaptureForegroundWindow();

    void SetNoActivate(nint windowHandle, bool enabled);

    bool RestoreForegroundWindow(nint windowHandle);
}

public sealed class WindowsScreenshotWindowActivation : IScreenshotWindowActivation
{
    private const int GwlExtendedStyle = -20;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpFrameChanged = 0x0020;

    public const int WsExNoActivate = 0x08000000;
    public const int WmMouseActivate = 0x0021;
    public const int MaNoActivate = 3;

    public static WindowsScreenshotWindowActivation Shared { get; } = new();

    public nint CaptureForegroundWindow() => GetForegroundWindowNative();

    public void SetNoActivate(nint windowHandle, bool enabled)
    {
        if (windowHandle == nint.Zero)
        {
            return;
        }
        var current = GetWindowLongPtrNative(windowHandle, GwlExtendedStyle).ToInt64();
        var updated = enabled
            ? current | WsExNoActivate
            : current & ~((long)WsExNoActivate);
        if (updated != current)
        {
            _ = SetWindowLongPtrNative(windowHandle, GwlExtendedStyle, new nint(updated));
            _ = SetWindowPosNative(
                windowHandle,
                insertAfter: nint.Zero,
                x: 0,
                y: 0,
                width: 0,
                height: 0,
                SwpNoSize | SwpNoMove | SwpNoZOrder | SwpNoActivate | SwpFrameChanged);
        }
    }

    public bool RestoreForegroundWindow(nint windowHandle) =>
        windowHandle != nint.Zero
        && IsWindowNative(windowHandle)
        && SetForegroundWindowNative(windowHandle);

    [DllImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    private static extern nint GetForegroundWindowNative();

    [DllImport("user32.dll", EntryPoint = "SetForegroundWindow", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindowNative(nint windowHandle);

    [DllImport("user32.dll", EntryPoint = "IsWindow")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowNative(nint windowHandle);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtrNative(nint windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtrNative(
        nint windowHandle,
        int index,
        nint newValue);

    [DllImport("user32.dll", EntryPoint = "SetWindowPos", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPosNative(
        nint windowHandle,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
