using System.Globalization;
using System.IO;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.FileTranscription;

public enum FileTranscriptionStatusTone
{
    Neutral,
    Active,
    Success,
    Warning,
    Destructive,
}

public sealed record FileTranscriptionSegmentDiagnostic(
    int Index,
    string Summary,
    FileTranscriptionSegmentStatus Status);

public sealed class FileTranscriptionJobPresentation
{
    public FileTranscriptionJobPresentation(
        FileTranscriptionJob job,
        IReadOnlyCollection<FileTranscriptionSegment> segments)
    {
        Job = job ?? throw new ArgumentNullException(nameof(job));
        ArgumentNullException.ThrowIfNull(segments);
        var diagnostics = segments
            .OrderBy(segment => segment.Index)
            .Select(segment => new FileTranscriptionSegmentDiagnostic(
                segment.Index,
                DiagnosticSummary(segment),
                segment.Status))
            .ToList();
        if (job.ErrorCode is { } jobError)
        {
            diagnostics.Add(new FileTranscriptionSegmentDiagnostic(
                -1,
                string.Format(
                    CultureInfo.CurrentUICulture,
                    L10n.Localize("FileTranscriptionJobDiagnosticErrorFormat"),
                    L10n.Localize(ErrorCodeKey(jobError))),
                FileTranscriptionSegmentStatus.Failed));
        }
        if (job.TranslationErrorCode is { } translationError)
        {
            diagnostics.Add(new FileTranscriptionSegmentDiagnostic(
                -1,
                string.Format(
                    CultureInfo.CurrentUICulture,
                    L10n.Localize("FileTranscriptionTranslationDiagnosticErrorFormat"),
                    L10n.Localize(ErrorCodeKey(translationError))),
                FileTranscriptionSegmentStatus.Failed));
        }
        Diagnostics = diagnostics;
    }

