using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum ProcessIntegrityLevel
{
    [JsonStringEnumMemberName("unknown")]
    Unknown,

    [JsonStringEnumMemberName("untrusted")]
    Untrusted,

    [JsonStringEnumMemberName("low")]
    Low,

    [JsonStringEnumMemberName("medium")]
    Medium,

    [JsonStringEnumMemberName("mediumPlus")]
    MediumPlus,

    [JsonStringEnumMemberName("high")]
    High,

    [JsonStringEnumMemberName("system")]
    System,

    [JsonStringEnumMemberName("protected")]
    Protected,
}

public enum SelectionAcquisitionSource
{
    [JsonStringEnumMemberName("uiAutomation")]
    UiAutomation,

    [JsonStringEnumMemberName("shortcutCopy")]
    ShortcutCopy,
}

public enum SelectionEditability
{
    [JsonStringEnumMemberName("unknown")]
    Unknown,

    [JsonStringEnumMemberName("readOnly")]
    ReadOnly,

    [JsonStringEnumMemberName("editable")]
    Editable,
}

public enum SelectionTargetRevalidationStatus
{
    [JsonStringEnumMemberName("ready")]
    Ready,

    [JsonStringEnumMemberName("targetClosed")]
    TargetClosed,

    [JsonStringEnumMemberName("targetChanged")]
    TargetChanged,

    [JsonStringEnumMemberName("integrityLevelChanged")]
    IntegrityLevelChanged,

    [JsonStringEnumMemberName("higherIntegrityBlocked")]
    HigherIntegrityBlocked,

    [JsonStringEnumMemberName("elementUnavailable")]
    ElementUnavailable,

    [JsonStringEnumMemberName("selectionMissing")]
    SelectionMissing,

    [JsonStringEnumMemberName("selectionTextChanged")]
    SelectionTextChanged,

    [JsonStringEnumMemberName("ambiguousSelection")]
    AmbiguousSelection,

    [JsonStringEnumMemberName("secureTarget")]
    SecureTarget,

    [JsonStringEnumMemberName("notEditable")]
    NotEditable,

    [JsonStringEnumMemberName("uipiBlocked")]
    UipiBlocked,
}

public sealed record ForegroundTargetSnapshot
{
    [JsonConstructor]
    public ForegroundTargetSnapshot(
        long windowHandle,
        int processId,
        string processName,
        string windowTitle,
        WindowBounds bounds,
        ProcessIntegrityLevel integrityLevel,
        IReadOnlyList<int> focusedElementRuntimeId,
        long capturedAtUnixMs)
    {
        if (windowHandle == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(windowHandle));
        }

        if (processId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(processId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(processName);
        ArgumentNullException.ThrowIfNull(windowTitle);
        ArgumentNullException.ThrowIfNull(bounds);
        ValidateEnum(integrityLevel, nameof(integrityLevel));
        ArgumentOutOfRangeException.ThrowIfNegative(capturedAtUnixMs);

        WindowHandle = windowHandle;
        ProcessId = processId;
        ProcessName = processName;
        WindowTitle = windowTitle;
        Bounds = bounds;
        IntegrityLevel = integrityLevel;
        FocusedElementRuntimeId = Freeze(
            focusedElementRuntimeId,
            nameof(focusedElementRuntimeId));
        CapturedAtUnixMs = capturedAtUnixMs;
    }

    public long WindowHandle { get; }

    public int ProcessId { get; }

    public string ProcessName { get; }

    public string WindowTitle { get; }

    public WindowBounds Bounds { get; }

    public ProcessIntegrityLevel IntegrityLevel { get; }

    public IReadOnlyList<int> FocusedElementRuntimeId { get; }

    public long CapturedAtUnixMs { get; }

    private static IReadOnlyList<T> Freeze<T>(
        IReadOnlyList<T> values,
        string parameterName)
    {
        ArgumentNullException.ThrowIfNull(values, parameterName);
        return Array.AsReadOnly(values.ToArray());
    }

    private static void ValidateEnum<T>(T value, string parameterName)
        where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}

public sealed record SelectionRangeSnapshot
{
    [JsonConstructor]
    public SelectionRangeSnapshot(
        int documentOrder,
        string text,
        IReadOnlyList<WindowBounds> bounds,
        string? leadingText,
        string? trailingText)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(documentOrder);
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        ArgumentNullException.ThrowIfNull(bounds);

