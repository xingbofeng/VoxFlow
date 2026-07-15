using System.ComponentModel;
using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Platform.Screenshot;

internal sealed record WindowsPhysicalDisplay(
    string DeviceName,
    CapturePixelRect Bounds,
    bool IsPrimary);

internal interface IWindowsPhysicalDisplayCatalog
{
    IReadOnlyList<WindowsPhysicalDisplay> GetActiveDisplays();
}

/// <summary>
/// Uses monitor APIs rather than WPF or WinForms geometry so coordinates remain physical pixels.
/// </summary>
internal sealed class WindowsPhysicalDisplayCatalog : IWindowsPhysicalDisplayCatalog
{
    private const uint MonitorInfoPrimary = 0x00000001;

    public static WindowsPhysicalDisplayCatalog Instance { get; } = new();

    private WindowsPhysicalDisplayCatalog()
    {
    }

    public IReadOnlyList<WindowsPhysicalDisplay> GetActiveDisplays()
    {
        var displays = new List<WindowsPhysicalDisplay>();
        var callback = new MonitorEnumerationCallback((monitor, _, _, _) =>
        {
            var info = new NativeMonitorInfo
            {
                Size = (uint)Marshal.SizeOf<NativeMonitorInfo>(),
            };
            if (!GetMonitorInfoNative(monitor, ref info))
            {
                return true;
            }

            var width = checked(info.Monitor.Right - info.Monitor.Left);
            var height = checked(info.Monitor.Bottom - info.Monitor.Top);
            if (width > 0 && height > 0 && !string.IsNullOrWhiteSpace(info.DeviceName))
            {
                displays.Add(new WindowsPhysicalDisplay(
                    NormalizeDeviceName(info.DeviceName),
                    new CapturePixelRect(info.Monitor.Left, info.Monitor.Top, width, height),
                    (info.Flags & MonitorInfoPrimary) != 0));
            }
            return true;
        });

        if (!EnumDisplayMonitorsNative(nint.Zero, nint.Zero, callback, nint.Zero))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        return displays
            .OrderBy(display => display.Bounds.Left)
            .ThenBy(display => display.Bounds.Top)
            .ThenBy(display => display.DeviceName, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    internal static string NormalizeDeviceName(string deviceName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);
        return deviceName.Trim().ToUpperInvariant();
    }

    private delegate bool MonitorEnumerationCallback(
        nint monitor,
        nint deviceContext,
        nint monitorRectangle,
        nint data);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeMonitorInfo
    {
        public uint Size;
        public NativeRect Monitor;
        public NativeRect WorkArea;
        public uint Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
    }

    [DllImport("user32.dll", EntryPoint = "EnumDisplayMonitors", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitorsNative(
        nint deviceContext,
        nint clippingRectangle,
        MonitorEnumerationCallback callback,
        nint data);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfoNative(nint monitor, ref NativeMonitorInfo info);
}
