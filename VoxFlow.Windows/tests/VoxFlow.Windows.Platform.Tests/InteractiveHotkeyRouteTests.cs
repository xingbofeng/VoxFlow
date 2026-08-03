using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class InteractiveHotkeyRouteTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 11, 13, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Low_level_modifier_state_routes_each_configured_workflow_action()
    {
        var router = new InteractiveHotkeyRoute(ConfiguredBindings());

        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0xA0, 0x2A, KeyTransition.Down)));
        var translation = router.Handle(Key(0x4A, 0x24, KeyTransition.Down));
        Assert.Equal(InteractiveHotkeyAction.SelectionTranslation, translation?.Action);
        Assert.Equal(KeyTransition.Down, translation?.Transition);
        Assert.Null(router.Handle(Key(0x4A, 0x24, KeyTransition.Down)));
        Assert.Equal(
            InteractiveHotkeyAction.SelectionTranslation,
            router.Handle(Key(0x4A, 0x24, KeyTransition.Up))?.Action);

        Assert.Null(router.Handle(Key(0xA0, 0x2A, KeyTransition.Up)));
        Assert.Null(router.Handle(Key(0xA4, 0x38, KeyTransition.Down)));
        var agent = router.Handle(Key(0x41, 0x1E, KeyTransition.Down));
        Assert.Equal(InteractiveHotkeyAction.AgentCompose, agent?.Action);
    }

    [Fact]
    public void Configured_screenshot_routes_control_shift_a_once_per_key_press()
    {
        var router = new InteractiveHotkeyRoute(ConfiguredBindings());

        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0xA0, 0x2A, KeyTransition.Down)));
        var down = router.Handle(Key(0x41, 0x1E, KeyTransition.Down));

        Assert.Equal(InteractiveHotkeyAction.Screenshot, down?.Action);
        Assert.Equal(KeyTransition.Down, down?.Transition);
        Assert.Null(router.Handle(Key(0x41, 0x1E, KeyTransition.Down)));
        Assert.Equal(
            InteractiveHotkeyAction.Screenshot,
            router.Handle(Key(0x41, 0x1E, KeyTransition.Up))?.Action);
    }

    [Fact]
    public void Cleared_binding_and_wrong_modifier_state_do_not_route()
    {
        var editor = new InteractiveHotkeyBindingEditor();
        var cleared = editor.TrySet(
            InteractiveHotkeyBindingSet.Default,
            InteractiveHotkeyAction.SelectionSummary,
            binding: null).Bindings;
        var router = new InteractiveHotkeyRoute(cleared);

        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0x4B, 0x25, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0x4B, 0x25, KeyTransition.Up)));
    }

    [Fact]
    public void Right_alt_altgr_with_synthetic_control_never_routes_the_agent_chord()
    {
        var router = new InteractiveHotkeyRoute(ConfiguredBindings());

        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(
            RightControlKeyClassifier.VirtualKeyRightMenu,
            0x38,
            KeyTransition.Down,
            extended: true)));
        Assert.Null(router.Handle(Key(0x41, 0x1E, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0x41, 0x1E, KeyTransition.Up)));
    }

    [Fact]
    public void Updated_bindings_take_effect_without_restarting_the_input_route()
    {
        var router = new InteractiveHotkeyRoute(InteractiveHotkeyBindingSet.Default);
        var configured = ConfiguredBindings();

        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0xA0, 0x2A, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0x4A, 0x24, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0x4A, 0x24, KeyTransition.Up)));
        Assert.Null(router.Handle(Key(0xA0, 0x2A, KeyTransition.Up)));
        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Up)));

        router.UpdateBindings(configured);

        Assert.Null(router.Handle(Key(0xA2, 0x1D, KeyTransition.Down)));
        Assert.Null(router.Handle(Key(0xA0, 0x2A, KeyTransition.Down)));
        Assert.Equal(
            InteractiveHotkeyAction.SelectionTranslation,
            router.Handle(Key(0x4A, 0x24, KeyTransition.Down))?.Action);
    }

    private static InteractiveHotkeyBindingSet ConfiguredBindings() => new(
        HotkeyBinding.RightControlDefault,
        new HotkeyBinding(0x41, 0x1E, HotkeyModifiers.Control | HotkeyModifiers.Shift, false),
        new HotkeyBinding(0x4A, 0x24, HotkeyModifiers.Control | HotkeyModifiers.Shift, false),
        new HotkeyBinding(0x4B, 0x25, HotkeyModifiers.Control | HotkeyModifiers.Shift, false),
        new HotkeyBinding(0x41, 0x1E, HotkeyModifiers.Control | HotkeyModifiers.Alt, false));

    private static LowLevelKeyEvent Key(
        uint virtualKey,
        uint scanCode,
        KeyTransition transition,
        bool extended = false) => new(
        virtualKey,
        scanCode,
        extended ? LowLevelKeyFlags.Extended : LowLevelKeyFlags.None,
        transition,
        Now);
}