        DocumentOrder = documentOrder;
        Text = text;
        Bounds = Array.AsReadOnly(bounds.ToArray());
        LeadingText = leadingText;
        TrailingText = trailingText;
    }

    public int DocumentOrder { get; }

    public string Text { get; }

    public IReadOnlyList<WindowBounds> Bounds { get; }

    public string? LeadingText { get; }

    public string? TrailingText { get; }
}

public sealed record SelectionSnapshot
{
    [JsonConstructor]
    public SelectionSnapshot(
        string text,
        SelectionAcquisitionSource source,
        ForegroundTargetSnapshot target,
        IReadOnlyList<int> elementRuntimeId,
        IReadOnlyList<SelectionRangeSnapshot> ranges,
        SelectionEditability editability,
        bool allowsReselection,
        long capturedAtUnixMs)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        ValidateEnum(source, nameof(source));
        ArgumentNullException.ThrowIfNull(target);
        ArgumentNullException.ThrowIfNull(elementRuntimeId);
        ArgumentNullException.ThrowIfNull(ranges);
        ValidateEnum(editability, nameof(editability));
        if (capturedAtUnixMs < target.CapturedAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(
                nameof(capturedAtUnixMs),
                "A selection cannot be captured before its foreground target.");
        }

        var frozenElementRuntimeId = Array.AsReadOnly(elementRuntimeId.ToArray());
        var frozenRanges = Array.AsReadOnly(ranges.ToArray());
        if (source == SelectionAcquisitionSource.UiAutomation
            && (frozenElementRuntimeId.Count == 0 || frozenRanges.Count == 0))
        {
            throw new ArgumentException(
                "A UI Automation selection requires an element identity and at least one range.",
                nameof(ranges));
        }

        for (var index = 1; index < frozenRanges.Count; index++)
        {
            if (frozenRanges[index - 1].DocumentOrder
                >= frozenRanges[index].DocumentOrder)
            {
                throw new ArgumentException(
                    "Selection ranges must be in strict document order.",
                    nameof(ranges));
            }
        }

        Text = text;
        Source = source;
        Target = target;
        ElementRuntimeId = frozenElementRuntimeId;
        Ranges = frozenRanges;
        Editability = editability;
        AllowsReselection = allowsReselection;
        CapturedAtUnixMs = capturedAtUnixMs;
    }

    public string Text { get; }

    public SelectionAcquisitionSource Source { get; }

    public ForegroundTargetSnapshot Target { get; }

    public IReadOnlyList<int> ElementRuntimeId { get; }

    public IReadOnlyList<SelectionRangeSnapshot> Ranges { get; }

    public SelectionEditability Editability { get; }

    public bool AllowsReselection { get; }

    public long CapturedAtUnixMs { get; }

    [JsonIgnore]
    public bool IsEditable => Editability == SelectionEditability.Editable;

    private static void ValidateEnum<T>(T value, string parameterName)
        where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}

public sealed record SelectionTargetRevalidationResult
{
    [JsonConstructor]
    public SelectionTargetRevalidationResult(
        SelectionTargetRevalidationStatus status)
    {
        if (!Enum.IsDefined(status))
        {
            throw new ArgumentOutOfRangeException(nameof(status), status, null);
        }

        Status = status;
    }

    public SelectionTargetRevalidationStatus Status { get; }

    [JsonIgnore]
    public bool CanWrite => Status == SelectionTargetRevalidationStatus.Ready;

    [JsonIgnore]
    public bool ShouldCopyInstead => !CanWrite;
}