    public FileTranscriptionJob Job { get; }
    public string Id => Job.Id;
    public string DisplayName => Job.DisplayName;
    public string StatusTitle => L10n.Localize(StatusKey(Job.Status));
    public string StatusIcon => Job.Status switch
    {
        FileTranscriptionJobStatus.Queued => "○",
        FileTranscriptionJobStatus.Running => "◉",
        FileTranscriptionJobStatus.Completed => "✓",
        FileTranscriptionJobStatus.PartiallyFailed => "△",
        FileTranscriptionJobStatus.Interrupted => "Ⅱ",
        FileTranscriptionJobStatus.Cancelled => "×",
        FileTranscriptionJobStatus.Failed => "!",
        _ => "?",
    };
    public FileTranscriptionStatusTone StatusTone => Job.Status switch
    {
        FileTranscriptionJobStatus.Running => FileTranscriptionStatusTone.Active,
        FileTranscriptionJobStatus.Completed => FileTranscriptionStatusTone.Success,
        FileTranscriptionJobStatus.PartiallyFailed or FileTranscriptionJobStatus.Interrupted =>
            FileTranscriptionStatusTone.Warning,
        FileTranscriptionJobStatus.Failed => FileTranscriptionStatusTone.Destructive,
        _ => FileTranscriptionStatusTone.Neutral,
    };
    public int ProgressPercent => (int)Math.Round(Job.Progress * 100);
    public string ProgressLabel => $"{ProgressPercent}%";
    public string? FinalText => Job.FinalText;
    public string? TranslatedText => Job.TranslatedText;
    public bool HasTranslation =>
        Job.TranslationStatus == FileTranscriptionTranslationStatus.Completed
        && !string.IsNullOrWhiteSpace(Job.TranslatedText);
    public bool IsTranslating => Job.TranslationStatus is
        FileTranscriptionTranslationStatus.Pending
        or FileTranscriptionTranslationStatus.Running;
    public bool IsRunning => Job.Status == FileTranscriptionJobStatus.Running;
    public bool CanStart => Job.Status == FileTranscriptionJobStatus.Queued;
    public bool CanCancel => Job.Status == FileTranscriptionJobStatus.Running;
    public bool CanContinue => Job.Status is FileTranscriptionJobStatus.Interrupted
        or FileTranscriptionJobStatus.PartiallyFailed;
    public bool CanRetry => Job.Status is FileTranscriptionJobStatus.Interrupted
        or FileTranscriptionJobStatus.PartiallyFailed
        or FileTranscriptionJobStatus.Failed
        or FileTranscriptionJobStatus.Cancelled;
    public bool CanDelete => true;
    public bool CanPlay => File.Exists(Job.SourcePath);
    public bool CanUseResult => Job.Status is FileTranscriptionJobStatus.Completed
        or FileTranscriptionJobStatus.PartiallyFailed
        && !string.IsNullOrWhiteSpace(Job.FinalText);
    public bool CanTranslate => CanUseResult && !IsTranslating;
    public bool HasDiagnostics => Diagnostics.Count > 0 || Job.Status is
        FileTranscriptionJobStatus.Failed
        or FileTranscriptionJobStatus.PartiallyFailed
        or FileTranscriptionJobStatus.Interrupted;
    public string MetadataLine => string.Format(
        CultureInfo.CurrentUICulture,
        L10n.Localize("FileTranscriptionMetadataFormat"),
        Path.GetExtension(Job.DisplayName).TrimStart('.').ToUpperInvariant(),
        Duration(Job.DurationMs),
        ProviderName(Job.Provider),
        Job.SegmentCompleted,
        Job.SegmentCount);
    public string ResultSubtitle => string.Format(
        CultureInfo.CurrentUICulture,
        L10n.Localize("FileTranscriptionResultSubtitleFormat"),
        StatusTitle,
        MetadataLine);
    public string ProcessingSegmentLine => string.Format(
        CultureInfo.CurrentUICulture,
        L10n.Localize("FileTranscriptionProcessingSegment"),
        Math.Min(Job.SegmentCompleted + 1, Math.Max(Job.SegmentCount, 1)),
        Math.Max(Job.SegmentCount, 1));
    public IReadOnlyList<FileTranscriptionSegmentDiagnostic> Diagnostics { get; }

    private static string DiagnosticSummary(FileTranscriptionSegment segment) => string.Format(
        CultureInfo.CurrentUICulture,
        L10n.Localize("FileTranscriptionDiagnosticFormat"),
        segment.Index + 1,
        Duration(segment.StartMs),
        Duration(segment.EndMs),
        L10n.Localize(SegmentStatusKey(segment.Status)),
        segment.RetryCount,
        L10n.Localize(FallbackReasonKey(segment.FallbackReason)),
        segment.ErrorCode is { } errorCode
            ? L10n.Localize(ErrorCodeKey(errorCode))
            : L10n.Localize("FileTranscriptionDiagnosticNoError"));

    private static string ProviderName(AsrProviderId provider) => provider switch
    {
        AsrProviderId.Qwen => "Qwen3-ASR",
        AsrProviderId.TencentCloud => L10n.Localize("FileTranscriptionProviderTencent"),
        AsrProviderId.AliyunDashScope => L10n.Localize("FileTranscriptionProviderAliyun"),
        AsrProviderId.Volcengine => L10n.Localize("FileTranscriptionProviderVolcengine"),
        _ => provider.ToString(),
    };

    private static string Duration(long? milliseconds)
    {
        if (milliseconds is null) return "--:--";
        var totalSeconds = milliseconds.Value / 1_000;
        return totalSeconds >= 3_600
            ? $"{totalSeconds / 3_600}:{totalSeconds % 3_600 / 60:00}:{totalSeconds % 60:00}"
            : $"{totalSeconds / 60}:{totalSeconds % 60:00}";
    }

