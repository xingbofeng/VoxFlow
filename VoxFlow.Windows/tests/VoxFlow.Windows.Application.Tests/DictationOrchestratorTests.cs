using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class DictationOrchestratorTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(AsrProviderAvailability.Unconfigured, DictationStartOutcome.NeedsConfiguration)]
    [InlineData(AsrProviderAvailability.NotReady, DictationStartOutcome.ProviderNotReady)]
    public async Task Start_guides_unavailable_provider_without_opening_audio(
        AsrProviderAvailability availability,
        DictationStartOutcome expected)
    {
        var fixture = new Fixture(availability);

        var outcome = await fixture.Orchestrator.StartAsync(CancellationToken.None);

        Assert.Equal(expected, outcome);
        Assert.Equal(DictationPhase.Idle, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(0, fixture.Audio.StartCalls);
        Assert.Equal(0, fixture.Output.TargetCaptureCalls);
        Assert.Equal(
            availability == AsrProviderAvailability.Unconfigured
                ? DictationGuidance.ConfigureAsr
                : DictationGuidance.PrepareSelectedProvider,
            fixture.Progress.Last.Guidance);
    }

    [Fact]
    public async Task Ready_start_captures_original_foreground_target_before_recording()
    {
        var fixture = new Fixture(AsrProviderAvailability.Ready);

        var outcome = await fixture.Orchestrator.StartAsync(CancellationToken.None);

        Assert.Equal(DictationStartOutcome.Started, outcome);
        Assert.Equal(1, fixture.Output.TargetCaptureCalls);
    }

    [Fact]
    public async Task Explicit_target_capture_is_used_when_post_processor_needs_a_frozen_target()
    {
        var targetCapture = new FakeTargetCapture();
        var fixture = new Fixture(AsrProviderAvailability.Ready, targetCapture: targetCapture);

        var outcome = await fixture.Orchestrator.StartAsync(CancellationToken.None);

        Assert.Equal(DictationStartOutcome.Started, outcome);
        Assert.Equal(1, targetCapture.Calls);
        Assert.Equal(0, fixture.Output.TargetCaptureCalls);
    }

    [Fact]
    public async Task Agent_style_processor_failure_never_falls_back_to_foreground_output()
    {
        var fixture = new Fixture(
            AsrProviderAvailability.Ready,
            processor: new NoFallbackThrowingProcessor());
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        var stopping = fixture.Orchestrator.StopAsync(CancellationToken.None).AsTask();
        await fixture.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        fixture.Session.EmitFinal("do not inject this instruction");
        await stopping;

        Assert.Equal(DictationPhase.Failed, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(0, fixture.Output.Calls);
        Assert.Empty(fixture.History.Saved);
    }

    [Fact]
    public async Task Recording_partial_final_processing_injection_and_history_complete_once()
    {
        var fixture = new Fixture(AsrProviderAvailability.Ready);
        fixture.Processor.Result = "conservative corrected text";
        fixture.Output.Result = new OutputResult(OutputResultKind.Inserted);

        Assert.Equal(
            DictationStartOutcome.Started,
            await fixture.Orchestrator.StartAsync(CancellationToken.None));
        Assert.Equal(DictationPhase.Recording, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(1, fixture.Audio.StartCalls);
        Assert.Equal(1, fixture.Session.StartCalls);

        fixture.Session.EmitPartial("partial words", revision: 1);
        Assert.Equal("partial words", fixture.Progress.Last.PartialText);

        var stopping = fixture.Orchestrator.StopAsync(CancellationToken.None).AsTask();
        await fixture.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Equal(DictationPhase.WaitingForFinal, fixture.Orchestrator.Snapshot.Phase);
        fixture.Session.EmitFinal("authoritative ASR text");

        await stopping;

        Assert.Equal(DictationPhase.Completed, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal("authoritative ASR text", fixture.Processor.LastInput);
        Assert.Equal("conservative corrected text", fixture.Output.LastText);
        Assert.Equal("streaming correction", fixture.Progress.Updates
            .Last(update => update.ProcessingText is not null).ProcessingText);
        var saved = Assert.Single(fixture.History.Saved);
        Assert.Equal("authoritative ASR text", saved.RawText);
        Assert.Equal("conservative corrected text", saved.FinalText);
        Assert.Equal(OutputResultKind.Inserted, saved.Output.Kind);
        Assert.Equal(
            [
                DictationPhase.Preparing,
                DictationPhase.Recording,
                DictationPhase.WaitingForFinal,
                DictationPhase.Processing,
                DictationPhase.Injecting,
                DictationPhase.Completed,
            ],
            fixture.Progress.Updates
                .Where(update => update.Snapshot is not null)
                .Select(update => update.Snapshot!.Phase)
                .Distinct());
    }

    [Fact]
    public async Task Cancel_stops_audio_and_session_then_drops_late_provider_callbacks()
    {
        var fixture = new Fixture(AsrProviderAvailability.Ready);
        await fixture.Orchestrator.StartAsync(CancellationToken.None);
        fixture.Session.EmitPartial("must disappear", revision: 1);

        await fixture.Orchestrator.CancelAsync(CancellationToken.None);
        fixture.Session.EmitFinal("late final");
        fixture.Session.EmitFailure(new VoxFlowError(VoxFlowErrorCode.ProviderFailure));

        Assert.Equal(DictationPhase.Idle, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(1, fixture.Audio.StopCalls);
        Assert.Equal(1, fixture.Session.CancelCalls);
        Assert.Equal(0, fixture.Processor.Calls);
        Assert.Equal(0, fixture.Output.Calls);
        Assert.Empty(fixture.History.Saved);
        Assert.Null(fixture.Progress.Last.PartialText);
    }

    [Fact]
    public async Task Missing_final_fails_after_the_controlled_timeout_without_output()
    {
        var fixture = new Fixture(AsrProviderAvailability.Ready);
        await fixture.Orchestrator.StartAsync(CancellationToken.None);

        var stopping = fixture.Orchestrator.StopAsync(CancellationToken.None).AsTask();
        await fixture.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        fixture.Time.Advance(TimeSpan.FromSeconds(15));
        await stopping;

        Assert.Equal(DictationPhase.Failed, fixture.Orchestrator.Snapshot.Phase);
        Assert.Equal(VoxFlowErrorCode.FinalTimeout, fixture.Orchestrator.Snapshot.Error!.Code);
        Assert.Equal(0, fixture.Processor.Calls);
        Assert.Equal(0, fixture.Output.Calls);
        Assert.Empty(fixture.History.Saved);
    }

    private sealed class Fixture
    {
        public Fixture(
            AsrProviderAvailability availability,
            IDictationTextPostProcessor? processor = null,
            IDictationTargetCapture? targetCapture = null)
        {
            Provider = new FakeAsrProvider(availability, Session);
            Processor = processor as FakeTextPostProcessor ?? new FakeTextPostProcessor();
            Orchestrator = new DictationOrchestrator(
                Provider,
                Audio,
                processor ?? Processor,
                Output,
                History,
                Progress,
                Time,
                finalTimeout: TimeSpan.FromSeconds(15),
                targetCapture: targetCapture);
        }

        public ControlledTimeProvider Time { get; } = new(Now);

        public FakeAsrSession Session { get; } = new();

        public FakeAsrProvider Provider { get; }

        public FakeAudioCapture Audio { get; } = new();

        public FakeTextPostProcessor Processor { get; }

        public FakeDictationOutput Output { get; } = new();

        public CapturingHistorySink History { get; } = new();

        public CapturingProgressSink Progress { get; } = new();

        public DictationOrchestrator Orchestrator { get; }
    }

    private sealed class FakeAsrProvider(
        AsrProviderAvailability availability,
        FakeAsrSession session) : IDictationAsrProvider
    {
        public AsrProviderAvailability Availability => availability;

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult<IDictationAsrSession>(session);
    }

    private sealed class FakeAsrSession : IDictationAsrSession
    {
        public event EventHandler<AsrPartialResult>? PartialReceived;

        public event EventHandler<AsrFinalResult>? FinalReceived;

        public event EventHandler<VoxFlowError>? Failed;

        public int StartCalls { get; private set; }

        public int FinishCalls { get; private set; }

        public int CancelCalls { get; private set; }

        public TaskCompletionSource FinishCalled { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask StartAsync(CancellationToken cancellationToken)
        {
            StartCalls++;
            return ValueTask.CompletedTask;
        }

        public ValueTask PushAudioAsync(
            ReadOnlyMemory<byte> pcmS16LittleEndian,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask FinishAsync(CancellationToken cancellationToken)
        {
            FinishCalls++;
            FinishCalled.TrySetResult();
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken)
        {
            CancelCalls++;
            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        public void EmitPartial(string text, long revision) =>
            PartialReceived?.Invoke(this, new AsrPartialResult(text, revision));

        public void EmitFinal(string text) =>
            FinalReceived?.Invoke(this, new AsrFinalResult(text));

        public void EmitFailure(VoxFlowError error) => Failed?.Invoke(this, error);
    }

    private sealed class FakeAudioCapture : IDictationAudioCapture
    {
        public int StartCalls { get; private set; }

        public int StopCalls { get; private set; }

        public ValueTask StartAsync(
            Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
            CancellationToken cancellationToken)
        {
            StartCalls++;
            return ValueTask.CompletedTask;
        }

        public ValueTask StopAsync(CancellationToken cancellationToken)
        {
            StopCalls++;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeTextPostProcessor : IDictationTextPostProcessor
    {
        public int Calls { get; private set; }

        public string? LastInput { get; private set; }

        public string Result { get; set; } = string.Empty;

        public ValueTask<string> ProcessAsync(
            string text,
            IProgress<string> streamingProgress,
            CancellationToken cancellationToken)
        {
            Calls++;
            LastInput = text;
            streamingProgress.Report("streaming correction");
            return ValueTask.FromResult(Result);
        }
    }

    private sealed class NoFallbackThrowingProcessor : IDictationTextPostProcessor,
        IDictationTextPostProcessorFailurePolicy
    {
        public bool UseAuthoritativeTextOnFailure => false;

        public ValueTask<string> ProcessAsync(
            string text,
            IProgress<string> streamingProgress,
            CancellationToken cancellationToken) =>
            ValueTask.FromException<string>(new InvalidOperationException("sidecar failed"));
    }

    private sealed class FakeTargetCapture : IDictationTargetCapture
    {
        public int Calls { get; private set; }

        public void CaptureOriginalTarget() => Calls++;
    }

    private sealed class FakeDictationOutput : IDictationOutput, IDictationTargetCapture
    {
        public int Calls { get; private set; }

        public int TargetCaptureCalls { get; private set; }

        public string? LastText { get; private set; }

        public OutputResult Result { get; set; } = new(OutputResultKind.Inserted);

        public void CaptureOriginalTarget() => TargetCaptureCalls++;

        public ValueTask<OutputResult> WriteAsync(
            string text,
            CancellationToken cancellationToken)
        {
            Calls++;
            LastText = text;
            return ValueTask.FromResult(Result);
        }
    }

    private sealed class CapturingHistorySink : IDictationHistorySink
    {
        public List<DictationHistoryDraft> Saved { get; } = [];

        public ValueTask SaveAsync(
            DictationHistoryDraft draft,
            CancellationToken cancellationToken)
        {
            Saved.Add(draft);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class CapturingProgressSink : IDictationProgressSink
    {
        public List<DictationProgressUpdate> Updates { get; } = [];

        public DictationProgressUpdate Last => Updates[^1];

        public void Publish(DictationProgressUpdate update) => Updates.Add(update);
    }
}
