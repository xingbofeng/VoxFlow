using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum FileTranscriptionJobStatus
{
    [JsonStringEnumMemberName("queued")]
    Queued,

    [JsonStringEnumMemberName("running")]
    Running,

    [JsonStringEnumMemberName("interrupted")]
    Interrupted,

    [JsonStringEnumMemberName("completed")]
    Completed,

    [JsonStringEnumMemberName("partiallyFailed")]
    PartiallyFailed,

    [JsonStringEnumMemberName("cancelled")]
    Cancelled,

    [JsonStringEnumMemberName("failed")]
    Failed,
}

public enum FileTranscriptionSegmentStatus
{
    [JsonStringEnumMemberName("pending")]
    Pending,

    [JsonStringEnumMemberName("running")]
    Running,

    [JsonStringEnumMemberName("completed")]
    Completed,

    [JsonStringEnumMemberName("failed")]
    Failed,

    [JsonStringEnumMemberName("interrupted")]
    Interrupted,

    [JsonStringEnumMemberName("cancelled")]
    Cancelled,
}

public enum FileTranscriptionProviderMode
{
    [JsonStringEnumMemberName("segmentedPcm")]
    SegmentedPcm,
}

public enum SegmentFallbackReason
{
    [JsonStringEnumMemberName("none")]
    None,

    [JsonStringEnumMemberName("retryAfterEmptyResult")]
    RetryAfterEmptyResult,

    [JsonStringEnumMemberName("retryAfterDuplicateResult")]
    RetryAfterDuplicateResult,

    [JsonStringEnumMemberName("retryAfterProviderError")]
    RetryAfterProviderError,
}

public enum FileTranscriptionTranslationStatus
{
    [JsonStringEnumMemberName("notRequested")]
    NotRequested,

    [JsonStringEnumMemberName("pending")]
    Pending,

    [JsonStringEnumMemberName("running")]
    Running,

    [JsonStringEnumMemberName("completed")]
    Completed,

    [JsonStringEnumMemberName("failed")]
    Failed,
}

public enum FileTranscriptionExportFormat
{
    [JsonStringEnumMemberName("text")]
    Text,

    [JsonStringEnumMemberName("markdown")]
    Markdown,

    [JsonStringEnumMemberName("srt")]
    Srt,

    [JsonStringEnumMemberName("translatedText")]
    TranslatedText,

    [JsonStringEnumMemberName("translatedMarkdown")]
    TranslatedMarkdown,

    [JsonStringEnumMemberName("bilingualMarkdown")]
    BilingualMarkdown,
}

public enum FileTranscriptionErrorCode
{
    [JsonStringEnumMemberName("sourceUnavailable")]
    SourceUnavailable,

    [JsonStringEnumMemberName("unsupportedMedia")]
    UnsupportedMedia,

    [JsonStringEnumMemberName("noAudioTrack")]
    NoAudioTrack,

    [JsonStringEnumMemberName("runtimeUnavailable")]
    RuntimeUnavailable,

    [JsonStringEnumMemberName("insufficientDiskSpace")]
    InsufficientDiskSpace,

    [JsonStringEnumMemberName("providerFailure")]
    ProviderFailure,

    [JsonStringEnumMemberName("providerUnavailable")]
    ProviderUnavailable,

    [JsonStringEnumMemberName("providerAuthenticationFailed")]
    ProviderAuthenticationFailed,

    [JsonStringEnumMemberName("providerQuotaExceeded")]
    ProviderQuotaExceeded,

    [JsonStringEnumMemberName("providerAudioFormatInvalid")]
    ProviderAudioFormatInvalid,

    [JsonStringEnumMemberName("providerModelNotReady")]
    ProviderModelNotReady,

    [JsonStringEnumMemberName("providerNetworkFailure")]
    ProviderNetworkFailure,

    [JsonStringEnumMemberName("segmentTimedOut")]
    SegmentTimedOut,

    [JsonStringEnumMemberName("translationFailure")]
    TranslationFailure,
}

