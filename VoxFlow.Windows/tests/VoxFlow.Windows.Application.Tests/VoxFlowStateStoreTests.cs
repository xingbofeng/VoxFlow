using System.Collections.Concurrent;
using VoxFlow.Windows.Application.State;

namespace VoxFlow.Windows.Application.Tests;

public sealed class VoxFlowStateStoreTests
{
    [Fact]
    public void Initial_snapshot_is_version_zero_with_domain_defaults()
    {
        var store = new VoxFlowStateStore();

        Assert.Equal(0, store.Current.Version);
        Assert.Equal(VoxFlowState.Default, store.Current.State);
        Assert.False(typeof(VoxFlowState).GetProperty(nameof(VoxFlowState.Settings))!.CanWrite);
        Assert.Throws<ArgumentNullException>(() =>
            VoxFlowState.Default.WithSettings(null!));
    }

    [Fact]
    public void Real_commands_advance_once_and_no_op_or_failure_does_not_advance()
    {
        var store = new VoxFlowStateStore();

        var first = store.Dispatch(new SetSettingCommand("theme", "dark"));
        var second = store.Dispatch(new SetSettingCommand("theme", "light"));
        var unchanged = store.Dispatch(new SetSettingCommand("theme", "light"));

        Assert.Equal(1, first.Version);
        Assert.Equal(2, second.Version);
        Assert.Equal(second, unchanged);
        Assert.Throws<InvalidOperationException>(() =>
            store.Dispatch(new ThrowingCommand()));
        Assert.Equal(second, store.Current);
    }

    [Fact]
    public void Concurrent_commands_are_serialized_without_lost_updates()
    {
        var store = new VoxFlowStateStore();
        ConcurrentQueue<long> observedVersions = [];
        using var subscription = store.Subscribe(
            change => observedVersions.Enqueue(change.Snapshot.Version),
            replayCurrent: false);

        Parallel.For(0, 100, _ =>
            store.Dispatch(new IncrementSettingCommand("count")));

        Assert.Equal("100", store.Current.State.Settings["count"]);
        Assert.Equal(100, store.Current.Version);
        Assert.Equal(
            Enumerable.Range(1, 100).Select(value => (long)value),
            observedVersions);
    }

    [Fact]
    public void Every_subscriber_receives_the_same_published_snapshot_sequence()
    {
        var store = new VoxFlowStateStore();
        List<StateChanged> first = [];
        List<StateChanged> second = [];
        using var firstSubscription = store.Subscribe(first.Add, replayCurrent: false);
        using var secondSubscription = store.Subscribe(second.Add, replayCurrent: false);

        store.Dispatch(new SetSettingCommand("theme", "dark"));
        store.Dispatch(new SetSettingCommand("language", "zh-CN"));

        Assert.Equal(first, second);
        Assert.Equal([1L, 2L], first.Select(change => change.Snapshot.Version));
        Assert.Same(first[0], second[0]);
        Assert.Same(first[1], second[1]);
    }

    [Fact]
    public void Replay_is_current_and_disposal_stops_future_delivery()
    {
        var store = new VoxFlowStateStore();
        store.Dispatch(new SetSettingCommand("theme", "dark"));
        List<StateChanged> observed = [];

        var subscription = store.Subscribe(observed.Add);

        Assert.Single(observed);
        Assert.Equal(store.Current, observed[0].Snapshot);
        Assert.Equal(StateChangeKind.All, observed[0].Changes);

        subscription.Dispose();
        store.Dispatch(new SetSettingCommand("theme", "light"));

        Assert.Single(observed);
    }

    [Fact]
    public void One_failing_observer_does_not_block_other_observers_or_dispatch()
    {
        var store = new VoxFlowStateStore();
        List<StateChanged> healthy = [];
        using var failingSubscription = store.Subscribe(
            _ => throw new InvalidOperationException("observer failure"),
            replayCurrent: false);
        using var healthySubscription = store.Subscribe(healthy.Add, replayCurrent: false);

        var snapshot = store.Dispatch(new SetSettingCommand("theme", "dark"));

        Assert.Equal(1, snapshot.Version);
        Assert.Single(healthy);
        Assert.Equal(snapshot, healthy[0].Snapshot);
    }

