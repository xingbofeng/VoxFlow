using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Home;

/// <summary>
/// Home asset source filters aligned with macOS <c>HomeAssetSourceFilter</c>.
/// </summary>
public enum HomeTextSourceFilter
{
    All,
    Dictation,
    Screenshot,
    Qwen,
    TencentCloud,
    AliyunDashScope,
    Volcengine,
    SelectionTranslation,
    SelectionSummary,
    AgentCompose,
    FileTranscription,
}

public sealed record HomeTextSourceFilterOption(
    HomeTextSourceFilter Value,
    string Label);

/// <summary>
/// Home stats aligned with the macOS asset breakdown.
/// </summary>
public sealed record HomeDashboardStatistics(
    int TotalAssets,
    int TodayAssets,
    int DictationAssets,
    int ScreenshotAssets,
    int ClipboardAssets,
    int ReusableAssets)
{
    public static HomeDashboardStatistics Empty { get; } = new(0, 0, 0, 0, 0, 0);

    // Backward-compatible aliases used by existing XAML bindings during transition.
    public int TotalDictations => TotalAssets;

    public int TodayDictations => TodayAssets;

    public int TotalCharacters => DictationAssets;

    public long TotalDurationMilliseconds => ScreenshotAssets;
}

public sealed record HomeActivityDay(
    DateOnly Date,
    int Count)
{
    public double Opacity => Count switch
    {
        <= 0 => 0.10,
        1 => 0.32,
        2 => 0.50,
        3 => 0.68,
        _ => 0.88,
    };
}

public sealed record HomeActivityWeek(IReadOnlyList<HomeActivityDay> Days);

