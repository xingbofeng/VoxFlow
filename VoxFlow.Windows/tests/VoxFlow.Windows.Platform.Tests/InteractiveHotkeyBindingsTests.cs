using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class InteractiveHotkeyBindingsTests
{
    [Fact]
    public void Defaults_bind_all_mac_parity_alt_shift_workflows_and_right_control_dictation()
    {
        var bindings = InteractiveHotkeyBindingSet.Default;

        Assert.Equal(HotkeyBinding.RightControlDefault, bindings.Dictation);
        Assert.Equal(HotkeyBinding.ScreenshotDefault, bindings.Screenshot);
        Assert.Equal(HotkeyBinding.ClipboardImageOcrDefault, bindings.ClipboardImageOcr);
        Assert.Equal(HotkeyBinding.SelectionTranslationDefault, bindings.SelectionTranslation);
        Assert.Equal(HotkeyBinding.SelectionSummaryDefault, bindings.SelectionSummary);
        Assert.Equal(HotkeyBinding.AgentComposeDefault, bindings.AgentCompose);
        Assert.Equal(HotkeyBinding.SelectionAskAiDefault, bindings.SelectionAskAi);

        // Alt+Shift letter map (mac ⌘+Shift → Alt+Shift).
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.Shift, bindings.Screenshot!.Modifiers);
        Assert.Equal(0x41u, bindings.Screenshot.VirtualKey); // A
        Assert.Equal(0x56u, bindings.ClipboardImageOcr!.VirtualKey); // V
        Assert.Equal(0x46u, bindings.SelectionTranslation!.VirtualKey); // F
        Assert.Equal(0x4Bu, bindings.SelectionSummary!.VirtualKey); // K
        Assert.Equal(0x4Cu, bindings.AgentCompose!.VirtualKey); // L
        Assert.Equal(0x50u, bindings.SelectionAskAi!.VirtualKey); // P

        Assert.Equal("Alt+Shift+A", bindings.Screenshot.ToDisplayString());
        Assert.Equal("Alt+Shift+V", bindings.ClipboardImageOcr.ToDisplayString());
        Assert.Equal("Alt+Shift+F", bindings.SelectionTranslation.ToDisplayString());
        Assert.Equal("Alt+Shift+K", bindings.SelectionSummary.ToDisplayString());
        Assert.Equal("Alt+Shift+L", bindings.AgentCompose.ToDisplayString());
        Assert.Equal("Alt+Shift+P", bindings.SelectionAskAi.ToDisplayString());

        // Dictation + 6 workflow actions.
        Assert.Equal(7, bindings.AssignedBindings.Count);
        Assert.Equal(
            bindings.AssignedBindings.Count,
            bindings.AssignedBindings.Distinct().Count());
        // Old Ctrl+Shift factory combos must not remain as defaults.
        Assert.DoesNotContain(
            bindings.AssignedBindings,
            binding => binding.Modifiers == (HotkeyModifiers.Control | HotkeyModifiers.Shift));
    }

    [Fact]
    public void Rebind_and_clear_return_a_new_valid_binding_set()
    {
        var editor = new InteractiveHotkeyBindingEditor();
        var replacement = new HotkeyBinding(
            VirtualKey: 0x55,
            ScanCode: 0x16,
            Modifiers: HotkeyModifiers.Alt | HotkeyModifiers.Shift,
            IsExtended: false);

        var rebound = editor.TrySet(
            InteractiveHotkeyBindingSet.Default,
            InteractiveHotkeyAction.SelectionTranslation,
            replacement);
        var cleared = editor.TrySet(
            rebound.Bindings,
            InteractiveHotkeyAction.SelectionSummary,
            binding: null);

        Assert.Equal(HotkeyCaptureStatus.Accepted, rebound.Status);
        Assert.Equal(replacement, rebound.Bindings.SelectionTranslation);
        Assert.Equal(HotkeyCaptureStatus.Accepted, cleared.Status);
        Assert.Null(cleared.Bindings.SelectionSummary);
        Assert.Equal(HotkeyBinding.AgentComposeDefault, cleared.Bindings.AgentCompose);
        Assert.Equal(HotkeyBinding.ScreenshotDefault, cleared.Bindings.Screenshot);
    }

    [Fact]
    public void Screenshot_default_restore_rebinds_alt_shift_a_and_conflicts_with_other_actions()
    {
        var editor = new InteractiveHotkeyBindingEditor();
        var defaults = InteractiveHotkeyBindingSet.Default;
        var cleared = editor.TrySet(
            defaults,
            InteractiveHotkeyAction.Screenshot,
            binding: null);

        var restored = editor.TrySet(
            cleared.Bindings,
            InteractiveHotkeyAction.Screenshot,
            defaults.Screenshot);
        var translation = new HotkeyBinding(
            VirtualKey: 0x54,
            ScanCode: 0x14,
            Modifiers: HotkeyModifiers.Alt | HotkeyModifiers.Shift,
            IsExtended: false);
        var withTranslation = editor.TrySet(
            // Clear selection translation first so the custom T binding is free.
            editor.TrySet(
                defaults,
                InteractiveHotkeyAction.SelectionTranslation,
                binding: null).Bindings,
            InteractiveHotkeyAction.SelectionTranslation,
            translation);
        var duplicate = editor.TrySet(
            withTranslation.Bindings,
            InteractiveHotkeyAction.Screenshot,
            translation);

        Assert.Equal(HotkeyCaptureStatus.Accepted, restored.Status);
        Assert.Equal(HotkeyBinding.ScreenshotDefault, restored.Bindings.Screenshot);
        Assert.Equal(HotkeyCaptureStatus.Conflict, duplicate.Status);
        Assert.Equal(HotkeyConflictKind.AlreadyAssigned, duplicate.Conflict);
        Assert.Same(withTranslation.Bindings, duplicate.Bindings);
    }

    [Fact]
    public void Duplicate_and_system_editing_combinations_are_rejected_without_mutation()
    {
        var editor = new InteractiveHotkeyBindingEditor();
        var defaults = InteractiveHotkeyBindingSet.Default;
        var translation = defaults.SelectionTranslation!;

        var duplicate = editor.TrySet(
            defaults,
            InteractiveHotkeyAction.SelectionSummary,
            translation);
        var copy = editor.TrySet(
            defaults,
            InteractiveHotkeyAction.AgentCompose,
            new HotkeyBinding(
                VirtualKey: 0x43,
                ScanCode: 0x2E,
                Modifiers: HotkeyModifiers.Control,
                IsExtended: false));

        Assert.Equal(HotkeyCaptureStatus.Conflict, duplicate.Status);
        Assert.Equal(HotkeyConflictKind.AlreadyAssigned, duplicate.Conflict);
        Assert.Same(defaults, duplicate.Bindings);
        Assert.Equal(HotkeyCaptureStatus.Conflict, copy.Status);
        Assert.Equal(HotkeyConflictKind.SystemEditing, copy.Conflict);
        Assert.Same(defaults, copy.Bindings);
    }
}