    [Fact]
    public void Observer_can_wait_for_cross_thread_dispatch_without_deadlocking_publication()
    {
        var store = new VoxFlowStateStore();
        var nestedCompletedInsideObserver = false;
        Task<VoxFlowStateSnapshot>? nestedDispatch = null;
        List<long> versions = [];
        using var subscription = store.Subscribe(
            change =>
            {
                versions.Add(change.Snapshot.Version);
                if (change.Snapshot.Version == 1)
                {
                    nestedDispatch = Task.Run(() =>
                        store.Dispatch(new SetSettingCommand("language", "zh-CN")));
                    nestedCompletedInsideObserver = nestedDispatch.Wait(TimeSpan.FromSeconds(1));
                }
            },
            replayCurrent: false);

        var committed = store.Dispatch(new SetSettingCommand("theme", "dark"));

        Assert.True(nestedCompletedInsideObserver);
        Assert.NotNull(nestedDispatch);
        Assert.True(nestedDispatch.IsCompletedSuccessfully);
        Assert.Equal(1, committed.Version);
        Assert.Equal(2, store.Current.Version);
        Assert.Equal("zh-CN", store.Current.State.Settings["language"]);
        Assert.Equal([1L, 2L], versions);
    }

    [Fact]
    public void Command_reducer_can_wait_for_cross_thread_dispatch_without_an_internal_lock_cycle()
    {
        var store = new VoxFlowStateStore();
        var command = new CrossThreadDispatchingCommand(store);

        var snapshot = store.Dispatch(command);

        Assert.True(command.NestedCompletedWhileApplying);
        Assert.Equal(2, snapshot.Version);
        Assert.Equal("ready", snapshot.State.Settings["nested"]);
        Assert.Equal("ready", snapshot.State.Settings["outer"]);
    }

    private sealed record SetSettingCommand(string Key, string Value) : IVoxFlowStateCommand
    {
        public StateMutation Apply(VoxFlowState state)
        {
            if (state.Settings.TryGetValue(Key, out var current) && current == Value)
            {
                return new StateMutation(state, StateChangeKind.None);
            }

            return new StateMutation(
                state.WithSettings(state.Settings.SetItem(Key, Value)),
                StateChangeKind.Settings);
        }
    }

    private sealed record IncrementSettingCommand(string Key) : IVoxFlowStateCommand
    {
        public StateMutation Apply(VoxFlowState state)
        {
            var current = state.Settings.TryGetValue(Key, out var value)
                ? int.Parse(value, System.Globalization.CultureInfo.InvariantCulture)
                : 0;

            return new StateMutation(
                state.WithSettings(state.Settings.SetItem(
                    Key,
                    (current + 1).ToString(
                        System.Globalization.CultureInfo.InvariantCulture))),
                StateChangeKind.Settings);
        }
    }

    private sealed class ThrowingCommand : IVoxFlowStateCommand
    {
        public StateMutation Apply(VoxFlowState state) =>
            throw new InvalidOperationException("command failure");
    }

    private sealed class CrossThreadDispatchingCommand(VoxFlowStateStore store)
        : IVoxFlowStateCommand
    {
        private int nestedStarted;

        public bool NestedCompletedWhileApplying { get; private set; }

        public StateMutation Apply(VoxFlowState state)
        {
            if (Interlocked.Exchange(ref nestedStarted, 1) == 0)
            {
                var nested = Task.Run(() =>
                    store.Dispatch(new SetSettingCommand("nested", "ready")));
                NestedCompletedWhileApplying = nested.Wait(TimeSpan.FromSeconds(1));
            }

            return new StateMutation(
                state.WithSettings(state.Settings.SetItem("outer", "ready")),
                StateChangeKind.Settings);
        }
    }
}
