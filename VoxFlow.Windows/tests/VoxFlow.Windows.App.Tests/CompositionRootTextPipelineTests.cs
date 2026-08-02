using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class CompositionRootTextPipelineTests
{
    [Fact]
    public async Task App_composition_injects_the_configurable_conservative_pipeline_into_dictation()
    {
        using var directory = new TemporaryDirectory();
        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);
        dynamic root = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "voxflow.db"),
            new DisabledRefiner())!);
        using ((IDisposable)root)
        {
            await ((ITextProcessingSettingsStore)root.TextSettingsStore).SaveAsync(
                DeterministicTextProcessingSettings.Default,
                CancellationToken.None);
            var provider = new FakeProvider();
            var output = new CapturingOutput();
            var orchestrator = Assert.IsType<DictationOrchestrator>(
                root.CreateDictationOrchestrator(
                    provider,
                    new FakeAudioCapture(),
                    output,
                    new DiscardingHistory(),
                    new DiscardingProgress(),
                    TimeProvider.System,
                    TimeSpan.FromSeconds(5)));

            await orchestrator.StartAsync(CancellationToken.None);
            var stopping = orchestrator.StopAsync(CancellationToken.None).AsTask();
            await provider.Session.FinishCalled.Task.WaitAsync(TimeSpan.FromSeconds(2));
            provider.Session.EmitFinal("嗯 hello世界 三个人");
            await stopping;

            Assert.Equal("Hello 世界 3 个人。", output.Text);
            await orchestrator.DisposeAsync();
        }
    }

    private sealed class DisabledRefiner : IStreamingTextRefiner
    {
        public ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(LlmRefinerAvailability.Disabled);

        public async IAsyncEnumerable<string> RefineAsync(
            string text,
            [System.Runtime.CompilerServices.EnumeratorCancellation]
            CancellationToken cancellationToken)
        {
            await Task.CompletedTask;
            yield break;
        }
    }

    private sealed class FakeProvider : IDictationAsrProvider
    {
        public AsrProviderAvailability Availability => AsrProviderAvailability.Ready;

        public FakeSession Session { get; } = new();

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult<IDictationAsrSession>(Session);
    }

    private sealed class FakeSession : IDictationAsrSession
    {
        public event EventHandler<AsrPartialResult>? PartialReceived
        {
            add { }
            remove { }
        }

        public event EventHandler<AsrFinalResult>? FinalReceived;

        public event EventHandler<VoxFlowError>? Failed
        {
            add { }
            remove { }
        }

        public TaskCompletionSource FinishCalled { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask StartAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask PushAudioAsync(
            ReadOnlyMemory<byte> pcmS16LittleEndian,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask FinishAsync(CancellationToken cancellationToken)
        {
            FinishCalled.TrySetResult();
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        public void EmitFinal(string text) =>
            FinalReceived?.Invoke(this, new AsrFinalResult(text));
    }

    private sealed class FakeAudioCapture : IDictationAudioCapture
    {
        public ValueTask StartAsync(
            Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask StopAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;
    }

    private sealed class CapturingOutput : IDictationOutput
    {
        public string? Text { get; private set; }

        public ValueTask<OutputResult> WriteAsync(
            string text,
            CancellationToken cancellationToken)
        {
            Text = text;
            return ValueTask.FromResult(new OutputResult(OutputResultKind.Inserted));
        }
    }

    private sealed class DiscardingHistory : IDictationHistorySink
    {
        public ValueTask SaveAsync(
            DictationHistoryDraft draft,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }

    private sealed class DiscardingProgress : IDictationProgressSink
    {
        public void Publish(DictationProgressUpdate update)
        {
        }
    }
}
