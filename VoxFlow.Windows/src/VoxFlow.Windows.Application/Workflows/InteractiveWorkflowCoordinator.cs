using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Workflows;

public sealed class InteractiveWorkflowLease
{
    internal InteractiveWorkflowLease(
        Guid id,
        Guid generation,
        InteractiveWorkflowKind kind,
        CancellationTokenSource cancellation)
    {
        Id = id;
        Generation = generation;
        Kind = kind;
        CancellationToken = cancellation.Token;
        Cancellation = cancellation;
    }

    public Guid Id { get; }

    public Guid Generation { get; }

    public InteractiveWorkflowKind Kind { get; }

    public CancellationToken CancellationToken { get; }

    internal CancellationTokenSource Cancellation { get; }
}

public enum InteractiveWorkflowStartStatus
{
    Started,
    ReplacedSelection,
    InteractiveBusy,
    FileProviderBusy,
}

public sealed record InteractiveWorkflowStartResult(
    InteractiveWorkflowStartStatus Status,
    InteractiveWorkflowLease? Lease);

/// <summary>
/// Owns the single foreground-interactive workflow lease. File transcription
/// is deliberately outside this coordinator and therefore is never cancelled
/// or replaced when an interactive lease starts.
/// </summary>
public sealed class InteractiveWorkflowCoordinator
{
    private readonly object stateGate = new();
    private InteractiveWorkflowLease? current;
    private Guid lastGeneration;
    private bool selectionReplacementInProgress;

    public InteractiveWorkflowLease? TryAcquire(InteractiveWorkflowKind kind)
    {
        if (!Enum.IsDefined(kind))
        {
            throw new ArgumentOutOfRangeException(nameof(kind), kind, null);
        }

        lock (stateGate)
        {
            if (current is not null || selectionReplacementInProgress)
            {
                return null;
            }
            current = CreateLeaseUnsafe(kind);
            return current;
        }
    }

    public InteractiveWorkflowStartResult StartOrReplaceSelection(
        InteractiveWorkflowKind kind,
        bool providerAllowsFileConcurrency,
        Action<InteractiveWorkflowLease> persistCancelledPartial)
    {
        if (kind is not (InteractiveWorkflowKind.SelectionTranslation
            or InteractiveWorkflowKind.SelectionSummary))
        {
            throw new ArgumentOutOfRangeException(nameof(kind), kind, null);
        }
        ArgumentNullException.ThrowIfNull(persistCancelledPartial);

        InteractiveWorkflowLease? replaced = null;
        lock (stateGate)
        {
            if (selectionReplacementInProgress
                || current is { Kind: InteractiveWorkflowKind.Dictation
                    or InteractiveWorkflowKind.AgentCompose })
            {
                return new InteractiveWorkflowStartResult(
                    InteractiveWorkflowStartStatus.InteractiveBusy,
                    Lease: null);
            }
            if (!providerAllowsFileConcurrency)
            {
                return new InteractiveWorkflowStartResult(
                    InteractiveWorkflowStartStatus.FileProviderBusy,
                    Lease: null);
            }
            if (current is null)
            {
                current = CreateLeaseUnsafe(kind);
                return new InteractiveWorkflowStartResult(
                    InteractiveWorkflowStartStatus.Started,
                    current);
            }

            replaced = current;
            current = null;
            selectionReplacementInProgress = true;
        }

        var replacedLease = replaced
            ?? throw new InvalidOperationException(
                "A selection replacement requires the previous lease.");
        try
        {
            replacedLease.Cancellation.Cancel();
            persistCancelledPartial(replacedLease);
        }
        catch
        {
            lock (stateGate)
            {
                selectionReplacementInProgress = false;
            }
            throw;
        }

        lock (stateGate)
        {
            current = CreateLeaseUnsafe(kind);
            selectionReplacementInProgress = false;
            return new InteractiveWorkflowStartResult(
                InteractiveWorkflowStartStatus.ReplacedSelection,
                current);
        }
    }

    public bool IsCurrent(InteractiveWorkflowLease lease)
    {
        ArgumentNullException.ThrowIfNull(lease);
        lock (stateGate)
        {
            return IsCurrentUnsafe(lease);
        }
    }

    public bool TryApply(InteractiveWorkflowLease lease, Action mutation)
    {
        ArgumentNullException.ThrowIfNull(lease);
        ArgumentNullException.ThrowIfNull(mutation);
        lock (stateGate)
        {
            if (!IsCurrentUnsafe(lease))
            {
                return false;
            }

            mutation();
            return true;
        }
    }

    public bool Cancel(InteractiveWorkflowLease lease) => End(lease, cancel: true);

    public bool Complete(InteractiveWorkflowLease lease) => End(lease, cancel: false);

    private bool End(InteractiveWorkflowLease lease, bool cancel)
    {
        ArgumentNullException.ThrowIfNull(lease);
        CancellationTokenSource? cancellation = null;
        lock (stateGate)
        {
            if (!IsCurrentUnsafe(lease))
            {
                return false;
            }

            current = null;
            if (cancel)
            {
                cancellation = lease.Cancellation;
            }
        }

        cancellation?.Cancel();
        return true;
    }

    private bool IsCurrentUnsafe(InteractiveWorkflowLease lease) =>
        ReferenceEquals(current, lease)
        && !lease.CancellationToken.IsCancellationRequested;

    private InteractiveWorkflowLease CreateLeaseUnsafe(
        InteractiveWorkflowKind kind)
    {
        Guid generation;
        do
        {
            generation = Guid.NewGuid();
        }
        while (generation == Guid.Empty || generation == lastGeneration);

        Guid id;
        do
        {
            id = Guid.NewGuid();
        }
        while (id == Guid.Empty || id == generation);

        lastGeneration = generation;
        return new InteractiveWorkflowLease(
            id,
            generation,
            kind,
            new CancellationTokenSource());
    }
}
