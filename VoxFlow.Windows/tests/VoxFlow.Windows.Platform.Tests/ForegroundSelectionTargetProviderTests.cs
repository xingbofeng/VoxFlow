using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class ForegroundSelectionTargetProviderTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 11, 15, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Capture_freezes_all_target_identity_and_safety_fields()
    {
        var api = new FakeForegroundSelectionApi(Probe());
        var provider = new Win32ForegroundSelectionTargetProvider(
            api,
            ownProcessId: 9000,
            timeProvider: new ControlledTimeProvider(Now));

        var result = provider.Capture();

        Assert.Equal(ForegroundTargetCaptureStatus.Captured, result.Status);
        var target = Assert.IsType<ForegroundTargetSnapshot>(result.Target);
        Assert.Equal(0x1234, target.WindowHandle);
        Assert.Equal(4242, target.ProcessId);
        Assert.Equal("notepad.exe", target.ProcessName);
        Assert.Equal("Draft", target.WindowTitle);
        Assert.Equal(new WindowBounds(10, 20, 800, 600), target.Bounds);
        Assert.Equal(ProcessIntegrityLevel.Medium, target.IntegrityLevel);
        Assert.Equal([42, 7, 3], target.FocusedElementRuntimeId);
        Assert.Equal(Now.ToUnixTimeMilliseconds(), target.CapturedAtUnixMs);
    }

    [Theory]
    [InlineData(ForegroundTargetCaptureStatus.SelfWindow)]
    [InlineData(ForegroundTargetCaptureStatus.SecureDesktop)]
    [InlineData(ForegroundTargetCaptureStatus.ProcessExited)]
    public void Self_secure_desktop_and_exited_process_are_rejected(
        ForegroundTargetCaptureStatus expected)
    {
        var probe = expected switch
        {
            ForegroundTargetCaptureStatus.SelfWindow => Probe(processId: 9000),
            ForegroundTargetCaptureStatus.SecureDesktop => Probe(isSecureDesktop: true),
            ForegroundTargetCaptureStatus.ProcessExited => Probe(isProcessAlive: false),
            _ => throw new ArgumentOutOfRangeException(nameof(expected)),
        };
        var provider = new Win32ForegroundSelectionTargetProvider(
            new FakeForegroundSelectionApi(probe),
            ownProcessId: 9000,
            timeProvider: new ControlledTimeProvider(Now));

        var result = provider.Capture();

        Assert.Equal(expected, result.Status);
        Assert.Null(result.Target);
    }

    [Fact]
    public void Missing_foreground_window_is_reported_without_a_snapshot()
    {
        var provider = new Win32ForegroundSelectionTargetProvider(
            new FakeForegroundSelectionApi(probe: null),
            ownProcessId: 9000,
            timeProvider: new ControlledTimeProvider(Now));

        var result = provider.Capture();

        Assert.Equal(ForegroundTargetCaptureStatus.NoForegroundWindow, result.Status);
        Assert.Null(result.Target);
    }

    [Fact]
    public void Windows_adapter_freezes_the_native_foreground_probe_at_trigger_time()
    {
        var native = new FakeNativeForegroundSelectionApi(Probe(
            focusedElementRuntimeId: [7, 11, 19],
            integrityLevel: ProcessIntegrityLevel.High));
        var api = new WindowsForegroundSelectionApi(native);

        var captured = api.ReadForeground();
        native.Replace(Probe(
            processId: 7777,
            focusedElementRuntimeId: [99],
            integrityLevel: ProcessIntegrityLevel.Low));

        var probe = Assert.IsType<ForegroundWindowProbe>(captured);
        Assert.Equal(4242, probe.ProcessId);
        Assert.Equal(ProcessIntegrityLevel.High, probe.IntegrityLevel);
        Assert.Equal([7, 11, 19], probe.FocusedElementRuntimeId);
    }

    private static ForegroundWindowProbe Probe(
        int processId = 4242,
        bool isSecureDesktop = false,
        bool isProcessAlive = true,
        IReadOnlyList<int>? focusedElementRuntimeId = null,
        ProcessIntegrityLevel integrityLevel = ProcessIntegrityLevel.Medium) => new(
        windowHandle: 0x1234,
        processId: processId,
        processName: "notepad.exe",
        windowTitle: "Draft",
        bounds: new WindowBounds(10, 20, 800, 600),
        integrityLevel: integrityLevel,
        focusedElementRuntimeId: focusedElementRuntimeId ?? [42, 7, 3],
        isSecureDesktop: isSecureDesktop,
        isPasswordElement: false,
        isProcessAlive: isProcessAlive);

    private sealed class FakeForegroundSelectionApi(ForegroundWindowProbe? probe)
        : IWin32ForegroundSelectionApi
    {
        public ForegroundWindowProbe? ReadForeground() => probe;
    }

    private sealed class FakeNativeForegroundSelectionApi(ForegroundWindowProbe? probe)
        : IWindowsForegroundSelectionNativeApi
    {
        private ForegroundWindowProbe? probe = probe;

        public ForegroundWindowProbe? ReadForegroundProbe() => probe;

        public void Replace(ForegroundWindowProbe? next) => probe = next;
    }
}
