#if DEBUG
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class DebugTranscriptInjectionRunnerTests
{
    [Fact]
    public async Task Injected_final_runs_the_real_orchestrator_downstream_without_audio()
    {
        var processor = new CapturingProcessor();
        var output = new CapturingOutput();
        var runner = new DebugTranscriptInjectionRunner((transcript, _) =>
            CreateOrchestrator(transcript, processor, output));

        var result = await runner.RunAsync(
            "测试语音纠错链路",
            DebugTranscriptInjectionMode.Dictation,
            CancellationToken.None);

        Assert.Equal(DebugTranscriptInjectionStatus.Completed, result.Status);
        Assert.Equal(DictationPhase.Completed, result.FinalPhase);
        Assert.Equal("测试语音纠错链路", processor.Input);
        Assert.Equal("processed:测试语音纠错链路", output.Text);
    }

    [Fact]
    public async Task Missing_agent_composition_reports_unavailable_instead_of_falling_back()
    {
        var runner = new DebugTranscriptInjectionRunner((_, _) => null);

        var result = await runner.RunAsync(
            "safe agent test",
            DebugTranscriptInjectionMode.AgentCompose,
            CancellationToken.None);

        Assert.Equal(DebugTranscriptInjectionStatus.Unavailable, result.Status);
    }

    private static DictationOrchestrator CreateOrchestrator(
        string transcript,
        IDictationTextPostProcessor processor,
        IDictationOutput output) => new(
        new DebugTranscriptAsrProvider(transcript),
        new DebugSilentAudioCapture(),
        processor,
        output,
        new DiscardingHistory(),
        new DiscardingProgress(),
        TimeProvider.System,
        TimeSpan.FromSeconds(1));

    private sealed class CapturingProcessor : IDictationTextPostProcessor
    {
        public string? Input { get; private set; }

        public ValueTask<string> ProcessAsync(
            string text,
            IProgress<string> streamingProgress,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Input = text;
            return ValueTask.FromResult("processed:" + text);
        }
    }

    private sealed class CapturingOutput : IDictationOutput
    {
        public string? Text { get; private set; }

        public ValueTask<OutputResult> WriteAsync(
            string text,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
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
        public void Publish(DictationProgressUpdate update) { }
    }
}
#endif
