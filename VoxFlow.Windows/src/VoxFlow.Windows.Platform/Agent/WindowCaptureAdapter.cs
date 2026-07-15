using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Agent;

public enum WindowCaptureStatus
{
    Captured,
    TargetClosed,
    TargetNotVisible,
    TargetMinimized,
    TargetProtected,
    BoundsUnavailable,
    BlackFrame,
    CaptureFailed,
}

/// <summary>Physical-pixel DWM frame bounds. They are intentionally not WPF
/// DIPs: PrintWindow and DWM always operate in device pixels.</summary>
public sealed record WindowCaptureBounds(int Left, int Top, int Width, int Height)
{
    public bool IsUsable => Width > 0 && Height > 0;
}

public sealed record WindowCaptureProbe(
    bool Exists,
    bool IsVisible,
    bool IsMinimized,
    bool IsProtected,
    WindowCaptureBounds? ExtendedFrameBounds);

public sealed record WindowCaptureFrame(
    byte[] Png,
    int SampledPixelCount,
    int DarkPixelCount);

public sealed record WindowCaptureResult(
    WindowCaptureStatus Status,
    string? ScreenshotPath = null,
    WindowCaptureBounds? Bounds = null)
{
    public bool Succeeded => Status == WindowCaptureStatus.Captured;
}

public interface IWindowCaptureNative
{
    WindowCaptureProbe Probe(long windowHandle);

    WindowCaptureFrame? Capture(long windowHandle, WindowCaptureBounds bounds);
}

public interface IAgentTaskScreenshotStore
{
    string WritePng(string taskWorkspace, ReadOnlySpan<byte> png);
}

/// <summary>Stores a capture only in the task-local transient directory.
/// Callers never provide a filename, preventing model/UI input from choosing
/// a product-media or user-data location.</summary>
public sealed class AgentTaskScreenshotStore : IAgentTaskScreenshotStore
{
    public const string DirectoryName = "screenshots";

    public string WritePng(string taskWorkspace, ReadOnlySpan<byte> png)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(taskWorkspace);
        if (png.Length == 0)
        {
            throw new ArgumentException("A screenshot must contain PNG data.", nameof(png));
        }

        var workspace = Path.GetFullPath(taskWorkspace);
        var screenshots = Path.GetFullPath(Path.Combine(workspace, DirectoryName));
        if (!string.Equals(
                Path.GetDirectoryName(screenshots),
                workspace,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("The screenshot directory must be a direct task-workspace child.", nameof(taskWorkspace));
        }

        Directory.CreateDirectory(screenshots);
        var path = Path.Combine(screenshots, $"ocr-{Guid.NewGuid():N}.png");
        File.WriteAllBytes(path, png.ToArray());
        return path;
    }
}

/// <summary>Captures at most one controlled frame from the frozen foreground
/// target. A failed capture is only a context warning; it is never a reason to
/// block the Agent voice workflow.</summary>
public sealed class WindowCaptureAdapter
{
    private const double BlackFrameRatio = 0.98;
    private readonly IWindowCaptureNative native;
    private readonly IAgentTaskScreenshotStore screenshots;

    public WindowCaptureAdapter(
        IWindowCaptureNative native,
        IAgentTaskScreenshotStore screenshots)
    {
        this.native = native ?? throw new ArgumentNullException(nameof(native));
        this.screenshots = screenshots ?? throw new ArgumentNullException(nameof(screenshots));
    }

    public WindowCaptureResult Capture(ForegroundTargetSnapshot target, string taskWorkspace)
    {
        ArgumentNullException.ThrowIfNull(target);
        ArgumentException.ThrowIfNullOrWhiteSpace(taskWorkspace);
        if (target.IntegrityLevel == ProcessIntegrityLevel.Protected)
        {
            return new(WindowCaptureStatus.TargetProtected);
        }

        var probe = native.Probe(target.WindowHandle);
        if (!probe.Exists)
        {
            return new(WindowCaptureStatus.TargetClosed);
        }
        if (probe.IsProtected)
        {
            return new(WindowCaptureStatus.TargetProtected);
        }
        if (probe.IsMinimized)
        {
            return new(WindowCaptureStatus.TargetMinimized);
        }
        if (!probe.IsVisible)
        {
            return new(WindowCaptureStatus.TargetNotVisible);
        }
        if (probe.ExtendedFrameBounds is not { IsUsable: true } bounds)
        {
            return new(WindowCaptureStatus.BoundsUnavailable);
        }

        var frame = native.Capture(target.WindowHandle, bounds);
        if (frame is null || frame.Png.Length == 0 || frame.SampledPixelCount <= 0)
        {
            return new(WindowCaptureStatus.CaptureFailed, Bounds: bounds);
        }
        if (frame.DarkPixelCount / (double)frame.SampledPixelCount >= BlackFrameRatio)
        {
            return new(WindowCaptureStatus.BlackFrame, Bounds: bounds);
        }

        return new(WindowCaptureStatus.Captured, screenshots.WritePng(taskWorkspace, frame.Png), bounds);
    }
}

