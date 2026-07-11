using System.Collections.Concurrent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class DictationOrchestratorConcurrencyTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Concurrent_starts_open_exactly_one_live_session()
    {
        var fixture = new Fixture();

        var outcomes = await Task.WhenAll(Enumerable.Range(0, 12)
            .Select(_ => fixture.Orchestrator.StartAsync(CancellationToken.None).AsTask()));

        Assert.Equal(1, outcomes.Count(outcome => outcome == DictationStartOutcome.Started));
        Assert.Equal(11, outcomes.Count(outcome => outcome == DictationStartOutcome.AlreadyActive));
        Assert.Equal(1, fixture.Provider.CreateCalls);
        Assert.Equal(1, fixture.Audio.StartCalls);
        Assert.Equal(1, fixture.Session.StartCalls);

        await fixture.Orchestrator.CancelAsync(CancellationToken.None);
        await fixture.Orchestrator.DisposeAsync();
    }

    [Fact]
    public async Task Cancel_while_provider_start_is_blocked_returns_promptly_and_releases_session()
    {
        var fixture = new Fixture();
        fixture.Session.BlockStart = true;
        var starting = fixture.Orchestrator.StartAsync(CancellationToken.None).AsTask();
        await fixture.Session.StartEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));

        var cancelling = fixture.Orchestrator.CancelAsync(CancellationToken.None).AsTask();
        try
        {
            await cancelling.WaitAsync(TimeSpan.FromMilliseconds(250));
        }
        finally
        {
            fixture.Session.ReleaseStart();
        }

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await starting.WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.Equal(DictationPhase.Idle, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(1, fixture.Session.CancelCalls);
        Assert.Equal(1, fixture.Session.DisposeCalls);
        Assert.Equal(0, fixture.Audio.StartCalls);

        await fixture.Orchestrator.DisposeAsync();
    }

    [Fact]
    public async Task Provider_final_callback_returns_before_the_processing_pipeline_finishes()
    {
        var fixture = new Fixture();
        fixture.Processor.BlockCompletion = true;
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        var stopping = fixture.Orchestrator.StopAsync(CancellationToken.None).AsTask();
        await fixture.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));

        var callback = Task.Run(() => fixture.Session.EmitFinal("first terminal wins"));
        await callback.WaitAsync(TimeSpan.FromSeconds(2));
        await fixture.Processor.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));

        fixture.Session.EmitFailure(new VoxFlowError(VoxFlowErrorCode.ProviderFailure));
        fixture.Processor.Complete("processed once");
        await stopping.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal(DictationPhase.Completed, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(1, fixture.Processor.Calls);
        Assert.Equal(1, fixture.Output.Calls);
        Assert.Single(fixture.History.Saved);
        Assert.Equal(1, fixture.Session.DisposeCalls);
        Assert.Equal(0, fixture.Session.SubscriberCount);

        await fixture.Orchestrator.DisposeAsync();
    }

    [Fact]
    public async Task Provider_failure_while_recording_terminates_and_releases_the_session()
    {
        var fixture = new Fixture();
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        fixture.Session.EmitFailure(new VoxFlowError(VoxFlowErrorCode.ProviderFailure));
        await WaitUntilAsync(
            () => fixture.Orchestrator.Snapshot.Phase == DictationPhase.Failed,
            TimeSpan.FromSeconds(2));
        await WaitUntilAsync(
            () => fixture.Session.DisposeCalls == 1,
            TimeSpan.FromSeconds(2));

        Assert.Equal(VoxFlowErrorCode.ProviderFailure, fixture.Orchestrator.Snapshot.Error!.Code);
        Assert.Equal(1, fixture.Audio.StopCalls);
        Assert.Equal(1, fixture.Session.CancelCalls);
        Assert.Equal(0, fixture.Processor.Calls);
        Assert.Equal(0, fixture.Output.Calls);
        Assert.Empty(fixture.History.Saved);

        await fixture.Orchestrator.DisposeAsync();
    }

    [Fact]
    public async Task Audio_device_failure_while_recording_enters_explicit_failed_state()
    {
        var fixture = new Fixture();
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        fixture.Audio.EmitFailure(
            new VoxFlowError(VoxFlowErrorCode.AudioDeviceUnavailable));
        await WaitUntilAsync(
            () => fixture.Orchestrator.Snapshot.Phase == DictationPhase.Failed,
            TimeSpan.FromSeconds(2));

        Assert.Equal(
            VoxFlowErrorCode.AudioDeviceUnavailable,
            fixture.Orchestrator.Snapshot.Error!.Code);
        Assert.Equal(1, fixture.Audio.StopCalls);
        Assert.Equal(1, fixture.Session.CancelCalls);
        Assert.Equal(0, fixture.Output.Calls);
        Assert.Empty(fixture.History.Saved);

        await fixture.Orchestrator.DisposeAsync();
    }

    [Fact]
    public async Task Cancel_final_and_timeout_races_end_in_one_coherent_terminal_state()
    {
        for (var iteration = 0; iteration < 24; iteration++)
        {
            var fixture = new Fixture();
            await fixture.Orchestrator.StartAsync(CancellationToken.None);
            var stopping = fixture.Orchestrator.StopAsync(CancellationToken.None).AsTask();
            await fixture.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));

            using var startingGate = new ManualResetEventSlim();
            Task competitor;
            if (iteration % 2 == 0)
            {
                competitor = Task.Run(() =>
                {
                    startingGate.Wait();
                    fixture.Session.EmitFinal("race final");
                });
            }
            else
            {
                competitor = Task.Run(() =>
                {
                    startingGate.Wait();
                    fixture.Time.Advance(TimeSpan.FromSeconds(15));
                });
            }

            var cancelling = Task.Run(async () =>
            {
                startingGate.Wait();
                await fixture.Orchestrator.CancelAsync(CancellationToken.None);
            });
            startingGate.Set();
            await Task.WhenAll(competitor, cancelling, stopping)
                .WaitAsync(TimeSpan.FromSeconds(2));

            var snapshot = fixture.Orchestrator.Snapshot;
            Assert.Contains(
                snapshot.Phase,
                new[]
                {
                    DictationPhase.Idle,
                    DictationPhase.Completed,
                    DictationPhase.Failed,
                });

            if (snapshot.Phase == DictationPhase.Completed)
            {
                Assert.Equal(1, fixture.Output.Calls);
                Assert.Single(fixture.History.Saved);
            }
            else
            {
                Assert.Equal(0, fixture.Output.Calls);
                Assert.Empty(fixture.History.Saved);
            }

            if (snapshot.Phase == DictationPhase.Failed)
            {
                Assert.Equal(VoxFlowErrorCode.FinalTimeout, snapshot.Error!.Code);
            }

            await fixture.Orchestrator.DisposeAsync();
        }
    }

    [Fact]
    public async Task Cancel_during_processing_drops_late_progress_output_and_history()
    {
        var fixture = new Fixture();
        fixture.Processor.BlockCompletion = true;
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        var stopping = fixture.Orchestrator.StopAsync(CancellationToken.None).AsTask();
        await fixture.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        fixture.Session.EmitFinal("raw final");
        await fixture.Processor.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));

        var cancelling = fixture.Orchestrator.CancelAsync(CancellationToken.None).AsTask();
        await WaitUntilAsync(
            () => fixture.Orchestrator.Snapshot.Phase == DictationPhase.Idle,
            TimeSpan.FromSeconds(2));
        var progressCountAtCancellation = fixture.Progress.Count;

        fixture.Processor.Report("late processing text");
        fixture.Processor.Complete("late final text");

        await cancelling.WaitAsync(TimeSpan.FromSeconds(2));
        await stopping.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal(DictationPhase.Idle, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(progressCountAtCancellation, fixture.Progress.Count);
        Assert.Equal(0, fixture.Output.Calls);
        Assert.Empty(fixture.History.Saved);

        await fixture.Orchestrator.DisposeAsync();
    }

    [Fact]
    public async Task Dispose_cancels_the_active_session_unsubscribes_and_rejects_new_work()
    {
        var fixture = new Fixture();
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        await fixture.Orchestrator.DisposeAsync();
        fixture.Session.EmitPartial("late", revision: 1);
        fixture.Session.EmitFinal("late");

        Assert.Equal(DictationPhase.Idle, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(1, fixture.Audio.StopCalls);
        Assert.Equal(1, fixture.Session.CancelCalls);
        Assert.Equal(1, fixture.Session.DisposeCalls);
        Assert.Equal(0, fixture.Session.SubscriberCount);
        await Assert.ThrowsAsync<ObjectDisposedException>(
            () => fixture.Orchestrator.StartAsync(CancellationToken.None).AsTask());
    }

    private static async Task WaitUntilAsync(Func<bool> condition, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (!condition())
        {
            if (DateTime.UtcNow >= deadline)
            {
                throw new TimeoutException("The expected condition was not observed.");
            }

            await Task.Delay(10);
        }
    }

    private sealed class Fixture
    {
        public Fixture()
        {
            Provider = new FakeAsrProvider(Session);
            Orchestrator = new DictationOrchestrator(
                Provider,
                Audio,
                Processor,
                Output,
                History,
                Progress,
                Time,
                finalTimeout: TimeSpan.FromSeconds(15));
        }

        public FakeAsrSession Session { get; } = new();

        public ControlledTimeProvider Time { get; } = new(Now);

        public FakeAsrProvider Provider { get; }

        public FakeAudioCapture Audio { get; } = new();

        public FakeTextPostProcessor Processor { get; } = new();

        public FakeDictationOutput Output { get; } = new();

        public CapturingHistorySink History { get; } = new();

        public CapturingProgressSink Progress { get; } = new();

        public DictationOrchestrator Orchestrator { get; }
    }

    private sealed class FakeAsrProvider(FakeAsrSession session) : IDictationAsrProvider
    {
        private int createCalls;

        public AsrProviderAvailability Availability => AsrProviderAvailability.Ready;

        public int CreateCalls => Volatile.Read(ref createCalls);

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref createCalls);
            return ValueTask.FromResult<IDictationAsrSession>(session);
        }
    }

    private sealed class FakeAsrSession : IDictationAsrSession
    {
        private EventHandler<AsrPartialResult>? partialReceived;
        private EventHandler<AsrFinalResult>? finalReceived;
        private EventHandler<VoxFlowError>? failed;
        private int startCalls;
        private int cancelCalls;
        private int disposeCalls;
        private readonly TaskCompletionSource startCompletion = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public event EventHandler<AsrPartialResult>? PartialReceived
        {
            add => partialReceived += value;
            remove => partialReceived -= value;
        }

        public event EventHandler<AsrFinalResult>? FinalReceived
        {
            add => finalReceived += value;
            remove => finalReceived -= value;
        }

        public event EventHandler<VoxFlowError>? Failed
        {
            add => failed += value;
            remove => failed -= value;
        }

        public int StartCalls => Volatile.Read(ref startCalls);

        public int CancelCalls => Volatile.Read(ref cancelCalls);

        public int DisposeCalls => Volatile.Read(ref disposeCalls);

        public int SubscriberCount =>
            SubscriberCountOf(partialReceived)
            + SubscriberCountOf(finalReceived)
            + SubscriberCountOf(failed);

        public bool BlockStart { get; set; }

        public TaskCompletionSource StartEntered { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource FinishCalled { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public async ValueTask StartAsync(CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref startCalls);
            StartEntered.TrySetResult();
            if (BlockStart)
            {
                await startCompletion.Task.ConfigureAwait(false);
            }
        }

        public void ReleaseStart() => startCompletion.TrySetResult();

        public ValueTask PushAudioAsync(
            ReadOnlyMemory<byte> pcmS16LittleEndian,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask FinishAsync(CancellationToken cancellationToken)
        {
            FinishCalled.TrySetResult();
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref cancelCalls);
            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync()
        {
            Interlocked.Increment(ref disposeCalls);
            return ValueTask.CompletedTask;
        }

        public void EmitPartial(string text, long revision) =>
            partialReceived?.Invoke(this, new AsrPartialResult(text, revision));

        public void EmitFinal(string text) =>
            finalReceived?.Invoke(this, new AsrFinalResult(text));

        public void EmitFailure(VoxFlowError error) => failed?.Invoke(this, error);

        private static int SubscriberCountOf(Delegate? handler) =>
            handler?.GetInvocationList().Length ?? 0;
    }

    private sealed class FakeAudioCapture :
        IDictationAudioCapture,
        IDictationAudioFailureSource
    {
        private int startCalls;
        private int stopCalls;

        public int StartCalls => Volatile.Read(ref startCalls);

        public int StopCalls => Volatile.Read(ref stopCalls);

        public event EventHandler<VoxFlowError>? Failed;

        public ValueTask StartAsync(
            Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
            CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref startCalls);
            return ValueTask.CompletedTask;
        }

        public ValueTask StopAsync(CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref stopCalls);
            return ValueTask.CompletedTask;
        }

        public void EmitFailure(VoxFlowError error) => Failed?.Invoke(this, error);
    }

    private sealed class FakeTextPostProcessor : IDictationTextPostProcessor
    {
        private readonly TaskCompletionSource<string> completion = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        private IProgress<string>? progress;
        private int calls;

        public int Calls => Volatile.Read(ref calls);

        public bool BlockCompletion { get; set; }

        public TaskCompletionSource Entered { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask<string> ProcessAsync(
            string text,
            IProgress<string> streamingProgress,
            CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref calls);
            progress = streamingProgress;
            Entered.TrySetResult();

            return BlockCompletion
                ? new ValueTask<string>(completion.Task)
                : ValueTask.FromResult(text);
        }

        public void Report(string text) => progress!.Report(text);

        public void Complete(string text) => completion.TrySetResult(text);
    }

    private sealed class FakeDictationOutput : IDictationOutput
    {
        private int calls;

        public int Calls => Volatile.Read(ref calls);

        public ValueTask<OutputResult> WriteAsync(
            string text,
            CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref calls);
            return ValueTask.FromResult(new OutputResult(OutputResultKind.Inserted));
        }
    }

    private sealed class CapturingHistorySink : IDictationHistorySink
    {
        public ConcurrentQueue<DictationHistoryDraft> Saved { get; } = new();

        public ValueTask SaveAsync(
            DictationHistoryDraft draft,
            CancellationToken cancellationToken)
        {
            Saved.Enqueue(draft);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class CapturingProgressSink : IDictationProgressSink
    {
        private readonly ConcurrentQueue<DictationProgressUpdate> updates = new();

        public int Count => updates.Count;

        public void Publish(DictationProgressUpdate update) => updates.Enqueue(update);
    }
}
