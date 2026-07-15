namespace VoxFlow.Windows.Platform.Input;

using VoxFlow.Windows.Application.Features;

public enum InteractiveHotkeyAction
{
    Dictation,
    Screenshot,
    ClipboardImageOcr,
    SelectionTranslation,
    SelectionSummary,
    SelectionAskAi,
    AgentCompose,
}

public sealed class InteractiveHotkeyBindingSet
{
    public InteractiveHotkeyBindingSet(
        HotkeyBinding dictation,
        HotkeyBinding? screenshot,
        HotkeyBinding? selectionTranslation,
        HotkeyBinding? selectionSummary,
        HotkeyBinding? agentCompose,
        HotkeyBinding? selectionAskAi = null,
        HotkeyBinding? clipboardImageOcr = null)
    {
        Dictation = dictation ?? throw new ArgumentNullException(nameof(dictation));
        Screenshot = screenshot;
        SelectionTranslation = selectionTranslation;
        SelectionSummary = selectionSummary;
        AgentCompose = agentCompose;
        SelectionAskAi = selectionAskAi;
        ClipboardImageOcr = clipboardImageOcr;
        AssignedBindings = new[]
            {
                Dictation,
                Screenshot,
                ClipboardImageOcr,
                SelectionTranslation,
                SelectionSummary,
                SelectionAskAi,
                AgentCompose,
            }
            .Where(binding => binding is not null)
            .Select(binding => binding!)
            .ToArray();
    }

    public static InteractiveHotkeyBindingSet Default { get; } = new(
        HotkeyBinding.RightControlDefault,
        screenshot: HotkeyBinding.ScreenshotDefault,
        selectionTranslation: HotkeyBinding.SelectionTranslationDefault,
        selectionSummary: HotkeyBinding.SelectionSummaryDefault,
        agentCompose: HotkeyBinding.AgentComposeDefault,
        selectionAskAi: HotkeyBinding.SelectionAskAiDefault,
        clipboardImageOcr: HotkeyBinding.ClipboardImageOcrDefault);

    public static InteractiveHotkeyBindingSet FromSettings(
        InteractiveHotkeySettingsDocument settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (!settings.IsValid)
        {
            throw new ArgumentException(
                "Valid current interactive hotkey settings are required.",
                nameof(settings));
        }
        return new InteractiveHotkeyBindingSet(
            FromSetting(settings.Dictation)
                ?? throw new ArgumentException("A dictation binding is required.", nameof(settings)),
            FromSetting(settings.Screenshot),
            FromSetting(settings.SelectionTranslation),
            FromSetting(settings.SelectionSummary),
            FromSetting(settings.AgentCompose),
            FromSetting(settings.SelectionAskAi),
            FromSetting(settings.ClipboardImageOcr));
    }

    public InteractiveHotkeySettingsDocument ToSettings() => new(
        InteractiveHotkeySettingsDocument.CurrentSchemaVersion,
        ToSetting(SelectionTranslation),
        ToSetting(SelectionSummary),
        ToSetting(AgentCompose),
        ToSetting(Screenshot),
        ToSetting(SelectionAskAi),
        ToSetting(ClipboardImageOcr),
        ToSetting(Dictation));

    public HotkeyBinding Dictation { get; }

    public HotkeyBinding? Screenshot { get; }

    public HotkeyBinding? ClipboardImageOcr { get; }

    public HotkeyBinding? SelectionTranslation { get; }

    public HotkeyBinding? SelectionSummary { get; }

    public HotkeyBinding? AgentCompose { get; }

    public HotkeyBinding? SelectionAskAi { get; }

    public IReadOnlyList<HotkeyBinding> AssignedBindings { get; }

    public HotkeyBinding? Get(InteractiveHotkeyAction action) => action switch
    {
        InteractiveHotkeyAction.Dictation => Dictation,
        InteractiveHotkeyAction.Screenshot => Screenshot,
        InteractiveHotkeyAction.ClipboardImageOcr => ClipboardImageOcr,
        InteractiveHotkeyAction.SelectionTranslation => SelectionTranslation,
        InteractiveHotkeyAction.SelectionSummary => SelectionSummary,
        InteractiveHotkeyAction.SelectionAskAi => SelectionAskAi,
        InteractiveHotkeyAction.AgentCompose => AgentCompose,
        _ => throw new ArgumentOutOfRangeException(nameof(action), action, null),
    };

    internal InteractiveHotkeyBindingSet Replace(
        InteractiveHotkeyAction action,
        HotkeyBinding? binding) => action switch
    {
        InteractiveHotkeyAction.Dictation when binding is not null => new(
            binding,
            Screenshot,
            SelectionTranslation,
            SelectionSummary,
            AgentCompose,
            SelectionAskAi,
            ClipboardImageOcr),
        InteractiveHotkeyAction.Dictation => throw new ArgumentException(
            "The primary dictation shortcut cannot be unbound.",
            nameof(binding)),
        InteractiveHotkeyAction.Screenshot => new(
            Dictation,
            binding,
            SelectionTranslation,
            SelectionSummary,
            AgentCompose,
            SelectionAskAi,
            ClipboardImageOcr),
        InteractiveHotkeyAction.ClipboardImageOcr => new(
            Dictation,
            Screenshot,
            SelectionTranslation,
            SelectionSummary,
            AgentCompose,
            SelectionAskAi,
            binding),
        InteractiveHotkeyAction.SelectionTranslation => new(
            Dictation,
            Screenshot,
            binding,
            SelectionSummary,
            AgentCompose,
            SelectionAskAi,
            ClipboardImageOcr),
        InteractiveHotkeyAction.SelectionSummary => new(
            Dictation,
            Screenshot,
            SelectionTranslation,
            binding,
            AgentCompose,
            SelectionAskAi,
            ClipboardImageOcr),
        InteractiveHotkeyAction.SelectionAskAi => new(
            Dictation,
            Screenshot,
            SelectionTranslation,
            SelectionSummary,
            AgentCompose,
            binding,
            ClipboardImageOcr),
        InteractiveHotkeyAction.AgentCompose => new(
            Dictation,
            Screenshot,
            SelectionTranslation,
            SelectionSummary,
            binding,
            SelectionAskAi,
            ClipboardImageOcr),
        _ => throw new ArgumentOutOfRangeException(nameof(action), action, null),
    };

