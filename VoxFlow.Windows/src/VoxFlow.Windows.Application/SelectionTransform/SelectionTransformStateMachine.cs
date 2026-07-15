namespace VoxFlow.Windows.Application.SelectionTransform;

public enum SelectionTransformOperation
{
    Translation,
    Summary,
    Refine,
    AskAi,
}

public enum SelectionTransformState
{
    Idle,
    Running,
    Completed,
    PartiallyCompleted,
    Failed,
    Cancelled,
}

public abstract record SelectionTransformEvent(Guid Generation);
public sealed record SelectionTransformStarted(Guid Generation) : SelectionTransformEvent(Generation);
public sealed record SelectionTransformPartial(Guid Generation, string Text) : SelectionTransformEvent(Generation);
public sealed record SelectionTransformCompleted(Guid Generation, string Text) : SelectionTransformEvent(Generation);
public sealed record SelectionTransformCancelled(Guid Generation, string PartialText) : SelectionTransformEvent(Generation);
public sealed record SelectionTransformFailed(Guid Generation, string SafeMessage, string PartialText) : SelectionTransformEvent(Generation);

/// <summary>
/// A generation-scoped accumulator. Streaming clients may replay cumulative
/// SSE snapshots; this machine publishes only the newest snapshot and never
/// lets a late generation mutate the visible result or history candidate.
/// </summary>
public sealed class SelectionTransformStateMachine
{
    public SelectionTransformStateMachine(Guid generation)
    {
        if (generation == Guid.Empty)
        {
            throw new ArgumentException("A non-empty generation is required.", nameof(generation));
        }

        Generation = generation;
    }

    public Guid Generation { get; }

    public SelectionTransformState State { get; private set; } = SelectionTransformState.Idle;

    public string LatestText { get; private set; } = string.Empty;

    public SelectionTransformStarted Start()
    {
        if (State != SelectionTransformState.Idle)
        {
            throw new InvalidOperationException("A selection transform can start only once.");
        }

        State = SelectionTransformState.Running;
        return new SelectionTransformStarted(Generation);
    }

    public SelectionTransformPartial? ApplySnapshot(Guid generation, string accumulatedText)
    {
        ArgumentNullException.ThrowIfNull(accumulatedText);
        if (generation != Generation || State != SelectionTransformState.Running)
        {
            return null;
        }

        if (string.Equals(LatestText, accumulatedText, StringComparison.Ordinal))
        {
            return null;
        }

        LatestText = accumulatedText;
        return new SelectionTransformPartial(Generation, LatestText);
    }

    public SelectionTransformCompleted? Complete(Guid generation, string finalText)
    {
        ArgumentNullException.ThrowIfNull(finalText);
        if (generation != Generation || State != SelectionTransformState.Running)
        {
            return null;
        }

        LatestText = finalText;
        State = SelectionTransformState.Completed;
        return new SelectionTransformCompleted(Generation, LatestText);
    }

    public SelectionTransformCancelled? Cancel(Guid generation)
    {
        if (generation != Generation || State != SelectionTransformState.Running)
        {
            return null;
        }

        State = string.IsNullOrWhiteSpace(LatestText)
            ? SelectionTransformState.Cancelled
            : SelectionTransformState.PartiallyCompleted;
        return new SelectionTransformCancelled(Generation, LatestText);
    }

    public SelectionTransformFailed? Fail(Guid generation, string safeMessage)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(safeMessage);
        if (generation != Generation || State != SelectionTransformState.Running)
        {
            return null;
        }

        State = SelectionTransformState.Failed;
        return new SelectionTransformFailed(Generation, safeMessage, LatestText);
    }
}
