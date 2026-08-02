using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class AgentChordGestureRecognizerTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 11, 14, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(DictationPhase.Idle, HotkeyRouteAction.ToggleStart)]
    [InlineData(DictationPhase.Recording, HotkeyRouteAction.ToggleStop)]
    public void Short_press_toggles_the_agent_recording_phase(
        DictationPhase phase,
        HotkeyRouteAction expected)
    {
        var recognizer = Recognizer();

        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(Event(KeyTransition.Down, Now), phase));
        Assert.Equal(
            expected,
            recognizer.Handle(
                Event(KeyTransition.Up, Now.AddMilliseconds(100)),
                phase));
    }

    [Fact]
    public void Long_press_starts_at_half_a_second_and_stops_on_A_release()
    {
        var recognizer = Recognizer();

        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(Event(KeyTransition.Down, Now), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Advance(Now.AddMilliseconds(499), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStart,
            recognizer.Advance(Now.AddMilliseconds(500), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStop,
            recognizer.Handle(
                Event(KeyTransition.Up, Now.AddMilliseconds(650)),
                DictationPhase.Recording));
    }

    [Fact]
    public void Modifier_release_auto_repeat_and_focus_change_do_not_lose_the_active_A_release()
    {
        var route = new InteractiveHotkeyRoute(new InteractiveHotkeyBindingSet(
            HotkeyBinding.RightControlDefault,
            screenshot: null,
            selectionTranslation: null,
            selectionSummary: null,
            agentCompose: new HotkeyBinding(
                0x41,
                0x1E,
                HotkeyModifiers.Control | HotkeyModifiers.Alt,
                IsExtended: false)));
        Assert.Null(route.Handle(Key(0xA2, 0x1D, KeyTransition.Down, Now)));
        Assert.Null(route.Handle(Key(0xA4, 0x38, KeyTransition.Down, Now)));
        var down = route.Handle(Key(0x41, 0x1E, KeyTransition.Down, Now));
        Assert.NotNull(down);
        Assert.Null(route.Handle(Key(0x41, 0x1E, KeyTransition.Down, Now.AddMilliseconds(10))));
        Assert.Null(route.Handle(Key(0xA4, 0x38, KeyTransition.Up, Now.AddMilliseconds(20))));
        Assert.Null(route.Handle(Key(0xA2, 0x1D, KeyTransition.Up, Now.AddMilliseconds(30))));

        var recognizer = Recognizer();
        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(down!, DictationPhase.Idle));
        recognizer.NotifyForegroundChanged();
        var up = route.Handle(Key(0x41, 0x1E, KeyTransition.Up, Now.AddMilliseconds(100)));

        Assert.NotNull(up);
        Assert.Equal(InteractiveHotkeyAction.AgentCompose, up!.Action);
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            recognizer.Handle(up, DictationPhase.Idle));
    }

    [Fact]
    public void Active_processing_phase_turns_a_new_agent_chord_into_cancellation()
    {
        var recognizer = Recognizer();

        Assert.Equal(
            HotkeyRouteAction.Cancel,
            recognizer.Handle(
                Event(KeyTransition.Down, Now),
                DictationPhase.Processing));
        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(
                Event(KeyTransition.Up, Now.AddMilliseconds(100)),
                DictationPhase.Processing));
    }

    [Theory]
    [InlineData(DictationPhase.Failed)]
    [InlineData(DictationPhase.Completed)]
    public void Short_press_after_terminal_phase_starts_new_agent_session(
        DictationPhase phase)
    {
        var recognizer = Recognizer();

        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(Event(KeyTransition.Down, Now), phase));
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            recognizer.Handle(
                Event(KeyTransition.Up, Now.AddMilliseconds(100)),
                phase));
    }

    private static AgentChordGestureRecognizer Recognizer() =>
        new(TimeSpan.FromMilliseconds(500));

    private static InteractiveHotkeyRouteEvent Event(
        KeyTransition transition,
        DateTimeOffset timestamp) => new(
        InteractiveHotkeyAction.AgentCompose,
        transition,
        timestamp);

    private static LowLevelKeyEvent Key(
        uint virtualKey,
        uint scanCode,
        KeyTransition transition,
        DateTimeOffset timestamp) => new(
        virtualKey,
        scanCode,
        LowLevelKeyFlags.None,
        transition,
        timestamp);
}
