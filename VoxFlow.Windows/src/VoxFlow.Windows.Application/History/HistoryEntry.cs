using System.Text.Json.Serialization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.History;

public sealed record HistoryEntry(
    string Id,
    string Source,
    string RawText,
    string FinalText,
    HistoryMetadata Metadata,
    DateTimeOffset CreatedAtUtc);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record HistoryMetadata
{
    [JsonConstructor]
    public HistoryMetadata(
        bool recovered = false,
        long capturedFrameCount = 0,
        long droppedFrameCount = 0,
        long? durationMilliseconds = null,
        VoxFlowErrorCode? errorCode = null,
        AsrProviderId? asrProvider = null,
        QwenVariant? qwenVariant = null,
        RecognitionLanguage? recognitionLanguage = null,
        LlmProviderId? llmProvider = null,
        long? llmDurationMilliseconds = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(capturedFrameCount);
        ArgumentOutOfRangeException.ThrowIfNegative(droppedFrameCount);
        if (durationMilliseconds is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(durationMilliseconds));
        }

        if (llmDurationMilliseconds is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(llmDurationMilliseconds));
        }

        if (qwenVariant is not null && asrProvider != AsrProviderId.Qwen)
        {
            throw new ArgumentException(
                "A Qwen history variant requires the Qwen ASR provider.",
                nameof(qwenVariant));
        }

        if (llmDurationMilliseconds is not null && llmProvider is null)
        {
            throw new ArgumentException(
                "An LLM duration requires an LLM provider.",
                nameof(llmDurationMilliseconds));
        }

        Recovered = recovered;
        CapturedFrameCount = capturedFrameCount;
        DroppedFrameCount = droppedFrameCount;
        DurationMilliseconds = durationMilliseconds;
        ErrorCode = errorCode;
        AsrProvider = asrProvider;
        QwenVariant = qwenVariant;
        RecognitionLanguage = recognitionLanguage;
        LlmProvider = llmProvider;
        LlmDurationMilliseconds = llmDurationMilliseconds;
    }

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
}