/// <summary>Windows implementation backed by DWM extended bounds and
/// PrintWindow. No screen-wide capture, clipboard, upload, or PATH lookup is
/// involved.</summary>
public sealed class DwmWindowCaptureNative : IWindowCaptureNative
{
    private const uint DwmwaExtendedFrameBounds = 9;
    private const uint WdaMonitor = 1;
    private const uint WdaExcludeFromCapture = 0x11;
    private const uint PrintWindowRenderFullContent = 2;

    public WindowCaptureProbe Probe(long windowHandle)
    {
        var handle = new nint(windowHandle);
        if (handle == nint.Zero || !IsWindowNative(handle))
        {
            return new(false, false, false, false, null);
        }

        var protectedWindow = GetWindowDisplayAffinityNative(handle, out var affinity)
            && affinity is WdaMonitor or WdaExcludeFromCapture;
        var status = DwmGetWindowAttributeNative(
            handle,
            DwmwaExtendedFrameBounds,
            out var rect,
            Marshal.SizeOf<NativeRect>());
        var bounds = status == 0
            ? new WindowCaptureBounds(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top)
            : null;
        return new(
            Exists: true,
            IsVisible: IsWindowVisibleNative(handle),
            IsMinimized: IsIconicNative(handle),
            IsProtected: protectedWindow,
            ExtendedFrameBounds: bounds);
    }

    public WindowCaptureFrame? Capture(long windowHandle, WindowCaptureBounds bounds)
    {
        var handle = new nint(windowHandle);
        try
        {
            using var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppPArgb);
            using var graphics = Graphics.FromImage(bitmap);
            var targetDeviceContext = graphics.GetHdc();
            try
            {
                if (!PrintWindowNative(handle, targetDeviceContext, PrintWindowRenderFullContent))
                {
                    return null;
                }
            }
            finally
            {
                graphics.ReleaseHdc(targetDeviceContext);
            }

            var (sampled, dark) = CountDarkPixels(bitmap);
            using var stream = new MemoryStream();
            bitmap.Save(stream, ImageFormat.Png);
            return new(stream.ToArray(), sampled, dark);
        }
        catch (ArgumentException)
        {
            return null;
        }
        catch (ExternalException)
        {
            return null;
        }
    }

    private static (int Sampled, int Dark) CountDarkPixels(Bitmap bitmap)
    {
        var step = Math.Max(1, Math.Max(bitmap.Width, bitmap.Height) / 96);
        var sampled = 0;
        var dark = 0;
        for (var y = 0; y < bitmap.Height; y += step)
        {
            for (var x = 0; x < bitmap.Width; x += step)
            {
                var pixel = bitmap.GetPixel(x, y);
                sampled++;
                if (pixel.R <= 8 && pixel.G <= 8 && pixel.B <= 8)
                {
                    dark++;
                }
            }
        }
        return (sampled, dark);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", EntryPoint = "IsWindow", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "IsWindowVisible", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisibleNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "IsIconic", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconicNative(nint handle);

    [DllImport("user32.dll", EntryPoint = "GetWindowDisplayAffinity", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowDisplayAffinityNative(nint handle, out uint affinity);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int DwmGetWindowAttributeNative(
        nint handle,
        uint attribute,
        out NativeRect value,
        int valueSize);

    [DllImport("user32.dll", EntryPoint = "PrintWindow", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PrintWindowNative(nint handle, nint deviceContext, uint flags);
}
