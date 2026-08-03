using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Dictation;

public sealed class DictationStateMachine
{
    private static readonly IReadOnlySet<DictationPhase> ActivePhases =
        new HashSet<DictationPhase>
        {
            DictationPhase.Preparing,
            DictationPhase.Recording,
            DictationPhase.WaitingForFinal,
            DictationPhase.Processing,
            DictationPhase.Injecting,
        };

    private static readonly IReadOnlySet<DictationPhase> ProviderFailurePhases =
        new HashSet<DictationPhase>
        {
            DictationPhase.Preparing,
            DictationPhase.Recording,
            DictationPhase.WaitingForFinal,
        };

    private readonly object syncRoot = new();
    private DictationSnapshot snapshot = DictationSnapshot.Idle;

    public DictationSnapshot Snapshot
    {
        get
        {
            lock (syncRoot)
            {
                return snapshot;
            }
        }
    }

    public void Begin(Guid generation)
    {
        if (generation == Guid.Empty)
        {
            throw new ArgumentException(
                "A dictation generation must not be empty.",
                nameof(generation));
        }

        lock (syncRoot)
        {
            RequireUnsafe(DictationPhase.Idle, DictationPhase.Preparing);
            snapshot = DictationSnapshot.Preparing(generation);
        }
    }

    public void Prepared()
    {
        lock (syncRoot)
        {
            RequireUnsafe(DictationPhase.Preparing, DictationPhase.Recording);
            snapshot = snapshot.ToRecording();
        }
    }

    public void StopRecording()
    {
        lock (syncRoot)
        {
            RequireUnsafe(DictationPhase.Recording, DictationPhase.WaitingForFinal);
            snapshot = snapshot.ToWaitingForFinal();
        }
    }

    /// <summary>
    /// Applies a provider final only when it belongs to the current active
    /// generation. Returns false for callbacks from cancelled or superseded
    /// sessions without mutating the current snapshot.
    /// </summary>
    public bool TryAcceptFinal(Guid generation, string finalText)
    {
        lock (syncRoot)
        {
            if (!IsCurrentGenerationUnsafe(generation)
                || snapshot.Phase != DictationPhase.WaitingForFinal)
            {
                return false;
            }

            if (string.IsNullOrWhiteSpace(finalText))
            {
                FailCurrentUnsafe(new VoxFlowError(VoxFlowErrorCode.EmptyFinal));
                return true;
            }

            snapshot = snapshot.WithAuthoritativeFinal(finalText);
            return true;
        }
    }

    /// <summary>
    /// Applies a final-result timeout only to the matching active generation.
    /// </summary>
    public bool TryFinalTimedOut(Guid generation)
    {
        lock (syncRoot)
        {
            if (!IsCurrentGenerationUnsafe(generation)
                || snapshot.Phase != DictationPhase.WaitingForFinal)
            {
                return false;
            }
            FailCurrentUnsafe(new VoxFlowError(VoxFlowErrorCode.FinalTimeout));
            return true;
        }
    }

    public bool TryProcessingCompleted(Guid generation, string outputText)
    {
        lock (syncRoot)
        {
            if (!IsCurrentGenerationUnsafe(generation)
                || snapshot.Phase != DictationPhase.Processing)
            {
                return false;
            }

            ArgumentException.ThrowIfNullOrWhiteSpace(outputText);
            snapshot = snapshot.WithProcessedOutput(outputText);
            return true;
        }
    }

    public bool TryOutputCompleted(Guid generation, OutputResult output)
    {
        ArgumentNullException.ThrowIfNull(output);

        lock (syncRoot)
        {
            if (!IsCurrentGenerationUnsafe(generation)
                || snapshot.Phase != DictationPhase.Injecting)
            {
                return false;
            }

            if (output.ErrorCode is { } errorCode)
            {
                snapshot = snapshot.WithFailure(
                    new VoxFlowError(errorCode),
                    output);
                return true;
            }

            if (output.Kind == OutputResultKind.Cancelled)
            {
                snapshot = DictationSnapshot.Idle;
                return true;
            }

            snapshot = snapshot.WithCompletedOutput(output);
            return true;
        }
    }

    /// <summary>
    /// Applies a provider error only when it belongs to the current active
    /// generation. Returns false for stale callbacks.
    /// </summary>
    public bool TryFail(Guid generation, VoxFlowError error)
    {
        ArgumentNullException.ThrowIfNull(error);

        lock (syncRoot)
        {
            if (!IsCurrentGenerationUnsafe(generation)
                || !ProviderFailurePhases.Contains(snapshot.Phase))
            {
                return false;
            }

            FailCurrentUnsafe(error);
            return true;
        }
    }

    /// <summary>
    /// Fails application-owned processing or output work without allowing a
    /// late provider callback to mutate those phases.
    /// </summary>
    internal bool TryOperationFailed(Guid generation, VoxFlowError error)
    {
        ArgumentNullException.ThrowIfNull(error);

        lock (syncRoot)
        {
            if (!IsCurrentGenerationUnsafe(generation)
                || snapshot.Phase is not (
                    DictationPhase.Processing or DictationPhase.Injecting))
            {
                return false;
            }

            FailCurrentUnsafe(error);
            return true;
        }
    }

    public void Cancel()
    {
        lock (syncRoot)
        {
            if (!ActivePhases.Contains(snapshot.Phase))
            {
                throw new InvalidDictationTransitionException(
                    snapshot.Phase,
                    DictationPhase.Idle);
            }

            snapshot = DictationSnapshot.Idle;
        }
    }

    public void Reset()
    {
        lock (syncRoot)
        {
            if (snapshot.Phase is not (DictationPhase.Completed or DictationPhase.Failed))
            {
                throw new InvalidDictationTransitionException(
                    snapshot.Phase,
                    DictationPhase.Idle);
            }

            snapshot = DictationSnapshot.Idle;
        }
    }

    private bool IsCurrentGenerationUnsafe(Guid generation) =>
        generation != Guid.Empty &&
        ActivePhases.Contains(snapshot.Phase) &&
        snapshot.Generation == generation;

    private void RequireUnsafe(DictationPhase current, DictationPhase requested)
    {
        if (snapshot.Phase != current)
        {
            throw new InvalidDictationTransitionException(
                snapshot.Phase,
                requested);
        }
    }

    private void FailCurrentUnsafe(VoxFlowError error)
    {
        snapshot = snapshot.WithFailure(error);
    }
}
