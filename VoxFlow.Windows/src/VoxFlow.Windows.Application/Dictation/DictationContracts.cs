using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Dictation;

public enum AsrProviderAvailability
{
    Unconfigured,
    NotReady,
    Ready,
}

public enum DictationStartOutcome
{
    Started,
    NeedsConfiguration,
    ProviderNotReady,
    AlreadyActive,
    Failed,
}

public enum DictationGuidance
{
    None,
    ConfigureAsr,
    PrepareSelectedProvider,
}

public sealed record AsrPartialResult
{
    public AsrPartialResult(string text, long revision)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentOutOfRangeException.ThrowIfNegative(revision);

        Text = text;
        Revision = revision;
    }

    public string Text { get; }

    public long Revision { get; }
}

public sealed record AsrFinalResult
{
    public AsrFinalResult(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        Text = text;
    }

    public string Text { get; }
}

public interface IDictationAsrProvider
{
    AsrProviderAvailability Availability { get; }

    ValueTask<IDictationAsrSession> CreateSessionAsync(
        Guid generation,
        CancellationToken cancellationToken);
}

public interface IDictationAsrSession : IAsyncDisposable
{
    event EventHandler<AsrPartialResult>? PartialReceived;

    event EventHandler<AsrFinalResult>? FinalReceived;

    event EventHandler<VoxFlowError>? Failed;

    ValueTask StartAsync(CancellationToken cancellationToken);

    ValueTask PushAudioAsync(
        ReadOnlyMemory<byte> pcmS16LittleEndian,
        CancellationToken cancellationToken);

    ValueTask FinishAsync(CancellationToken cancellationToken);

    ValueTask CancelAsync(CancellationToken cancellationToken);
}

public interface IDictationAudioCapture
{
    ValueTask StartAsync(
        Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
        CancellationToken cancellationToken);

    ValueTask StopAsync(CancellationToken cancellationToken);
}

public interface IDictationAudioFailureSource
{
    event EventHandler<VoxFlowError>? Failed;
}

public sealed class DictationAudioCaptureException : Exception
{
    public DictationAudioCaptureException(
        VoxFlowError error,
        Exception innerException)
        : base("The audio capture operation failed.", innerException)
    {
        Error = error ?? throw new ArgumentNullException(nameof(error));
    }

    public VoxFlowError Error { get; }
}

public interface IDictationTextPostProcessor
{
    ValueTask<string> ProcessAsync(
        string text,
        IProgress<string> streamingProgress,
        CancellationToken cancellationToken);
}

/// <summary>
/// Lets a specialized post-processor opt out of the normal dictation fallback
/// that writes the original ASR text when post-processing fails. Agent Compose
/// uses this to ensure a failed sidecar can never turn a voice instruction
/// into foreground text input.
/// </summary>
public interface IDictationTextPostProcessorFailurePolicy
{
    bool UseAuthoritativeTextOnFailure { get; }
}

public interface IDictationOutput
{
    ValueTask<OutputResult> WriteAsync(
        string text,
        CancellationToken cancellationToken);
}

public interface IDictationTargetCapture
{
    void CaptureOriginalTarget();
}

public interface IDictationHistorySink
{
    ValueTask SaveAsync(
        DictationHistoryDraft draft,
        CancellationToken cancellationToken);
}

/// <summary>
/// Receives already-sanitized presentation snapshots. Implementations must
/// enqueue UI work and return promptly because partial results may originate
/// on a provider callback thread.
/// </summary>
public interface IDictationProgressSink
{
    void Publish(DictationProgressUpdate update);
}

public sealed record DictationHistoryDraft(
    Guid Generation,
    string RawText,
    string FinalText,
    OutputResult Output,
    DateTimeOffset CreatedAtUtc);

public sealed record DictationProgressUpdate(
    DictationSnapshot? Snapshot = null,
    string? PartialText = null,
    string? ProcessingText = null,
    DictationGuidance Guidance = DictationGuidance.None);
