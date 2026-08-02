using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class ScreenshotSelectionTests
{
    [Fact]
    public void Session_lifecycle_accepts_current_run_and_drops_stale_callbacks()
    {
        var runId = Guid.NewGuid();
        var state = ScreenshotSessionState.Create(runId)
            .StartFreezing()
            .BeginSelection();

        Assert.Equal(ScreenshotSessionPhase.Selecting, state.Phase);
        Assert.False(state.TryApply(
            Guid.NewGuid(),
            current => current.Cancel(),
            out var unchanged));
        Assert.Same(state, unchanged);
        Assert.True(state.TryApply(
            runId,
            current => current.BeginAnnotation(),
            out var annotating));
        Assert.Equal(ScreenshotSessionPhase.Annotating, annotating.Phase);

        var result = new ScreenshotResult(
            Guid.NewGuid(),
            runId,
            ScreenshotCompletionKind.Complete,
            new PixelSize(640, 480));
        var completed = annotating.BeginProcessing().Complete(result);
        Assert.True(completed.IsTerminal);
        Assert.False(completed.TryApply(runId, current => current.Cancel(), out _));
    }

    [Fact]
    public void Reverse_drag_normalizes_and_rejects_regions_smaller_than_eight_pixels()
    {
        var state = CreateState()
            .BeginRegionDrag(new PixelPoint(500, 400))
            .UpdatePointer(new PixelPoint(100, 50))
            .EndPointer();

        Assert.Equal(new PixelRect(100, 50, 400, 350), state.Region);
        Assert.True(state.HasValidRegion);

        var tiny = CreateState()
            .BeginRegionDrag(new PixelPoint(10, 10))
            .UpdatePointer(new PixelPoint(17, 100))
            .EndPointer();

        Assert.Null(tiny.Region);
        Assert.False(tiny.HasValidRegion);
    }

    [Fact]
    public void Move_and_all_eight_resize_handles_are_clamped_to_desktop_and_minimum_size()
    {
        var initial = CreateState().WithRegion(new PixelRect(10, 10, 100, 80));
        var moved = initial.BeginMove(new PixelPoint(20, 20))
            .UpdatePointer(new PixelPoint(-5000, -5000))
            .EndPointer();
        Assert.Equal(new PixelRect(-1280, -200, 100, 80), moved.Region);

        foreach (var handle in Enum.GetValues<ScreenshotResizeHandle>())
        {
            var resized = initial.BeginResize(handle)
                .UpdatePointer(new PixelPoint(12, 12))
                .EndPointer();

            Assert.NotNull(resized.Region);
            Assert.True(resized.Region.Value.Width >= ScreenshotSelectionState.MinimumRegionSize);
            Assert.True(resized.Region.Value.Height >= ScreenshotSelectionState.MinimumRegionSize);
            Assert.True(CreateLayout().VirtualBounds.Contains(resized.Region.Value));
        }
    }

    [Fact]
    public void Window_candidate_tab_full_screen_arrows_and_terminal_commands_form_one_state_machine()
    {
        var candidate = new WindowTargetCandidate(
            42,
            new PixelRect(20, 30, 500, 400),
            zOrder: 1);
        var state = CreateState().WithWindowCandidate(candidate);

        Assert.Equal(candidate.Bounds, state.EffectiveRegion);
        var tab = state.Apply(
            ScreenshotSelectionCommand.ToggleWindowSnap,
            new PixelPoint(100, 100));
        Assert.False(tab.State.IsWindowSnapEnabled);
        Assert.Null(tab.State.EffectiveRegion);

        var full = tab.State.Apply(
            ScreenshotSelectionCommand.FullDisplay,
            new PixelPoint(-100, 100));
        Assert.Equal(new PixelRect(-1280, -200, 1280, 1024), full.State.Region);

        var nudged = full.State.Apply(
            ScreenshotSelectionCommand.MoveRight,
            new PixelPoint(-100, 100));
        Assert.Equal(full.State.Region!.Value.Translate(1, 0), nudged.State.Region);

        var enter = nudged.State.Apply(
            ScreenshotSelectionCommand.Complete,
            new PixelPoint(-100, 100));
        Assert.Equal(ScreenshotSelectionOutcome.Completed, enter.Outcome);
        Assert.Equal(nudged.State.Region, enter.Region);

        var doubleClick = nudged.State.Apply(
            ScreenshotSelectionCommand.DoubleClick,
            new PixelPoint(-100, 100));
        Assert.Equal(ScreenshotSelectionOutcome.Completed, doubleClick.Outcome);
        Assert.Equal(
            ScreenshotSelectionOutcome.Continue,
            nudged.State.Apply(
                ScreenshotSelectionCommand.DoubleClick,
                new PixelPoint(500, 1000)).Outcome);

        Assert.Equal(
            ScreenshotSelectionOutcome.Cancelled,
            nudged.State.Apply(ScreenshotSelectionCommand.Cancel, null).Outcome);
        Assert.Equal(
            ScreenshotSelectionOutcome.Cancelled,
            nudged.State.Apply(ScreenshotSelectionCommand.RightClick, null).Outcome);
    }

    [Fact]
    public void Partly_off_desktop_window_candidates_are_clipped_to_capturable_pixels()
    {
        var state = CreateState().WithWindowCandidate(new WindowTargetCandidate(
            77,
            new PixelRect(-1300, -220, 200, 200),
            zOrder: 0));

        Assert.Equal(new PixelRect(-1280, -200, 180, 180), state.EffectiveRegion);
        var completed = state.Apply(
            ScreenshotSelectionCommand.Complete,
            new PixelPoint(-1200, -100));
        Assert.Equal(ScreenshotSelectionOutcome.Completed, completed.Outcome);
        Assert.Equal(state.EffectiveRegion, completed.Region);
    }

    [Fact]
    public void Arrow_keys_move_a_region_one_source_pixel_when_space_is_available()
    {
        var state = CreateState().WithRegion(new PixelRect(100, 100, 50, 50));

        state = state.Apply(ScreenshotSelectionCommand.MoveLeft, null).State;
        state = state.Apply(ScreenshotSelectionCommand.MoveUp, null).State;
        state = state.Apply(ScreenshotSelectionCommand.MoveRight, null).State;
        state = state.Apply(ScreenshotSelectionCommand.MoveDown, null).State;

        Assert.Equal(new PixelRect(100, 100, 50, 50), state.Region);
    }

    private static ScreenshotSelectionState CreateState() =>
        ScreenshotSelectionState.Create(CreateLayout());

    private static ScreenshotDesktopLayout CreateLayout() => new(
    [
        new ScreenshotDisplay(
            "left",
            "DISPLAY1",
            new PixelRect(-1280, -200, 1280, 1024),
            120,
            120,
            DisplayRotation.Degrees0,
            isPrimary: false),
        new ScreenshotDisplay(
            "main",
            "DISPLAY2",
            new PixelRect(0, 0, 1920, 1080),
            192,
            192,
            DisplayRotation.Degrees0,
            isPrimary: true),
    ]);
}