public sealed record HomeHistoryItem(
    UnifiedHistoryEntry Entry,
    bool IsSelected)
{
    public string Id => Entry.Id;

    public string FinalText => Entry.ResultText;

    public DateTimeOffset CreatedAtUtc => Entry.CreatedAtUtc;

    public UnifiedHistoryKind Kind => Entry.Kind;

    public string Title => Entry.Title;

    public string Status => Entry.Status;

    public bool IsWorkflow => Entry.Kind is UnifiedHistoryKind.SelectionTranslation
        or UnifiedHistoryKind.SelectionSummary
        or UnifiedHistoryKind.AgentCompose;

    public bool IsScreenshot => Entry.Kind == UnifiedHistoryKind.Screenshot;

    public bool IsFailed => Entry.WorkflowTask?.Status is WorkflowTaskStatus.Failed
        or WorkflowTaskStatus.Cancelled
        or WorkflowTaskStatus.Interrupted;

    public string WorkflowGlyph => Entry.Kind switch
    {
        UnifiedHistoryKind.SelectionTranslation => "\uE774",
        UnifiedHistoryKind.SelectionSummary => "\uE8A5",
        UnifiedHistoryKind.AgentCompose => "\uE950",
        UnifiedHistoryKind.FileTranscription => "\uE8D2",
        UnifiedHistoryKind.Screenshot => "\uE722",
        UnifiedHistoryKind.Dictation => "\uE720",
        _ => "\uE8A5",
    };

    public string StatusLabel => Entry.WorkflowTask?.Status switch
    {
        WorkflowTaskStatus.Pending => L10n.Localize("WorkflowStatusPending"),
        WorkflowTaskStatus.Running => L10n.Localize("WorkflowStatusRunning"),
        WorkflowTaskStatus.PartiallyCompleted => L10n.Localize("WorkflowStatusPartiallyCompleted"),
        WorkflowTaskStatus.Completed => L10n.Localize("WorkflowStatusCompleted"),
        WorkflowTaskStatus.Failed => L10n.Localize("WorkflowStatusFailed"),
        WorkflowTaskStatus.Cancelled => L10n.Localize("WorkflowStatusCancelled"),
        WorkflowTaskStatus.Interrupted => L10n.Localize("WorkflowStatusInterrupted"),
        null => Entry.Status,
        _ => throw new ArgumentOutOfRangeException(),
    };

    public string SourceLabel => Entry.Kind switch
    {
        UnifiedHistoryKind.Dictation when Entry.DictationEntry is { } dictation
            && HomeTextSource.TryClassify(dictation, out var source)
            && source is not HomeTextSourceFilter.All
            && source is not HomeTextSourceFilter.Dictation => source switch
            {
                HomeTextSourceFilter.Qwen => L10n.Localize("HistorySourceQwen"),
                HomeTextSourceFilter.TencentCloud => L10n.Localize("HistorySourceTencent"),
                HomeTextSourceFilter.AliyunDashScope => L10n.Localize("HistorySourceAliyun"),
                HomeTextSourceFilter.Volcengine => L10n.Localize("HistorySourceVolcengine"),
                _ => L10n.Localize("HistorySourceDictation"),
            },
        UnifiedHistoryKind.Dictation => L10n.Localize("HistorySourceDictation"),
        UnifiedHistoryKind.SelectionTranslation =>
            L10n.Localize("HistorySourceSelectionTranslation"),
        UnifiedHistoryKind.SelectionSummary =>
            L10n.Localize("HistorySourceSelectionSummary"),
        UnifiedHistoryKind.AgentCompose => L10n.Localize("HistorySourceAgentCompose"),
        UnifiedHistoryKind.FileTranscription =>
            L10n.Localize("HistorySourceFileTranscription"),
        UnifiedHistoryKind.Screenshot => L10n.Localize("HistorySourceScreenshot"),
        _ => Entry.Title,
    };

    public string RawTextPreview => Entry.RawText;

    public string ResultTextPreview => Entry.ResultText;

    public string ContentTypeLabel => Entry.Kind switch
    {
        UnifiedHistoryKind.Dictation => L10n.Localize("HistoryContentTypeVoice"),
        UnifiedHistoryKind.Screenshot => L10n.Localize("HistoryContentTypeImage"),
        UnifiedHistoryKind.FileTranscription => L10n.Localize("HistoryContentTypeFile"),
        UnifiedHistoryKind.SelectionTranslation
            or UnifiedHistoryKind.SelectionSummary
            or UnifiedHistoryKind.AgentCompose => L10n.Localize("HistoryContentTypeWorkflow"),
        _ => L10n.Localize("HistoryContentTypeText"),
    };

    public string DisplayTitle => string.IsNullOrWhiteSpace(Title)
        ? SourceLabel
        : Title;

    public string MetaPreview
    {
        get
        {
            var preview = string.IsNullOrWhiteSpace(ResultTextPreview)
                ? RawTextPreview
                : ResultTextPreview;
            return preview.ReplaceLineEndings(" ").Trim();
        }
    }
}

/// <summary>
/// Classifies dictation providers when metadata is available; unknown sources still count as dictation assets (mac parity).
/// </summary>
internal static class HomeTextSource
{
    public static bool TryClassify(
        HistoryEntry entry,
        out HomeTextSourceFilter source)
    {
        if (entry.Metadata.AsrProvider is { } provider)
        {
            source = provider switch
            {
                Domain.AsrProviderId.Qwen => HomeTextSourceFilter.Qwen,
                Domain.AsrProviderId.TencentCloud => HomeTextSourceFilter.TencentCloud,
                Domain.AsrProviderId.AliyunDashScope => HomeTextSourceFilter.AliyunDashScope,
                Domain.AsrProviderId.Volcengine => HomeTextSourceFilter.Volcengine,
                _ => HomeTextSourceFilter.Dictation,
            };
            return true;
        }

        var normalized = entry.Source.Trim().ToLowerInvariant();
        if (normalized.StartsWith("qwen", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.Qwen;
            return true;
        }

        if (normalized.StartsWith("tencent", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.TencentCloud;
            return true;
        }

        if (normalized.StartsWith("aliyun", StringComparison.Ordinal)
            || normalized.StartsWith("dashscope", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.AliyunDashScope;
            return true;
        }

        if (normalized.StartsWith("volcengine", StringComparison.Ordinal)
            || normalized.StartsWith("doubao", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.Volcengine;
            return true;
        }

        // macOS keeps unconfigured / agent-style dictation rows as dictation assets.
        source = HomeTextSourceFilter.Dictation;
        return true;
    }
}