    private static string StatusKey(FileTranscriptionJobStatus status) => status switch
    {
        FileTranscriptionJobStatus.Queued => "FileTranscriptionStatusQueued",
        FileTranscriptionJobStatus.Running => "FileTranscriptionStatusRunning",
        FileTranscriptionJobStatus.Completed => "FileTranscriptionStatusCompleted",
        FileTranscriptionJobStatus.PartiallyFailed => "FileTranscriptionStatusPartiallyFailed",
        FileTranscriptionJobStatus.Interrupted => "FileTranscriptionStatusInterrupted",
        FileTranscriptionJobStatus.Cancelled => "FileTranscriptionStatusCancelled",
        FileTranscriptionJobStatus.Failed => "FileTranscriptionStatusFailed",
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    private static string SegmentStatusKey(FileTranscriptionSegmentStatus status) => status switch
    {
        FileTranscriptionSegmentStatus.Pending => "FileTranscriptionSegmentPending",
        FileTranscriptionSegmentStatus.Running => "FileTranscriptionSegmentRunning",
        FileTranscriptionSegmentStatus.Completed => "FileTranscriptionSegmentCompleted",
        FileTranscriptionSegmentStatus.Failed => "FileTranscriptionSegmentFailed",
        FileTranscriptionSegmentStatus.Interrupted => "FileTranscriptionSegmentInterrupted",
        FileTranscriptionSegmentStatus.Cancelled => "FileTranscriptionSegmentCancelled",
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    private static string FallbackReasonKey(SegmentFallbackReason reason) => reason switch
    {
        SegmentFallbackReason.None => "FileTranscriptionFallbackNone",
        SegmentFallbackReason.RetryAfterEmptyResult => "FileTranscriptionFallbackEmptyResult",
        SegmentFallbackReason.RetryAfterDuplicateResult => "FileTranscriptionFallbackDuplicateResult",
        SegmentFallbackReason.RetryAfterProviderError => "FileTranscriptionFallbackProviderError",
        _ => throw new ArgumentOutOfRangeException(nameof(reason)),
    };

    private static string ErrorCodeKey(FileTranscriptionErrorCode errorCode) => errorCode switch
    {
        FileTranscriptionErrorCode.SourceUnavailable => "FileTranscriptionErrorSourceUnavailable",
        FileTranscriptionErrorCode.UnsupportedMedia => "FileTranscriptionErrorUnsupportedMedia",
        FileTranscriptionErrorCode.NoAudioTrack => "FileTranscriptionErrorNoAudioTrack",
        FileTranscriptionErrorCode.RuntimeUnavailable => "FileTranscriptionErrorRuntimeUnavailable",
        FileTranscriptionErrorCode.InsufficientDiskSpace => "FileTranscriptionErrorInsufficientDiskSpace",
        FileTranscriptionErrorCode.ProviderFailure => "FileTranscriptionErrorProviderFailure",
        FileTranscriptionErrorCode.ProviderUnavailable => "FileTranscriptionErrorProviderUnavailable",
        FileTranscriptionErrorCode.ProviderAuthenticationFailed => "FileTranscriptionErrorProviderAuthentication",
        FileTranscriptionErrorCode.ProviderQuotaExceeded => "FileTranscriptionErrorProviderQuota",
        FileTranscriptionErrorCode.ProviderAudioFormatInvalid => "FileTranscriptionErrorProviderAudioFormat",
        FileTranscriptionErrorCode.ProviderModelNotReady => "FileTranscriptionErrorProviderModelNotReady",
        FileTranscriptionErrorCode.ProviderNetworkFailure => "FileTranscriptionErrorProviderNetwork",
        FileTranscriptionErrorCode.SegmentTimedOut => "FileTranscriptionErrorSegmentTimedOut",
        FileTranscriptionErrorCode.TranslationFailure => "FileTranscriptionErrorTranslation",
        _ => throw new ArgumentOutOfRangeException(nameof(errorCode)),
    };
}
