using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class Dx11ScreenshotLiveTests
{
    [Fact]
    public async Task Explicit_live_smoke_freezes_every_real_dx11_display()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("VOICEINPUT_TEST_WINDOWS_SCREEN_CAPTURE"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        using var source = new Dx11ScreenshotFrameSource();
        var readiness = source.GetReadiness();
        Assert.True(
            readiness.IsReady,
            $"Capture readiness was {readiness.Status}; active={readiness.ActiveDisplayCount}, mapped={readiness.MappedDisplayCount}, adapters={readiness.AdapterCount}.");

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        var desktop = await source.FreezeAllDisplaysAsync(TimeSpan.FromSeconds(3), timeout.Token);

        Assert.Equal(readiness.ActiveDisplayCount, desktop.Frames.Count);
        Assert.All(desktop.Frames, frame =>
        {
            Assert.Equal(checked(frame.Bounds.Width * 4), frame.Stride);
            Assert.Equal(checked(frame.Stride * frame.Bounds.Height), frame.Bgra.Length);
            Assert.Contains(frame.Bgra.ToArray(), value => value != 0);
        });
        var crop = desktop.Crop(desktop.Frames[0].Bounds);
        Assert.Equal(desktop.Frames[0].Bounds.Width, crop.Width);
        Assert.Equal(desktop.Frames[0].Bounds.Height, crop.Height);

        var readinessAfterCapture = source.GetReadiness();
        Assert.True(
            readinessAfterCapture.IsReady,
            $"A successful native capture unexpectedly opened the process circuit ({readinessAfterCapture.Status}).");
        var secondDesktop = await source.FreezeAllDisplaysAsync(TimeSpan.FromSeconds(3), timeout.Token);
        Assert.Equal(desktop.Frames.Count, secondDesktop.Frames.Count);
    }
}
