using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Home;

public interface IHomeHistoryDetail
{
    string Id { get; }

    string Title { get; }

    string SourceLabel { get; }

    string ContentTypeLabel { get; }

    string RawText { get; }

    string FinalText { get; }

    string EditedFinalText { get; set; }

    string SanitizedDiagnostic { get; }

    bool IsDictation { get; }

    bool IsWorkflow { get; }

    bool IsScreenshot { get; }

    bool IsReadOnly { get; }
}

public sealed class HistoryDetailViewModel : INotifyPropertyChanged, IHomeHistoryDetail
{
    private string finalText;
    private string editedFinalText;

    internal HistoryDetailViewModel(HistoryEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        Id = entry.Id;
        Title = string.IsNullOrWhiteSpace(entry.Source)
            ? L10n.Localize("HistorySourceDictation")
            : entry.Source;
        SourceLabel = L10n.Localize("HistorySourceDictation");
        ContentTypeLabel = L10n.Localize("HistoryContentTypeVoice");
        RawText = entry.RawText;
        finalText = entry.FinalText;
        editedFinalText = entry.FinalText;
        CreatedAtUtc = entry.CreatedAtUtc;
        Recovered = entry.Metadata.Recovered;
        CapturedFrameCount = entry.Metadata.CapturedFrameCount;
        DroppedFrameCount = entry.Metadata.DroppedFrameCount;
        DurationMilliseconds = entry.Metadata.DurationMilliseconds;
        ErrorCode = entry.Metadata.ErrorCode;
        AsrProvider = entry.Metadata.AsrProvider;
        QwenVariant = entry.Metadata.QwenVariant;
        RecognitionLanguage = entry.Metadata.RecognitionLanguage;
        LlmProvider = entry.Metadata.LlmProvider;
        LlmDurationMilliseconds = entry.Metadata.LlmDurationMilliseconds;
        SanitizedDiagnostic = JsonSerializer.Serialize(
            new HistoryDiagnostic(
                SchemaVersion: 1,
                CreatedAtUtc,
                Recovered,
                CapturedFrameCount,
                DroppedFrameCount,
                DurationMilliseconds,
                ErrorCode,
                AsrProvider,
                QwenVariant,
                RecognitionLanguage,
                LlmProvider,
                LlmDurationMilliseconds),
            DomainJson.Options);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Id { get; }

    public string Title { get; }

    public string SourceLabel { get; }

    public string ContentTypeLabel { get; }

    public string RawText { get; }

    public string FinalText
    {
        get => finalText;
        private set
        {
            if (finalText == value)
            {
                return;
            }

            finalText = value;
            OnPropertyChanged();
        }
    }

    public string EditedFinalText
    {
        get => editedFinalText;
        set
        {
            ArgumentNullException.ThrowIfNull(value);
            if (editedFinalText == value)
            {
                return;
            }

            editedFinalText = value;
            OnPropertyChanged();
        }
    }

    public DateTimeOffset CreatedAtUtc { get; }

    public bool Recovered { get; }

    public long CapturedFrameCount { get; }

    public long DroppedFrameCount { get; }

    public long? DurationMilliseconds { get; }

    public VoxFlowErrorCode? ErrorCode { get; }

    public AsrProviderId? AsrProvider { get; }

    public QwenVariant? QwenVariant { get; }

    public RecognitionLanguage? RecognitionLanguage { get; }

    public LlmProviderId? LlmProvider { get; }

    public long? LlmDurationMilliseconds { get; }

    public string SanitizedDiagnostic { get; }

    public bool IsDictation => true;

    public bool IsWorkflow => false;

    public bool IsScreenshot => false;

    public bool IsReadOnly => false;

    internal void ApplyFinalText(string value)
    {
        FinalText = value;
        EditedFinalText = value;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private sealed record HistoryDiagnostic(
        int SchemaVersion,
        DateTimeOffset CreatedAtUtc,
        bool Recovered,
        long CapturedFrameCount,
        long DroppedFrameCount,
        long? DurationMilliseconds,
        VoxFlowErrorCode? ErrorCode,
        AsrProviderId? AsrProvider,
        QwenVariant? QwenVariant,
        RecognitionLanguage? RecognitionLanguage,
        LlmProviderId? LlmProvider,
        long? LlmDurationMilliseconds);
}

public sealed record WorkflowHistoryEventViewModel(
    AgentActionEventKind Kind,
    string Title,
    string? Detail,
    DateTimeOffset TimestampUtc,
    long? ElapsedMilliseconds,
    string? ToolName,
    bool IsFailure);

public sealed record WorkflowHistoryArtifactViewModel(
    string Id,
    AgentArtifactKind Kind,
    string Path,
    string? Summary,
    DateTimeOffset? UpdatedAtUtc);

public sealed class WorkflowHistoryDetailViewModel : IHomeHistoryDetail
{
    internal WorkflowHistoryDetailViewModel(UnifiedHistoryEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        var task = entry.WorkflowTask
            ?? throw new ArgumentException(
                "A workflow detail requires a workflow task.",
                nameof(entry));
        Id = entry.Id;
        Title = entry.Title;
        SourceLabel = entry.Kind switch
        {
            UnifiedHistoryKind.SelectionTranslation =>
                L10n.Localize("HistorySourceSelectionTranslation"),
            UnifiedHistoryKind.SelectionSummary =>
                L10n.Localize("HistorySourceSelectionSummary"),
            UnifiedHistoryKind.AgentCompose => L10n.Localize("HistorySourceAgentCompose"),
            _ => entry.Title,
        };
        ContentTypeLabel = L10n.Localize("HistoryContentTypeWorkflow");
        RawText = task.RawText ?? string.Empty;
        FinalText = entry.ResultText;
        EditedFinalText = FinalText;
        OriginalText = RawText;
        ResultText = FinalText;
        VoiceInstruction = task.Kind == WorkflowTaskKind.AgentCompose
            ? RawText
            : string.Empty;
        IsAgent = task.Kind == WorkflowTaskKind.AgentCompose;
        IsSelection = task.Kind is WorkflowTaskKind.SelectionTranslation
            or WorkflowTaskKind.SelectionSummary;
        Kind = task.Kind;
        Status = task.Status;
        ProviderId = task.ProviderId;
        Model = task.Model;
        CreatedAtUtc = entry.CreatedAtUtc;
        DurationMilliseconds = entry.DurationMilliseconds;

        var trace = ReadTrace(task.TraceJson);
        ContextSources = ReadContextSources(task.ContextJson, trace)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        Events = (trace?.Events ?? [])
            .Select(agentEvent => new WorkflowHistoryEventViewModel(
                agentEvent.Kind,
                agentEvent.Title,
                agentEvent.Detail,
                DateTimeOffset.FromUnixTimeMilliseconds(agentEvent.TimestampUnixMs),
                agentEvent.ElapsedMs,
                agentEvent.ToolName,
                agentEvent.IsFailure))
            .ToArray();
        ToolNames = Events
            .Select(agentEvent => agentEvent.ToolName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Select(name => name!)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        Artifacts = (trace?.Artifacts ?? [])
            .Select(artifact => new WorkflowHistoryArtifactViewModel(
                artifact.Id,
                artifact.Kind,
                artifact.Path,
                artifact.Summary,
                artifact.UpdatedAtUnixMs is { } updated
                    ? DateTimeOffset.FromUnixTimeMilliseconds(updated)
                    : null))
            .ToArray();
        ResultSummary = trace?.ResultSummary ?? FinalText;
        FailureCode = ReadFailureCode(task.FailureJson);
        SanitizedDiagnostic = JsonSerializer.Serialize(
            new
            {
                schemaVersion = 1,
                kind = task.Kind,
                status = task.Status,
                task.ProviderId,
                task.Model,
                entry.DurationMilliseconds,
                contextSources = ContextSources,
                eventCount = Events.Count,
                toolNames = ToolNames,
                artifactCount = Artifacts.Count,
                failureCode = FailureCode,
            },
            DomainJson.Options);
    }

    public string Id { get; }

    public string Title { get; }

    public string SourceLabel { get; }

    public string ContentTypeLabel { get; }

    public string RawText { get; }

    public string FinalText { get; }

    public string EditedFinalText { get; set; }

    public string SanitizedDiagnostic { get; }

    public bool IsDictation => false;

    public bool IsWorkflow => true;

    public bool IsScreenshot => false;

    public bool IsReadOnly => true;

    public bool IsAgent { get; }

    public bool IsSelection { get; }

    public WorkflowTaskKind Kind { get; }

    public WorkflowTaskStatus Status { get; }

    public string StatusLabel => Status switch
    {
        WorkflowTaskStatus.Pending => L10n.Localize("WorkflowStatusPending"),
        WorkflowTaskStatus.Running => L10n.Localize("WorkflowStatusRunning"),
        WorkflowTaskStatus.PartiallyCompleted => L10n.Localize("WorkflowStatusPartiallyCompleted"),
        WorkflowTaskStatus.Completed => L10n.Localize("WorkflowStatusCompleted"),
        WorkflowTaskStatus.Failed => L10n.Localize("WorkflowStatusFailed"),
        WorkflowTaskStatus.Cancelled => L10n.Localize("WorkflowStatusCancelled"),
        WorkflowTaskStatus.Interrupted => L10n.Localize("WorkflowStatusInterrupted"),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public string OriginalText { get; }

    public string ResultText { get; }

    public string VoiceInstruction { get; }

    public string? ProviderId { get; }

    public string? Model { get; }

    public DateTimeOffset CreatedAtUtc { get; }

    public long? DurationMilliseconds { get; }

    public IReadOnlyList<string> ContextSources { get; }

    public IReadOnlyList<WorkflowHistoryEventViewModel> Events { get; }

    public IReadOnlyList<string> ToolNames { get; }

    public IReadOnlyList<WorkflowHistoryArtifactViewModel> Artifacts { get; }

    public string ResultSummary { get; }

    public string? FailureCode { get; }

    public bool HasFailure => !string.IsNullOrWhiteSpace(FailureCode);

    private static AgentActionTrace? ReadTrace(JsonElement? traceJson)
    {
        if (traceJson is null)
        {
            return null;
        }
        try
        {
            return JsonSerializer.Deserialize<AgentActionTrace>(
                traceJson.Value.GetRawText(),
                DomainJson.Options);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static IEnumerable<string> ReadContextSources(
        JsonElement? contextJson,
        AgentActionTrace? trace)
    {
        if (contextJson is { ValueKind: JsonValueKind.Object } context
            && context.TryGetProperty("sources", out var sources)
            && sources.ValueKind == JsonValueKind.Array)
        {
            foreach (var source in sources.EnumerateArray())
            {
                if (source.ValueKind == JsonValueKind.String
                    && !string.IsNullOrWhiteSpace(source.GetString()))
                {
                    yield return source.GetString()!;
                }
            }
        }
        if (trace?.ScreenContext is { } screenContext)
        {
            foreach (var source in screenContext.Sources)
            {
                yield return source;
            }
        }
    }

    private static string? ReadFailureCode(JsonElement? failureJson)
    {
        if (failureJson is not { ValueKind: JsonValueKind.Object } failure
            || !failure.TryGetProperty("code", out var code)
            || code.ValueKind != JsonValueKind.String)
        {
            return null;
        }
        return code.GetString();
    }
}

/// <summary>
/// Read-only home detail for screenshot assets (macOS HomeAssetDetailModal parity).
/// </summary>
public sealed class ScreenshotHistoryDetailViewModel : IHomeHistoryDetail
{
    internal ScreenshotHistoryDetailViewModel(
        UnifiedHistoryEntry entry,
        IScreenshotAssetStore? assets = null)
    {
        ArgumentNullException.ThrowIfNull(entry);
        var record = entry.ScreenshotRecord
            ?? throw new ArgumentException(
                "A screenshot detail requires a screenshot record.",
                nameof(entry));
        Id = entry.Id;
        Title = entry.Title;
        SourceLabel = L10n.Localize("HistorySourceScreenshot");
        ContentTypeLabel = L10n.Localize("HistoryContentTypeImage");
        RawText = record.OcrText;
        FinalText = entry.ResultText;
        EditedFinalText = FinalText;
        PreviewText = string.IsNullOrWhiteSpace(entry.ResultText)
            ? record.OcrText
            : entry.ResultText;
        ThumbnailPath = record.ThumbnailPath;
        RenderedImagePath = record.RenderedImagePath;
        WidthPixels = record.WidthPixels;
        HeightPixels = record.HeightPixels;
        CreatedAtUtc = record.CreatedAtUtc;
        IsFavorite = record.IsFavorite;
        FavoriteLabel = record.IsFavorite
            ? L10n.Localize("ScreenshotFavorited")
            : L10n.Localize("ScreenshotNotFavorited");
        ResolutionText = $"{record.WidthPixels} × {record.HeightPixels}";
        AbsoluteImagePath = ResolveImagePath(assets, record);
        DisplayedImage = TryLoadImage(AbsoluteImagePath);
        HasImage = DisplayedImage is not null;
        SanitizedDiagnostic = JsonSerializer.Serialize(
            new
            {
                schemaVersion = 1,
                kind = "screenshot",
                record.Id,
                record.WidthPixels,
                record.HeightPixels,
                record.FileSizeBytes,
                record.SourceDisplayId,
                record.IsFavorite,
                ocrLength = record.OcrText.Length,
                hasRefined = !string.IsNullOrWhiteSpace(record.RefinedText),
                hasTranslated = !string.IsNullOrWhiteSpace(record.TranslatedText),
                hasSummary = !string.IsNullOrWhiteSpace(record.SummaryText),
                absoluteImagePath = AbsoluteImagePath,
            },
            DomainJson.Options);
    }

    public string Id { get; }

    public string Title { get; }

    public string SourceLabel { get; }

    public string ContentTypeLabel { get; }

    public string RawText { get; }

    public string FinalText { get; }

    public string EditedFinalText { get; set; }

    public string PreviewText { get; }

    public string SanitizedDiagnostic { get; }

    public bool IsDictation => false;

    public bool IsWorkflow => false;

    public bool IsScreenshot => true;

    public bool IsReadOnly => true;

    public string ThumbnailPath { get; }

    public string RenderedImagePath { get; }

    public string? AbsoluteImagePath { get; }

    public ImageSource? DisplayedImage { get; }

    public bool HasImage { get; }

    public int WidthPixels { get; }

    public int HeightPixels { get; }

    public string ResolutionText { get; }

    public DateTimeOffset CreatedAtUtc { get; }

    public bool IsFavorite { get; }

    public string FavoriteLabel { get; }

    private static string? ResolveImagePath(
        IScreenshotAssetStore? assets,
        ScreenshotRecord record)
    {
        foreach (var relative in new[]
                 {
                     record.RenderedImagePath,
                     record.ThumbnailPath,
                     record.OriginalImagePath,
                 })
        {
            if (string.IsNullOrWhiteSpace(relative))
            {
                continue;
            }

            try
            {
                if (assets is not null)
                {
                    var absolute = assets.ResolveAbsolutePath(relative);
                    if (File.Exists(absolute))
                    {
                        return absolute;
                    }
                }
                else if (Path.IsPathRooted(relative) && File.Exists(relative))
                {
                    return relative;
                }
            }
            catch (ArgumentException)
            {
                // Ignore invalid managed paths and try the next candidate.
            }
        }

        return null;
    }

    private static ImageSource? TryLoadImage(string? absolutePath)
    {
        if (string.IsNullOrWhiteSpace(absolutePath) || !File.Exists(absolutePath))
        {
            return null;
        }

        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(absolutePath, UriKind.Absolute);
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }
}

/// <summary>
/// Read-only detail for file transcription and other non-dictation text assets.
/// </summary>
public sealed class GenericAssetHistoryDetailViewModel : IHomeHistoryDetail
{
    internal GenericAssetHistoryDetailViewModel(UnifiedHistoryEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        Id = entry.Id;
        Title = entry.Title;
        SourceLabel = entry.Kind switch
        {
            UnifiedHistoryKind.FileTranscription =>
                L10n.Localize("HistorySourceFileTranscription"),
            UnifiedHistoryKind.Screenshot => L10n.Localize("HistorySourceScreenshot"),
            _ => entry.Title,
        };
        ContentTypeLabel = entry.Kind switch
        {
            UnifiedHistoryKind.FileTranscription =>
                L10n.Localize("HistoryContentTypeFile"),
            UnifiedHistoryKind.Screenshot => L10n.Localize("HistoryContentTypeImage"),
            _ => L10n.Localize("HistoryContentTypeText"),
        };
        RawText = entry.RawText;
        FinalText = entry.ResultText;
        EditedFinalText = FinalText;
        PreviewText = string.IsNullOrWhiteSpace(entry.ResultText)
            ? entry.RawText
            : entry.ResultText;
        CreatedAtUtc = entry.CreatedAtUtc;
        Status = entry.Status;
        ProviderId = entry.ProviderId;
        Model = entry.Model;
        DurationMilliseconds = entry.DurationMilliseconds;
        SanitizedDiagnostic = JsonSerializer.Serialize(
            new
            {
                schemaVersion = 1,
                kind = entry.Kind.ToString(),
                entry.Id,
                entry.Status,
                entry.ProviderId,
                entry.Model,
                entry.DurationMilliseconds,
            },
            DomainJson.Options);
    }

    public string Id { get; }

    public string Title { get; }

    public string SourceLabel { get; }

    public string ContentTypeLabel { get; }

    public string RawText { get; }

    public string FinalText { get; }

    public string EditedFinalText { get; set; }

    public string PreviewText { get; }

    public string SanitizedDiagnostic { get; }

    public bool IsDictation => false;

    public bool IsWorkflow => false;

    public bool IsScreenshot => false;

    public bool IsReadOnly => true;

    public bool IsGenericAsset => true;

    public DateTimeOffset CreatedAtUtc { get; }

    public string Status { get; }

    public string? ProviderId { get; }

    public string? Model { get; }

    public long? DurationMilliseconds { get; }
}