public sealed record FileTranscriptionJob
{
    [JsonConstructor]
    public FileTranscriptionJob(
        string id,
        string sourcePath,
        string displayName,
        AsrProviderId provider,
        RecognitionLanguage language,
        long createdAtUnixMs,
        FileTranscriptionJobStatus status = FileTranscriptionJobStatus.Queued,
        long? durationMs = null,
        double progress = 0,
        string? rawText = null,
        string? finalText = null,
        FileTranscriptionErrorCode? errorCode = null,
        FileTranscriptionProviderMode providerMode = FileTranscriptionProviderMode.SegmentedPcm,
        int segmentCount = 0,
        int segmentCompleted = 0,
        string? partialFailureSummary = null,
        FileTranscriptionTranslationStatus translationStatus = FileTranscriptionTranslationStatus.NotRequested,
        string? translatedText = null,
        string? translationTargetLanguage = null,
        FileTranscriptionErrorCode? translationErrorCode = null,
        long? translationUpdatedAtUnixMs = null,
        long updatedAtUnixMs = long.MinValue,
        long? completedAtUnixMs = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(displayName);
        ArgumentOutOfRangeException.ThrowIfNegative(createdAtUnixMs);
        ValidateEnum(provider, nameof(provider));
        ValidateEnum(language, nameof(language));
        ValidateEnum(status, nameof(status));
        ValidateEnum(providerMode, nameof(providerMode));
        ValidateEnum(translationStatus, nameof(translationStatus));
        if (durationMs is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(durationMs));
        }

        if (progress is < 0 or > 1 || double.IsNaN(progress))
        {
            throw new ArgumentOutOfRangeException(nameof(progress));
        }

        ArgumentOutOfRangeException.ThrowIfNegative(segmentCount);
        ArgumentOutOfRangeException.ThrowIfNegative(segmentCompleted);
        if (segmentCompleted > segmentCount)
        {
            throw new ArgumentOutOfRangeException(nameof(segmentCompleted));
        }

        if (status == FileTranscriptionJobStatus.Failed && errorCode is null)
        {
            throw new ArgumentException("A failed file transcription job requires an error code.", nameof(errorCode));
        }

        if (status is FileTranscriptionJobStatus.Completed or FileTranscriptionJobStatus.PartiallyFailed &&
            string.IsNullOrWhiteSpace(finalText))
        {
            throw new ArgumentException("A completed file transcription job requires final text.", nameof(finalText));
        }

        if (translationStatus == FileTranscriptionTranslationStatus.Completed &&
            (string.IsNullOrWhiteSpace(translatedText) || string.IsNullOrWhiteSpace(translationTargetLanguage)))
        {
            throw new ArgumentException(
                "A completed translation requires text and a target language.",
                nameof(translatedText));
        }

        if (translationStatus == FileTranscriptionTranslationStatus.Failed && translationErrorCode is null)
        {
            throw new ArgumentException(
                "A failed translation requires an error code.",
                nameof(translationErrorCode));
        }

        var effectiveUpdatedAtUnixMs = updatedAtUnixMs == long.MinValue
            ? createdAtUnixMs
            : updatedAtUnixMs;
        ValidateTimestamp(effectiveUpdatedAtUnixMs, createdAtUnixMs, nameof(updatedAtUnixMs));
        ValidateTimestamp(translationUpdatedAtUnixMs, createdAtUnixMs, nameof(translationUpdatedAtUnixMs));
        ValidateTimestamp(completedAtUnixMs, createdAtUnixMs, nameof(completedAtUnixMs));

