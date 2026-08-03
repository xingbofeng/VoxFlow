using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen;

namespace VoxFlow.Windows.Providers.Qwen.Tests;

public sealed class QwenAsrProviderTests
{
    [Fact]
    public async Task Not_ready_model_cannot_start_a_native_session()
    {
        var factory = new FakeAttemptFactory();
        var provider = new QwenAsrProvider(
            QwenVariant.Qwen06B,
            new FixedReadiness(false),
            factory);

        Assert.Equal(AsrProviderAvailability.NotReady, provider.Availability);
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => provider.CreateSessionAsync(Guid.NewGuid(), CancellationToken.None).AsTask());
        Assert.Equal(0, factory.CreateCount);
    }

    [Fact]
    public async Task Higher_partial_revisions_replace_preview_and_only_one_authoritative_final_is_published()
    {
        var attempt = new FakeAttempt();
        var factory = new FakeAttemptFactory(attempt);
        var provider = new QwenAsrProvider(QwenVariant.Qwen06B, new FixedReadiness(true), factory);
        await using IDictationAsrSession session = await provider.CreateSessionAsync(Guid.NewGuid(), CancellationToken.None);
        var partials = new List<AsrPartialResult>();
        var finals = new List<string>();
        session.PartialReceived += (_, value) => partials.Add(value);
        session.FinalReceived += (_, value) => finals.Add(value.Text);

        await session.StartAsync(CancellationToken.None);
        attempt.EmitPartial("你", 1);
        attempt.EmitPartial("你好", 2);
        attempt.EmitPartial("stale", 1);
        attempt.EmitFinal("你好");
        attempt.EmitFinal("duplicate");

        Assert.Equal(["你", "你好"], partials.Select(value => value.Text));
        Assert.Equal([1L, 2L], partials.Select(value => value.Revision));
        Assert.Equal(["你好"], finals);
    }

    [Fact]
    public async Task Empty_final_is_a_failure_and_is_never_published_as_output()
    {
        var attempt = new FakeAttempt();
        var provider = new QwenAsrProvider(
            QwenVariant.Qwen17B,
            new FixedReadiness(true),
            new FakeAttemptFactory(attempt));
        await using IDictationAsrSession session = await provider.CreateSessionAsync(Guid.NewGuid(), CancellationToken.None);
        var failure = new TaskCompletionSource<VoxFlowError>(TaskCreationOptions.RunContinuationsAsynchronously);
        int finals = 0;
        session.FinalReceived += (_, _) => finals++;
        session.Failed += (_, error) => failure.TrySetResult(error);

        await session.StartAsync(CancellationToken.None);
        attempt.EmitFinal("  ");

        Assert.Equal(VoxFlowErrorCode.EmptyFinal, (await failure.Task.WaitAsync(TimeSpan.FromSeconds(1))).Code);
        Assert.Equal(0, finals);
    }

    [Fact]
    public async Task One_recoverable_native_failure_rewarms_replays_audio_and_retries_finish_once()
    {
        var first = new FakeAttempt();
        var second = new FakeAttempt();
        var factory = new FakeAttemptFactory(first, second);
        var provider = new QwenAsrProvider(QwenVariant.Qwen06B, new FixedReadiness(true), factory);
        await using IDictationAsrSession session = await provider.CreateSessionAsync(Guid.NewGuid(), CancellationToken.None);
        var final = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, value) => final.TrySetResult(value.Text);

        await session.StartAsync(CancellationToken.None);
        await session.PushAudioAsync(new byte[] { 1, 0, 2, 0 }, CancellationToken.None);
        await session.FinishAsync(CancellationToken.None);
        first.EmitFailure(new VoxFlowError(VoxFlowErrorCode.NativeRuntimeFailure, AsrProviderId.Qwen));

        await second.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        second.EmitFinal("recovered");

        Assert.Equal("recovered", await final.Task.WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.Equal(1, factory.PrewarmCount);
        Assert.Equal(2, factory.CreateCount);
        Assert.Equal(new byte[] { 1, 0, 2, 0 }, Assert.Single(second.AudioFrames));
        Assert.Equal(1, second.FinishCount);
    }

    [Fact]
    public async Task Second_recoverable_failure_stops_without_switching_provider_or_model()
    {
        var first = new FakeAttempt();
        var second = new FakeAttempt();
        var factory = new FakeAttemptFactory(first, second);
        var provider = new QwenAsrProvider(QwenVariant.Qwen17B, new FixedReadiness(true), factory);
        await using IDictationAsrSession session = await provider.CreateSessionAsync(Guid.NewGuid(), CancellationToken.None);
        var failure = new TaskCompletionSource<VoxFlowError>(TaskCreationOptions.RunContinuationsAsynchronously);
        session.Failed += (_, value) => failure.TrySetResult(value);

        await session.StartAsync(CancellationToken.None);
        first.EmitFailure(new VoxFlowError(VoxFlowErrorCode.NativeRuntimeFailure, AsrProviderId.Qwen));
        await second.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        second.EmitFailure(new VoxFlowError(VoxFlowErrorCode.NativeRuntimeFailure, AsrProviderId.Qwen));

        Assert.Equal(VoxFlowErrorCode.NativeRuntimeFailure, (await failure.Task.WaitAsync(TimeSpan.FromSeconds(2))).Code);
        Assert.Equal(2, factory.CreateCount);
        Assert.Equal([QwenVariant.Qwen17B, QwenVariant.Qwen17B], factory.RequestedVariants);
    }

    [Fact]
    public async Task Cancellation_discards_late_partial_final_and_failure_events()
    {
        var attempt = new FakeAttempt();
        var provider = new QwenAsrProvider(
            QwenVariant.Qwen06B,
            new FixedReadiness(true),
            new FakeAttemptFactory(attempt));
        await using IDictationAsrSession session = await provider.CreateSessionAsync(Guid.NewGuid(), CancellationToken.None);
        int published = 0;
        session.PartialReceived += (_, _) => published++;
        session.FinalReceived += (_, _) => published++;
        session.Failed += (_, _) => published++;

        await session.StartAsync(CancellationToken.None);
        await session.CancelAsync(CancellationToken.None);
        attempt.EmitPartial("late", 1);
        attempt.EmitFinal("late");
        attempt.EmitFailure(new VoxFlowError(VoxFlowErrorCode.NativeRuntimeFailure, AsrProviderId.Qwen));
        await Task.Delay(50);

        Assert.Equal(1, attempt.CancelCount);
        Assert.Equal(0, published);
    }

    private sealed record FixedReadiness(bool IsReady) : IQwenProviderReadiness
    {
        public bool IsReadyFor(QwenVariant variant) => IsReady;
    }

    private sealed class FakeAttemptFactory : IQwenSessionAttemptFactory
    {
        private readonly Queue<FakeAttempt> attempts;

        public FakeAttemptFactory(params FakeAttempt[] attempts)
        {
            this.attempts = new Queue<FakeAttempt>(attempts);
        }

        public int CreateCount { get; private set; }

        public int PrewarmCount { get; private set; }

        public List<QwenVariant> RequestedVariants { get; } = [];

        public ValueTask PrewarmAsync(QwenVariant variant, CancellationToken cancellationToken)
        {
            PrewarmCount++;
            return ValueTask.CompletedTask;
        }

        public ValueTask<IDictationAsrSession> CreateAsync(
            QwenVariant variant,
            Guid generation,
            CancellationToken cancellationToken)
        {
            CreateCount++;
            RequestedVariants.Add(variant);
            if (attempts.Count == 0)
            {
                throw new InvalidOperationException("No fake attempt remains.");
            }

            return ValueTask.FromResult<IDictationAsrSession>(attempts.Dequeue());
        }
    }

    private sealed class FakeAttempt : IDictationAsrSession
    {
        public event EventHandler<AsrPartialResult>? PartialReceived;

        public event EventHandler<AsrFinalResult>? FinalReceived;

        public event EventHandler<VoxFlowError>? Failed;

        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public List<byte[]> AudioFrames { get; } = [];

        public int FinishCount { get; private set; }

        public int CancelCount { get; private set; }

        public ValueTask StartAsync(CancellationToken cancellationToken)
        {
            Started.TrySetResult();
            return ValueTask.CompletedTask;
        }

        public ValueTask PushAudioAsync(ReadOnlyMemory<byte> pcmS16LittleEndian, CancellationToken cancellationToken)
        {
            AudioFrames.Add(pcmS16LittleEndian.ToArray());
            return ValueTask.CompletedTask;
        }

        public ValueTask FinishAsync(CancellationToken cancellationToken)
        {
            FinishCount++;
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken)
        {
            CancelCount++;
            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        public void EmitPartial(string text, long revision) =>
            PartialReceived?.Invoke(this, new AsrPartialResult(text, revision));

        public void EmitFinal(string text) =>
            FinalReceived?.Invoke(this, new AsrFinalResult(text));

        public void EmitFailure(VoxFlowError error) =>
            Failed?.Invoke(this, error);
    }
}
