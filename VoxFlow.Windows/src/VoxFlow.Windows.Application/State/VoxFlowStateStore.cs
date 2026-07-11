namespace VoxFlow.Windows.Application.State;

/// <summary>
/// The single writable application state source. Reducers execute without a
/// store mutex; commits use optimistic serialization, and observer callbacks
/// drain from an ordered queue outside all internal locks.
/// </summary>
public sealed class VoxFlowStateStore
{
    private readonly object stateGate = new();
    private readonly Dictionary<long, Subscriber> subscribers = [];
    private readonly Queue<Publication> pendingPublications = [];
    private VoxFlowStateSnapshot current = new(0, VoxFlowState.Default);
    private bool publicationDraining;
    private long nextSubscriberId;

    public VoxFlowStateSnapshot Current
    {
        get
        {
            lock (stateGate)
            {
                return current;
            }
        }
    }

    public VoxFlowStateSnapshot Dispatch(IVoxFlowStateCommand command)
    {
        ArgumentNullException.ThrowIfNull(command);

        while (true)
        {
            VoxFlowStateSnapshot before;
            lock (stateGate)
            {
                before = current;
            }

            // Reducers are pure and may be retried. They deliberately execute
            // outside stateGate so UI or provider coordination cannot form a
            // lock cycle with another dispatch.
            var mutation = command.Apply(before.State)
                ?? throw new InvalidOperationException(
                    "A state command returned no mutation.");
            ValidateMutation(before.State, mutation);

            var shouldDrain = false;
            VoxFlowStateSnapshot committed;

            lock (stateGate)
            {
                if (current.Version != before.Version)
                {
                    continue;
                }

                if (mutation.Changes == StateChangeKind.None
                    || Equals(mutation.State, before.State))
                {
                    return before;
                }

                committed = new VoxFlowStateSnapshot(
                    checked(before.Version + 1),
                    mutation.State);
                current = committed;

                var change = new StateChanged(committed, mutation.Changes);
                pendingPublications.Enqueue(new Publication(
                    change,
                    [.. subscribers.Values]));

                if (!publicationDraining)
                {
                    publicationDraining = true;
                    shouldDrain = true;
                }
            }

            if (shouldDrain)
            {
                DrainPublications();
            }

            return committed;
        }
    }

    public IDisposable Subscribe(
        Action<StateChanged> observer,
        bool replayCurrent = true)
    {
        ArgumentNullException.ThrowIfNull(observer);

        Subscriber subscriber;
        var shouldDrain = false;

        lock (stateGate)
        {
            var subscriberId = checked(++nextSubscriberId);
            subscriber = new Subscriber(this, subscriberId, observer);
            subscribers.Add(subscriberId, subscriber);

            if (replayCurrent)
            {
                pendingPublications.Enqueue(new Publication(
                    new StateChanged(current, StateChangeKind.All),
                    [subscriber]));

                if (!publicationDraining)
                {
                    publicationDraining = true;
                    shouldDrain = true;
                }
            }
        }

        if (shouldDrain)
        {
            DrainPublications();
        }

        return subscriber;
    }

    private static void ValidateMutation(
        VoxFlowState before,
        StateMutation mutation)
    {
        if (mutation.State is null)
        {
            throw new InvalidOperationException(
                "A state command returned a mutation without state.");
        }

        if ((mutation.Changes & ~StateChangeKind.All) != StateChangeKind.None)
        {
            throw new InvalidOperationException(
                $"A state mutation contains unsupported change flags: {mutation.Changes}.");
        }

        if (mutation.Changes == StateChangeKind.None
            && !Equals(mutation.State, before))
        {
            throw new InvalidOperationException(
                "A state-changing mutation must identify at least one change category.");
        }
    }

    private void DrainPublications()
    {
        while (true)
        {
            Publication publication;

            lock (stateGate)
            {
                if (!pendingPublications.TryDequeue(out publication!))
                {
                    publicationDraining = false;
                    return;
                }
            }

            foreach (var subscriber in publication.Subscribers)
            {
                subscriber.Notify(publication.Change);
            }
        }
    }

    private void Unsubscribe(long subscriberId)
    {
        lock (stateGate)
        {
            subscribers.Remove(subscriberId);
        }
    }

    private sealed record Publication(
        StateChanged Change,
        Subscriber[] Subscribers);

    private sealed class Subscriber(
        VoxFlowStateStore owner,
        long subscriberId,
        Action<StateChanged> observer) : IDisposable
    {
        private VoxFlowStateStore? owner = owner;

        public void Notify(StateChanged change)
        {
            if (Volatile.Read(ref owner) is null)
            {
                return;
            }

            try
            {
                observer(change);
            }
            catch (Exception)
            {
                // A projection cannot roll back committed state or prevent
                // later projections from receiving the same snapshot.
            }
        }

        public void Dispose()
        {
            Interlocked.Exchange(ref owner, null)?.Unsubscribe(subscriberId);
        }
    }
}
