using VoxFlow.Windows.Platform.Agent;
using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WindowTargetCatalogTests
{
    [Fact]
    public void Returns_frontmost_eligible_window_and_filters_non_user_targets()
    {
        var native = new FakeWindowTargetNative(
        [
            Probe(10, processId: 20, zOrder: 0, bounds: new(0, 0, 500, 400)),
            Probe(11, processId: 21, zOrder: 1, bounds: new(0, 0, 400, 300)),
            Probe(12, processId: 99, zOrder: 2, bounds: new(0, 0, 600, 500)),
            Probe(13, processId: 22, zOrder: 3, bounds: new(0, 0, 600, 500), isCloaked: true),
            Probe(14, processId: 23, zOrder: 4, bounds: new(0, 0, 600, 500), isTool: true),
            Probe(15, processId: 24, zOrder: 5, bounds: new(0, 0, 600, 500), isTransparent: true),
            Probe(16, processId: 25, zOrder: 6, bounds: new(0, 0, 600, 500), isProtected: true),
            Probe(17, processId: 26, zOrder: 7, bounds: new(0, 0, 50, 500)),
            Probe(18, processId: 27, zOrder: 8, bounds: new(0, 0, 600, 500), className: "WorkerW"),
        ]);
        var catalog = new WindowTargetCatalog(native, ownProcessId: 99);

        var targets = catalog.GetTargets(new HashSet<long> { 11 });
        var hovered = catalog.FindTopmostAt(
            new CapturePixelPoint(30, 30),
            new HashSet<long> { 11 });

        var target = Assert.Single(targets);
        Assert.Equal(10, target.WindowHandle);
        Assert.Equal(0, target.ZOrder);
        Assert.Equal(target, hovered);
    }

    [Fact]
    public void FindTopmostAt_uses_enumwindows_z_order_not_area_or_process_id()
    {
        var catalog = new WindowTargetCatalog(
            new FakeWindowTargetNative(
            [
                Probe(100, processId: 50, zOrder: 0, bounds: new(50, 50, 200, 200)),
                Probe(200, processId: 40, zOrder: 1, bounds: new(0, 0, 800, 600)),
            ]),
            ownProcessId: 999);

        var result = catalog.FindTopmostAt(new CapturePixelPoint(100, 100));

        Assert.NotNull(result);
        Assert.Equal(100, result.WindowHandle);
    }

    [Fact]
    public void Controlled_window_fallback_reuses_protected_and_black_frame_checks()
    {
        var protectedNative = new FakeWindowCaptureNative(
            new WindowCaptureProbe(true, true, false, true, new(0, 0, 640, 480)),
            frame: null);
        var blackNative = new FakeWindowCaptureNative(
            new WindowCaptureProbe(true, true, false, false, new(0, 0, 640, 480)),
            new WindowCaptureFrame([1, 2, 3], 100, 99));

        var protectedResult = new WindowOnlyCaptureFallback(protectedNative).Capture(123);
        var blackResult = new WindowOnlyCaptureFallback(blackNative).Capture(456);

        Assert.Equal(WindowCaptureStatus.TargetProtected, protectedResult.Status);
        Assert.Equal(0, protectedNative.CaptureCount);
        Assert.Equal(WindowCaptureStatus.BlackFrame, blackResult.Status);
        Assert.Equal(1, blackNative.CaptureCount);
        Assert.True(blackResult.Png.IsEmpty);
    }

    [Fact]
    public void Controlled_window_fallback_returns_an_owned_png_without_media_side_effects()
    {
        var png = new byte[] { 0x89, 0x50, 0x4E, 0x47 };
        var native = new FakeWindowCaptureNative(
            new WindowCaptureProbe(true, true, false, false, new(-20, 30, 640, 480)),
            new WindowCaptureFrame(png, 100, 1));

        var result = new WindowOnlyCaptureFallback(native).Capture(456);
        png[0] = 0;

        Assert.True(result.Succeeded);
        Assert.Equal(new WindowCaptureBounds(-20, 30, 640, 480), result.Bounds);
        Assert.Equal(0x89, result.Png.Span[0]);
    }

    private static WindowTargetProbe Probe(
        long handle,
        int processId,
        int zOrder,
        CapturePixelRect? bounds,
        bool isCloaked = false,
        bool isTool = false,
        bool isTransparent = false,
        bool isProtected = false,
        string className = "ApplicationWindow") =>
        new(
            handle,
            processId,
            bounds,
            IsVisible: true,
            IsMinimized: false,
            IsCloaked: isCloaked,
            IsToolWindow: isTool,
            IsTransparent: isTransparent,
            IsProtected: isProtected,
            className,
            zOrder);

    private sealed class FakeWindowTargetNative(IReadOnlyList<WindowTargetProbe> probes)
        : IWindowTargetNative
    {
        public IReadOnlyList<WindowTargetProbe> EnumerateTopLevelWindows() => probes;
    }

    private sealed class FakeWindowCaptureNative(
        WindowCaptureProbe probe,
        WindowCaptureFrame? frame)
        : IWindowCaptureNative
    {
        public int CaptureCount { get; private set; }

        public WindowCaptureProbe Probe(long windowHandle) => probe;

        public WindowCaptureFrame? Capture(long windowHandle, WindowCaptureBounds bounds)
        {
            CaptureCount++;
            return frame;
        }
    }
}
