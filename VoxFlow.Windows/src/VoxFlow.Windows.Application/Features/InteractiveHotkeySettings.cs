namespace VoxFlow.Windows.Application.Features;

public sealed record HotkeyBindingSetting
{
    public HotkeyBindingSetting(
        uint virtualKey,
        uint scanCode,
        int modifiers,
        bool isExtended)
    {
        VirtualKey = virtualKey;
        ScanCode = scanCode;
        Modifiers = modifiers;
        IsExtended = isExtended;
    }

    public uint VirtualKey { get; init; }

    public uint ScanCode { get; init; }

    public int Modifiers { get; init; }

    public bool IsExtended { get; init; }

    public bool IsValid =>
        VirtualKey is > 0 and <= 0xFF
        && ScanCode <= 0xFF
        && Modifiers >= 0
        && (Modifiers & ~0x0F) == 0;
}

public sealed record InteractiveHotkeySettingsDocument
{
    /// <summary>
    /// Schema 6: mac ⌘+Shift → Windows Alt+Shift factory defaults for all
    /// interactive workflow actions (screenshot, clipboard OCR, selection F/K/L/P).
    /// </summary>
    public const int CurrentSchemaVersion = 7;

    public const int SchemaVersionWithoutDictation = 6;

    /// <summary>
    /// Schema 5: Ctrl+Shift factory defaults for screenshot/clipboard only;
    /// selection workflows unbound by default.
    /// </summary>
    public const int SchemaVersionWithCtrlShiftDefaults = 5;

    public const int SchemaVersionWithoutClipboardImageOcr = 4;

    public const int SchemaVersionWithoutSelectionAskAi = 3;

    public const int SchemaVersionWithoutScreenshot = 1;

    public const int SchemaVersionWithConflictProneDefaults = 2;

    /// <summary>Alt + Shift (mac ⌘+Shift parity).</summary>
    public const int AltShiftModifiers = 6;

    /// <summary>Legacy Ctrl + Shift factory modifier mask.</summary>
    public const int CtrlShiftModifiers = 3;

    public InteractiveHotkeySettingsDocument(
        int schemaVersion,
        HotkeyBindingSetting? selectionTranslation,
        HotkeyBindingSetting? selectionSummary,
        HotkeyBindingSetting? agentCompose,
        HotkeyBindingSetting? screenshot,
        HotkeyBindingSetting? selectionAskAi = null,
        HotkeyBindingSetting? clipboardImageOcr = null,
        HotkeyBindingSetting? dictation = null)
    {
        SchemaVersion = schemaVersion;
        SelectionTranslation = selectionTranslation;
        SelectionSummary = selectionSummary;
        AgentCompose = agentCompose;
        Screenshot = screenshot;
        SelectionAskAi = selectionAskAi;
        ClipboardImageOcr = clipboardImageOcr;
        Dictation = dictation;
    }

    public static HotkeyBindingSetting ScreenshotDefault { get; } = new(
        virtualKey: 0x41, // A
        scanCode: 0x1E,
        modifiers: AltShiftModifiers,
        isExtended: false);

    public static HotkeyBindingSetting DictationDefault { get; } = new(
        virtualKey: 0xA3, // Right Control
        scanCode: 0x1D,
        modifiers: 0,
        isExtended: true);

    public static HotkeyBindingSetting ClipboardImageOcrDefault { get; } = new(
        virtualKey: 0x56, // V
        scanCode: 0x2F,
        modifiers: AltShiftModifiers,
        isExtended: false);

    public static HotkeyBindingSetting SelectionTranslationDefault { get; } = new(
        virtualKey: 0x46, // F — selection action / 划词操作
        scanCode: 0x21,
        modifiers: AltShiftModifiers,
        isExtended: false);

    public static HotkeyBindingSetting SelectionSummaryDefault { get; } = new(
        virtualKey: 0x4B, // K
        scanCode: 0x25,
        modifiers: AltShiftModifiers,
        isExtended: false);

    public static HotkeyBindingSetting AgentComposeDefault { get; } = new(
        virtualKey: 0x4C, // L — task / agent
        scanCode: 0x26,
        modifiers: AltShiftModifiers,
        isExtended: false);

    public static HotkeyBindingSetting SelectionAskAiDefault { get; } = new(
        virtualKey: 0x50, // P
        scanCode: 0x19,
        modifiers: AltShiftModifiers,
        isExtended: false);

    /// <summary>Schema-5 factory screenshot (Ctrl+Shift+A) used for migration.</summary>
    public static HotkeyBindingSetting CtrlShiftScreenshotDefault { get; } = new(
        virtualKey: 0x41,
        scanCode: 0x1E,
        modifiers: CtrlShiftModifiers,
        isExtended: false);

    /// <summary>Schema-5 factory clipboard OCR (Ctrl+Shift+V) used for migration.</summary>
    public static HotkeyBindingSetting CtrlShiftClipboardImageOcrDefault { get; } = new(
        virtualKey: 0x56,
        scanCode: 0x2F,
        modifiers: CtrlShiftModifiers,
        isExtended: false);

    public static InteractiveHotkeySettingsDocument Default { get; } = new(
        CurrentSchemaVersion,
        selectionTranslation: SelectionTranslationDefault,
        selectionSummary: SelectionSummaryDefault,
        agentCompose: AgentComposeDefault,
        screenshot: ScreenshotDefault,
        selectionAskAi: SelectionAskAiDefault,
        clipboardImageOcr: ClipboardImageOcrDefault,
        dictation: DictationDefault);

    public static InteractiveHotkeySettingsDocument ConflictProneDefaults { get; } = new(
        SchemaVersionWithConflictProneDefaults,
        new HotkeyBindingSetting(0x4A, 0x24, modifiers: CtrlShiftModifiers, isExtended: false),
        new HotkeyBindingSetting(0x4B, 0x25, modifiers: CtrlShiftModifiers, isExtended: false),
        new HotkeyBindingSetting(0x41, 0x1E, modifiers: 5, isExtended: false),
        new HotkeyBindingSetting(0x41, 0x1E, modifiers: CtrlShiftModifiers, isExtended: false),
        selectionAskAi: null,
        clipboardImageOcr: null);

    public int SchemaVersion { get; init; }

    public HotkeyBindingSetting? SelectionTranslation { get; init; }

    public HotkeyBindingSetting? SelectionSummary { get; init; }

    public HotkeyBindingSetting? AgentCompose { get; init; }

    public HotkeyBindingSetting? Screenshot { get; init; }

    public HotkeyBindingSetting? SelectionAskAi { get; init; }

    public HotkeyBindingSetting? ClipboardImageOcr { get; init; }

    public HotkeyBindingSetting? Dictation { get; init; }

    public bool IsValid => SchemaVersion == CurrentSchemaVersion
        && Dictation is not null
        && AllBindings().All(binding => binding.IsValid)
        && AllBindings().Distinct().Count() == AllBindings().Count;

    private IReadOnlyList<HotkeyBindingSetting> AllBindings() =>
        new[] { Dictation, Screenshot, ClipboardImageOcr, SelectionTranslation, SelectionSummary, AgentCompose, SelectionAskAi }
            .Where(binding => binding is not null)
            .Select(binding => binding!)
            .ToArray();
}

public interface IInteractiveHotkeySettingsStore
{
    ValueTask<InteractiveHotkeySettingsDocument> LoadAsync(
        CancellationToken cancellationToken);

    ValueTask SaveAsync(
        InteractiveHotkeySettingsDocument settings,
        CancellationToken cancellationToken);
}
