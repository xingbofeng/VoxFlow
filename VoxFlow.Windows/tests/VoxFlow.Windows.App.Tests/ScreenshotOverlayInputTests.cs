using System.Windows.Input;
using System.Windows.Threading;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotOverlayInputTests
{
    [Fact]
    public void Copy_shortcut_matches_macOS_completion_and_annotation_branches()
    {
        Assert.Equal(
            ScreenshotCopyShortcutAction.CompleteSelection,
            ScreenshotOverlayInputPolicy.ResolveCopyShortcut(
                hasValidRegion: true,
                selectedAnnotationCount: 0));
        Assert.Equal(
            ScreenshotCopyShortcutAction.CopySelectedAnnotations,
            ScreenshotOverlayInputPolicy.ResolveCopyShortcut(
                hasValidRegion: true,
                selectedAnnotationCount: 2));
        Assert.Equal(
            ScreenshotCopyShortcutAction.Ignore,
            ScreenshotOverlayInputPolicy.ResolveCopyShortcut(
                hasValidRegion: false,
                selectedAnnotationCount: 0));
    }

    [Fact]
    public void Text_editor_reserves_escape_while_regular_text_keys_stay_in_the_editor()
    {
        Assert.True(ScreenshotOverlayInputPolicy.ShouldForwardFromTextEditor(Key.Escape));
        Assert.False(ScreenshotOverlayInputPolicy.ShouldForwardFromTextEditor(Key.Enter));
        Assert.False(ScreenshotOverlayInputPolicy.ShouldForwardFromTextEditor(Key.C));
    }

    [Fact]
    public void Mouse_activation_is_suppressed_except_during_explicit_text_editing()
    {
        Assert.True(ScreenshotOverlayWindow.ShouldSuppressMouseActivation(
            WindowsScreenshotWindowActivation.WmMouseActivate,
            isTextEditing: false));
        Assert.False(ScreenshotOverlayWindow.ShouldSuppressMouseActivation(
            WindowsScreenshotWindowActivation.WmMouseActivate,
            isTextEditing: true));
        Assert.False(ScreenshotOverlayWindow.ShouldSuppressMouseActivation(
            message: 0x0201,
            isTextEditing: false));
    }

    [Fact]
    public async Task Overlay_session_captures_and_restores_foreground_and_releases_hook_ownership()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var activation = new CapturingActivation();
            var keyboard = new ScreenshotKeyboardHookRouter();
            using var coordinator = new ScreenshotOverlayCoordinator(
                new WindowTargetCatalog(),
                Dispatcher.CurrentDispatcher,
                inlineTranslation: null,
                keyboard,
                activation);
            coordinator.PreserveForegroundWindow();
            var frame = new FrozenDisplayFrame(
                "DISPLAY1",
                "adapter",
                new CapturePixelRect(0, 0, 160, 90),
                rotationDegrees: 0,
                stride: 640,
                new byte[640 * 90]);
            var run = coordinator.RunAsync(
                new FrozenDesktop([frame]),
                Guid.NewGuid());

            Assert.Equal(1, activation.CaptureCalls);
            Assert.All(activation.NoActivateStates, Assert.True);
            Assert.Equal([new nint(4321)], activation.RestoredWindows);
            var escape = keyboard.Route(HookKey(0x1B, KeyTransition.Down));
            Assert.True(escape.Consume);
            keyboard.Dispatch(Assert.IsType<ScreenshotKeyboardRoutedCommand>(
                escape.ScreenshotCommand));

            Assert.Null(await run.WaitAsync(TimeSpan.FromSeconds(5)));
            Assert.Equal(2, activation.RestoredWindows.Count(static handle =>
                handle == new nint(4321)));
            Assert.True(keyboard.Route(HookKey(0x1B, KeyTransition.Up)).Consume);

            var retry = coordinator.RunAsync(
                new FrozenDesktop([frame]),
                Guid.NewGuid());
            Assert.Equal(1, activation.CaptureCalls);
            var retryEscape = keyboard.Route(HookKey(0x1B, KeyTransition.Down));
            Assert.True(retryEscape.Consume);
            keyboard.Dispatch(Assert.IsType<ScreenshotKeyboardRoutedCommand>(
                retryEscape.ScreenshotCommand));
            Assert.Null(await retry.WaitAsync(TimeSpan.FromSeconds(5)));
            Assert.Equal(4, activation.RestoredWindows.Count(static handle =>
                handle == new nint(4321)));
            Assert.True(keyboard.Route(HookKey(0x1B, KeyTransition.Up)).Consume);
            Assert.False(keyboard.Route(HookKey(0x41, KeyTransition.Down)).Consume);
        });
    }

    [Theory]
    [InlineData(true, true, true, true, (int)ScreenshotEscapeDisposition.CancelTextDraft)]
    [InlineData(false, true, true, true, (int)ScreenshotEscapeDisposition.CloseStylePopover)]
    [InlineData(false, false, true, true, (int)ScreenshotEscapeDisposition.CancelAnnotationPreview)]
    [InlineData(false, false, false, true, (int)ScreenshotEscapeDisposition.ClearAnnotationSelection)]
    [InlineData(false, false, false, false, (int)ScreenshotEscapeDisposition.CancelSession)]
    public void Escape_resolves_one_child_layer_at_a_time_before_cancelling_the_session(
        bool hasTextDraft,
        bool hasStylePopover,
        bool hasAnnotationPreview,
        bool hasAnnotationSelection,
        int expected)
    {
        Assert.Equal(
            (ScreenshotEscapeDisposition)expected,
            ScreenshotOverlayCoordinator.ResolveEscapeDisposition(
                hasTextDraft,
                hasStylePopover,
                hasAnnotationPreview,
                hasAnnotationSelection));
    }

    [Fact]
    public void Completed_shape_gestures_are_deselected_so_copy_completes_the_screenshot()
    {
        Assert.True(ScreenshotOverlayInputPolicy.ShouldClearSelectionAfterCommit(
            ScreenshotTool.Ellipse));
        Assert.True(ScreenshotOverlayInputPolicy.ShouldClearSelectionAfterCommit(
            ScreenshotTool.DotMarker));
        Assert.False(ScreenshotOverlayInputPolicy.ShouldClearSelectionAfterCommit(
            ScreenshotTool.Text));
        Assert.False(ScreenshotOverlayInputPolicy.ShouldClearSelectionAfterCommit(
            ScreenshotTool.Select));
    }

    [Fact]
    public void Window_candidate_click_and_drag_are_distinguished_in_physical_pixels()
    {
        var start = new PixelPoint(-1200, 200);

        Assert.False(ScreenshotOverlayInputPolicy.ShouldBeginFreeRegionFromWindowCandidate(
            start,
            new PixelPoint(-1199, 201)));
        Assert.True(ScreenshotOverlayInputPolicy.ShouldBeginFreeRegionFromWindowCandidate(
            start,
            new PixelPoint(-1198, 201)));
        Assert.True(ScreenshotOverlayInputPolicy.ShouldBeginFreeRegionFromWindowCandidate(
            start,
            new PixelPoint(-1201, 198)));
    }

    [Fact]
    public void Tray_icon_is_loaded_from_the_embedded_voxflow_resource()
    {
        using var icon = WindowsTrayIcon.LoadTrayIcon();

        Assert.True(icon.Width > 0);
        Assert.True(icon.Height > 0);
        Assert.NotEqual(System.Drawing.SystemIcons.Application.Handle, icon.Handle);
    }

    private static LowLevelKeyEvent HookKey(uint virtualKey, KeyTransition transition) => new(
        virtualKey,
        ScanCode: 0,
        LowLevelKeyFlags.None,
        transition,
        DateTimeOffset.UnixEpoch);

    private sealed class CapturingActivation : IScreenshotWindowActivation
    {
        public int CaptureCalls { get; private set; }

        public List<bool> NoActivateStates { get; } = [];

        public List<nint> RestoredWindows { get; } = [];

        public nint CaptureForegroundWindow()
        {
            CaptureCalls++;
            return new nint(4321);
        }

        public void SetNoActivate(nint windowHandle, bool enabled)
        {
            Assert.NotEqual(nint.Zero, windowHandle);
            NoActivateStates.Add(enabled);
        }

        public bool RestoreForegroundWindow(nint windowHandle)
        {
            RestoredWindows.Add(windowHandle);
            return true;
        }
    }
}