    private static HotkeyBinding? FromSetting(HotkeyBindingSetting? setting) =>
        setting is null
            ? null
            : new HotkeyBinding(
                setting.VirtualKey,
                setting.ScanCode,
                (HotkeyModifiers)setting.Modifiers,
                setting.IsExtended);

    private static HotkeyBindingSetting? ToSetting(HotkeyBinding? binding) =>
        binding is null
            ? null
            : new HotkeyBindingSetting(
                binding.VirtualKey,
                binding.ScanCode,
                (int)binding.Modifiers,
                binding.IsExtended);
}

public sealed record InteractiveHotkeyUpdateResult(
    HotkeyCaptureStatus Status,
    InteractiveHotkeyBindingSet Bindings,
    HotkeyConflictKind Conflict,
    string? MessageKey);

public sealed class InteractiveHotkeyBindingEditor
{
    private static readonly IReadOnlySet<uint> SystemEditingKeys =
        new HashSet<uint>
        {
            0x41, // A: select all
            0x43, // C: copy
            0x56, // V: paste
            0x58, // X: cut
            0x59, // Y: redo
            0x5A, // Z: undo
        };

    public InteractiveHotkeyUpdateResult TrySet(
        InteractiveHotkeyBindingSet current,
        InteractiveHotkeyAction action,
        HotkeyBinding? binding)
    {
        ArgumentNullException.ThrowIfNull(current);
        if (!Enum.IsDefined(action))
        {
            throw new ArgumentOutOfRangeException(nameof(action), action, null);
        }

        if (binding is null)
        {
            return Accepted(current.Replace(action, binding));
        }

        if (IsSystemEditingCombination(binding))
        {
            return Conflict(
                current,
                HotkeyConflictKind.SystemEditing,
                "hotkey.conflict.systemEditing");
        }

        if (binding.VirtualKey == RightControlKeyClassifier.VirtualKeyRightMenu)
        {
            return Conflict(
                current,
                HotkeyConflictKind.AltGrUnsafe,
                "hotkey.conflict.altGrUnsafe");
        }

        var assignedByAnotherAction = current.AssignedBindings
            .Where(existing => existing != current.Get(action));
        if (assignedByAnotherAction.Contains(binding))
        {
            return Conflict(
                current,
                HotkeyConflictKind.AlreadyAssigned,
                "hotkey.conflict.alreadyAssigned");
        }

        return Accepted(current.Replace(action, binding));
    }

    private static bool IsSystemEditingCombination(HotkeyBinding binding) =>
        binding.Modifiers == HotkeyModifiers.Control
        && SystemEditingKeys.Contains(binding.VirtualKey);

    private static InteractiveHotkeyUpdateResult Accepted(
        InteractiveHotkeyBindingSet bindings) => new(
        HotkeyCaptureStatus.Accepted,
        bindings,
        HotkeyConflictKind.None,
        MessageKey: null);

    private static InteractiveHotkeyUpdateResult Conflict(
        InteractiveHotkeyBindingSet current,
        HotkeyConflictKind conflict,
        string messageKey) => new(
        HotkeyCaptureStatus.Conflict,
        current,
        conflict,
        messageKey);
}

public static class HotkeyBindingDisplayExtensions
{
    public static string ToDisplayString(this HotkeyBinding binding)
    {
        ArgumentNullException.ThrowIfNull(binding);
        return string.Join('+', binding.ToDisplayTokens());
    }

    /// <summary>
    /// Individual key chips for settings UI (Ctrl / Alt / Shift / Win / letter).
    /// Order matches conventional Mac/Windows shortcut presentation.
    /// </summary>
    public static IReadOnlyList<string> ToDisplayTokens(this HotkeyBinding binding)
    {
        ArgumentNullException.ThrowIfNull(binding);
        List<string> parts = [];
        if (binding.Modifiers.HasFlag(HotkeyModifiers.Control))
        {
            parts.Add("Ctrl");
        }
        if (binding.Modifiers.HasFlag(HotkeyModifiers.Alt))
        {
            parts.Add("Alt");
        }
        if (binding.Modifiers.HasFlag(HotkeyModifiers.Shift))
        {
            parts.Add("Shift");
        }
        if (binding.Modifiers.HasFlag(HotkeyModifiers.Windows))
        {
            parts.Add("Win");
        }

        parts.Add(binding.VirtualKey is >= 0x41 and <= 0x5A
            ? ((char)binding.VirtualKey).ToString()
            : $"VK 0x{binding.VirtualKey:X2}");
        return parts;
    }
}
