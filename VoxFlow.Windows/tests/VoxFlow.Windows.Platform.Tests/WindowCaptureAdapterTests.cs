using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Agent;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WindowCaptureAdapterTests
{
    [Theory]
    [InlineData(false, true, false, false, WindowCaptureStatus.TargetClosed)]
    [InlineData(true, false, false, false, WindowCaptureStatus.TargetNotVisible)]
    [InlineData(true, true, true, false, WindowCaptureStatus.TargetMinimized)]
    [InlineData(true, true, false, true, WindowCaptureStatus.TargetProtected)]
    public void Rejects_closed_hidden_minimized_and_protected_windows_before_capturing(
        bool exists,
        bool visible,
        bool minimized,
        bool protectedWindow,
        WindowCaptureStatus expected)
    {
        var native = new FakeNative(new(exists, visible, minimized, protectedWindow, new(20, 30, 800, 600)));
        var store = new CapturingStore();

        var result = new WindowCaptureAdapter(native, store).Capture(Target(), "C:\\task");

        Assert.Equal(expected, result.Status);
        Assert.Equal(0, native.CaptureCount);
        Assert.Empty(store.Paths);
    }

    [Fact]
    public void Rejects_missing_extended_frame_bounds_and_black_frames_without_writing_media()
    {
        var noBounds = new FakeNative(new(true, true, false, false, null));
        var black = new FakeNative(new(true, true, false, false, new(200, 300, 1200, 900)), new([1, 2, 3], 100, 99));
        var store = new CapturingStore();

        Assert.Equal(WindowCaptureStatus.BoundsUnavailable,
            new WindowCaptureAdapter(noBounds, store).Capture(Target(), "C:\\task").Status);
        Assert.Equal(WindowCaptureStatus.BlackFrame,
            new WindowCaptureAdapter(black, store).Capture(Target(), "C:\\task").Status);
        Assert.Empty(store.Paths);
        Assert.Equal(0, noBounds.CaptureCount);
        Assert.Equal(1, black.CaptureCount);
    }

    [Fact]
    public void Captures_one_dwm_physical_frame_only_into_the_task_screenshots_directory()
    {
        var native = new FakeNative(
            new(true, true, false, false, new(-120, 48, 1500, 960)),
            new([0x89, 0x50, 0x4E, 0x47], 100, 2));
        var store = new CapturingStore();

        var result = new WindowCaptureAdapter(native, store).Capture(Target(), "C:\\task");

        Assert.True(result.Succeeded);
        Assert.Equal(new WindowCaptureBounds(-120, 48, 1500, 960), result.Bounds);
        Assert.Equal(1, native.CaptureCount);
        Assert.Single(store.Paths);
        Assert.StartsWith("C:\\task\\screenshots\\", store.Paths[0], StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Store_uses_a_direct_task_screenshots_child_and_never_a_product_media_directory()
    {
        using var directory = new TemporaryDirectory();
        var task = Path.Combine(directory.Path, "session-1");
        var path = new AgentTaskScreenshotStore().WritePng(task, [0x89, 0x50, 0x4E, 0x47]);

        Assert.True(File.Exists(path));
        Assert.Equal(Path.Combine(task, "screenshots"), Path.GetDirectoryName(path));
        Assert.DoesNotContain("media", path, StringComparison.OrdinalIgnoreCase);
    }

    private static ForegroundTargetSnapshot Target() => new(
        windowHandle: 123,
        processId: 456,
        processName: "target.exe",
        windowTitle: "Target",
        bounds: new WindowBounds(20, 30, 800, 600),
        integrityLevel: ProcessIntegrityLevel.Medium,
        focusedElementRuntimeId: [],
        capturedAtUnixMs: 1);

    private sealed class FakeNative(WindowCaptureProbe probe, WindowCaptureFrame? frame = null)
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

    private sealed class CapturingStore : IAgentTaskScreenshotStore
    {
        public List<string> Paths { get; } = [];

        public string WritePng(string taskWorkspace, ReadOnlySpan<byte> png)
        {
            var path = Path.Combine(taskWorkspace, "screenshots", $"{Paths.Count}.png");
            Paths.Add(path);
            return path;
        }
    }
}
