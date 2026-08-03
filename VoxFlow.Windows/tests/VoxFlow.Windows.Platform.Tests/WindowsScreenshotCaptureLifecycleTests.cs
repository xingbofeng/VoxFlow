using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WindowsScreenshotCaptureLifecycleTests
{
    [Fact]
    public void Display_and_device_window_messages_invalidate_the_capture_service()
    {
        var sink = new CapturingInvalidationSink();
        using var lifecycle = new WindowsScreenshotCaptureLifecycle(sink);

        Assert.True(lifecycle.HandleWindowMessage(WindowsScreenshotCaptureLifecycle.DisplayChangeMessage));
        Assert.True(lifecycle.HandleWindowMessage(WindowsScreenshotCaptureLifecycle.DeviceChangeMessage));
        Assert.False(lifecycle.HandleWindowMessage(0x0100));

        Assert.Equal(
            new[]
            {
                ScreenshotCaptureInvalidationReason.DisplayChange,
                ScreenshotCaptureInvalidationReason.DeviceChange,
            },
            sink.Reasons);
    }

    [Fact]
    public void Shutdown_marks_the_process_scoped_service_for_rebuild_or_disposal()
    {
        var sink = new CapturingInvalidationSink();
        using var lifecycle = new WindowsScreenshotCaptureLifecycle(sink);

        lifecycle.Shutdown();

        Assert.Equal(
            ScreenshotCaptureInvalidationReason.ApplicationShutdown,
            Assert.Single(sink.Reasons));
    }

    private sealed class CapturingInvalidationSink : IScreenshotCaptureInvalidationSink
    {
        public List<ScreenshotCaptureInvalidationReason> Reasons { get; } = [];

        public void Invalidate(ScreenshotCaptureInvalidationReason reason) => Reasons.Add(reason);
    }
}