        Id = id;
        SourcePath = sourcePath;
        DisplayName = displayName;
        Provider = provider;
        Language = language;
        CreatedAtUnixMs = createdAtUnixMs;
        Status = status;
        DurationMs = durationMs;
        Progress = progress;
        RawText = rawText;
        FinalText = finalText;
        ErrorCode = errorCode;
        ProviderMode = providerMode;
        SegmentCount = segmentCount;
        SegmentCompleted = segmentCompleted;
        PartialFailureSummary = partialFailureSummary;
        TranslationStatus = translationStatus;
        TranslatedText = translatedText;
        TranslationTargetLanguage = translationTargetLanguage;
        TranslationErrorCode = translationErrorCode;
        TranslationUpdatedAtUnixMs = translationUpdatedAtUnixMs;
        UpdatedAtUnixMs = effectiveUpdatedAtUnixMs;
        CompletedAtUnixMs = completedAtUnixMs;
    }

    public string Id { get; }

    public string SourcePath { get; }

    public string DisplayName { get; }

    public AsrProviderId Provider { get; }

    public RecognitionLanguage Language { get; }

    public long CreatedAtUnixMs { get; }

    public FileTranscriptionJobStatus Status { get; }

    public long? DurationMs { get; }

    public double Progress { get; }

    public string? RawText { get; }

    public string? FinalText { get; }

    public FileTranscriptionErrorCode? ErrorCode { get; }

    public FileTranscriptionProviderMode ProviderMode { get; }

    public int SegmentCount { get; }

    public int SegmentCompleted { get; }

    public string? PartialFailureSummary { get; }

    public FileTranscriptionTranslationStatus TranslationStatus { get; }

    public string? TranslatedText { get; }

    public string? TranslationTargetLanguage { get; }

    public FileTranscriptionErrorCode? TranslationErrorCode { get; }

    public long? TranslationUpdatedAtUnixMs { get; }

    public long UpdatedAtUnixMs { get; }

    public long? CompletedAtUnixMs { get; }

    private static void ValidateTimestamp(long? value, long minimum, string parameterName)
    {
        if (value is < 0 || value < minimum)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void ValidateEnum<T>(T value, string parameterName) where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}

public sealed record FileTranscriptionSegment
{
    [JsonConstructor]
    public FileTranscriptionSegment(
        string jobId,
        int index,
        long startMs,
        long endMs,
        FileTranscriptionSegmentStatus status,
        AsrProviderId provider,
        string? text = null,
        int retryCount = 0,
        FileTranscriptionProviderMode providerMode = FileTranscriptionProviderMode.SegmentedPcm,
        SegmentFallbackReason fallbackReason = SegmentFallbackReason.None,
        FileTranscriptionErrorCode? errorCode = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        ArgumentOutOfRangeException.ThrowIfNegative(startMs);
        if (endMs <= startMs)
        {
            throw new ArgumentOutOfRangeException(nameof(endMs));
        }

        ArgumentOutOfRangeException.ThrowIfNegative(retryCount);
        ValidateEnum(status, nameof(status));
        ValidateEnum(provider, nameof(provider));
        ValidateEnum(providerMode, nameof(providerMode));
        ValidateEnum(fallbackReason, nameof(fallbackReason));
        if (errorCode is not null)
        {
            ValidateEnum(errorCode.Value, nameof(errorCode));
        }
        if (status == FileTranscriptionSegmentStatus.Completed && string.IsNullOrWhiteSpace(text))
        {
            throw new ArgumentException("A completed segment requires text.", nameof(text));
        }

        if (status == FileTranscriptionSegmentStatus.Failed && errorCode is null)
        {
            throw new ArgumentException("A failed segment requires an error code.", nameof(errorCode));
        }

        JobId = jobId;
        Index = index;
        StartMs = startMs;
        EndMs = endMs;
        Status = status;
        Provider = provider;
        Text = text;
        RetryCount = retryCount;
        ProviderMode = providerMode;
        FallbackReason = fallbackReason;
        ErrorCode = errorCode;
    }

    public string JobId { get; }

    public int Index { get; }

    public long StartMs { get; }

    public long EndMs { get; }

    public FileTranscriptionSegmentStatus Status { get; }

    public AsrProviderId Provider { get; }

    public string? Text { get; }

    public int RetryCount { get; }

    public FileTranscriptionProviderMode ProviderMode { get; }

    public SegmentFallbackReason FallbackReason { get; }

    public FileTranscriptionErrorCode? ErrorCode { get; }

    private static void ValidateEnum<T>(T value, string parameterName) where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}
