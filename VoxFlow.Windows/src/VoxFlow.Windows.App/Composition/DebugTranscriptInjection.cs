#if DEBUG
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Composition;

public enum DebugTranscriptInjectionMode
{
    Dictation,
    AgentCompose,
}

public enum DebugTranscriptInjectionStatus
{
    Completed,
    Busy,
    Unavailable,
    Failed,
}

public sealed record DebugTranscriptInjectionResult(
    DebugTranscriptInjectionStatus Status,
    DictationPhase? FinalPhase = null);

/// <summary>
/// Debug-only entry point that replaces microphone and ASR with one injected
/// final transcript while keeping the production post-processing, output,
/// history, HUD, and Agent execution dependencies supplied by the App.
/// </summary>
public sealed class DebugTranscriptInjectionRunner(
    Func<string, DebugTranscriptInjectionMode, DictationOrchestrator?> orchestratorFactory)
{
    private readonly Func<string, DebugTranscriptInjectionMode, DictationOrchestrator?>
        orchestratorFactory = orchestratorFactory
            ?? throw new ArgumentNullException(nameof(orchestratorFactory));
    private readonly SemaphoreSlim executionGate = new(1, 1);

    public bool IsBusy => executionGate.CurrentCount == 0;

    public async Task<DebugTranscriptInjectionResult> RunAsync(
        string transcript,
        DebugTranscriptInjectionMode mode,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(transcript);
        if (!Enum.IsDefined(mode))
        {
            throw new ArgumentOutOfRangeException(nameof(mode));
        }
        if (!await executionGate.WaitAsync(0, cancellationToken).ConfigureAwait(false))
        {
            return new DebugTranscriptInjectionResult(
                DebugTranscriptInjectionStatus.Busy);
        }

        try
        {
            var orchestrator = orchestratorFactory(transcript.Trim(), mode);
            if (orchestrator is null)
            {
                return new DebugTranscriptInjectionResult(
                    DebugTranscriptInjectionStatus.Unavailable);
            }
            await using var ownedOrchestrator = orchestrator;

            var started = await ownedOrchestrator.StartAsync(cancellationToken)
                .ConfigureAwait(false);
            if (started != DictationStartOutcome.Started)
            {
                return new DebugTranscriptInjectionResult(
                    DebugTranscriptInjectionStatus.Failed,
                    ownedOrchestrator.Snapshot.Phase);
            }

            await ownedOrchestrator.StopAsync(cancellationToken).ConfigureAwait(false);
            var phase = ownedOrchestrator.Snapshot.Phase;
            return new DebugTranscriptInjectionResult(
                phase == DictationPhase.Completed
                    ? DebugTranscriptInjectionStatus.Completed
                    : DebugTranscriptInjectionStatus.Failed,
                phase);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new DebugTranscriptInjectionResult(
                DebugTranscriptInjectionStatus.Failed);
        }
        finally
        {
            executionGate.Release();
        }
    }
}

internal sealed class DebugTranscriptAsrProvider(string transcript)
    : IDictationAsrProvider
{
    private readonly string transcript = string.IsNullOrWhiteSpace(transcript)
        ? throw new ArgumentException("A debug transcript is required.", nameof(transcript))
        : transcript.Trim();

    public AsrProviderAvailability Availability => AsrProviderAvailability.Ready;

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult<IDictationAsrSession>(
            new DebugTranscriptAsrSession(transcript));
    }
}

internal sealed class DebugTranscriptAsrSession(string transcript)
    : IDictationAsrSession
{
    public event EventHandler<AsrPartialResult>? PartialReceived;
    public event EventHandler<AsrFinalResult>? FinalReceived;
    public event EventHandler<VoxFlowError>? Failed
    {
        add { }
        remove { }
    }

    public ValueTask StartAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        PartialReceived?.Invoke(this, new AsrPartialResult(transcript, 1));
        return ValueTask.CompletedTask;
    }

    public ValueTask PushAudioAsync(
        ReadOnlyMemory<byte> pcmS16LittleEndian,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.CompletedTask;
    }

    public ValueTask FinishAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        FinalReceived?.Invoke(this, new AsrFinalResult(transcript));
        return ValueTask.CompletedTask;
    }

    public ValueTask CancelAsync(CancellationToken cancellationToken) =>
        ValueTask.CompletedTask;

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

internal sealed class DebugSilentAudioCapture : IDictationAudioCapture
{
    public ValueTask StartAsync(
        Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(onFrame);
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.CompletedTask;
    }

    public ValueTask StopAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.CompletedTask;
    }
}
#endif
