using VoxFlow.Windows.Platform.Agent;

namespace VoxFlow.Windows.Platform.Screenshot;

public sealed record WindowOnlyCaptureResult(
    WindowCaptureStatus Status,
    WindowCaptureBounds? Bounds,
    ReadOnlyMemory<byte> Png)
{
    public bool Succeeded => Status == WindowCaptureStatus.Captured;
}

/// <summary>
/// Controlled fallback for an explicitly requested independent window frame.
/// It is intentionally incapable of replacing a failed full-display DX11 capture.
/// </summary>
public sealed class WindowOnlyCaptureFallback
{
    private const double BlackFrameRatio = 0.98;
    private readonly IWindowCaptureNative native;

    public WindowOnlyCaptureFallback()
        : this(new DwmWindowCaptureNative())
    {
    }

    public WindowOnlyCaptureFallback(IWindowCaptureNative native)
    {
        this.native = native ?? throw new ArgumentNullException(nameof(native));
    }

    public WindowOnlyCaptureResult Capture(long windowHandle)
    {
        var probe = native.Probe(windowHandle);
        if (!probe.Exists)
        {
            return Failure(WindowCaptureStatus.TargetClosed);
        }
        if (probe.IsProtected)
        {
            return Failure(WindowCaptureStatus.TargetProtected);
        }
        if (probe.IsMinimized)
        {
            return Failure(WindowCaptureStatus.TargetMinimized);
        }
        if (!probe.IsVisible)
        {
            return Failure(WindowCaptureStatus.TargetNotVisible);
        }
        if (probe.ExtendedFrameBounds is not { IsUsable: true } bounds)
        {
            return Failure(WindowCaptureStatus.BoundsUnavailable);
        }

        var frame = native.Capture(windowHandle, bounds);
        if (frame is null || frame.Png.Length == 0 || frame.SampledPixelCount <= 0)
        {
            return Failure(WindowCaptureStatus.CaptureFailed, bounds);
        }
        if (frame.DarkPixelCount / (double)frame.SampledPixelCount >= BlackFrameRatio)
        {
            return Failure(WindowCaptureStatus.BlackFrame, bounds);
        }

        return new WindowOnlyCaptureResult(
            WindowCaptureStatus.Captured,
            bounds,
            frame.Png.ToArray());
    }

    private static WindowOnlyCaptureResult Failure(
        WindowCaptureStatus status,
        WindowCaptureBounds? bounds = null) =>
        new(status, bounds, ReadOnlyMemory<byte>.Empty);
}
