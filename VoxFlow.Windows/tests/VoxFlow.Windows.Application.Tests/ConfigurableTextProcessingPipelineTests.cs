using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Application.Tests;

public sealed class ConfigurableTextProcessingPipelineTests
{
    [Fact]
    public async Task Pipeline_runs_filler_and_numbers_before_LLM_then_formatting_after_it()
    {
        var store = new FakeSettingsStore(DeterministicTextProcessingSettings.Default);
        var llm = new CapturingLlmProcessor();
        var pipeline = new ConfigurableTextProcessingPipeline(store, llm);
        var progress = new CapturingProgress();

        var result = await pipeline.ProcessAsync(
            "嗯 hello世界 三个人",
            progress,
            CancellationToken.None);

        Assert.Equal("hello世界 3个人", llm.Input);
        Assert.Equal("Hello 世界 3 个人。", result);
        Assert.Equal("Hello 世界 3 个人。", progress.Values[^1]);
    }

    [Fact]
    public async Task Master_switch_off_skips_LLM_and_every_deterministic_processor()
    {
        var store = new FakeSettingsStore(
            DeterministicTextProcessingSettings.Default with { Enabled = false });
        var llm = new CapturingLlmProcessor();
        var pipeline = new ConfigurableTextProcessingPipeline(store, llm);

        var result = await pipeline.ProcessAsync(
            "嗯 hello世界",
            new CapturingProgress(),
            CancellationToken.None);

        Assert.Equal("嗯 hello世界", result);
        Assert.Equal(0, llm.Calls);
    }

    [Fact]
    public async Task LLM_failure_falls_back_to_deterministic_processing_without_another_provider()
    {
        var store = new FakeSettingsStore(DeterministicTextProcessingSettings.Default);
        var llm = new CapturingLlmProcessor
        {
            Failure = new InvalidDataException("synthetic failure"),
        };
        var pipeline = new ConfigurableTextProcessingPipeline(store, llm);

        var result = await pipeline.ProcessAsync(
            "嗯 hello世界",
            new CapturingProgress(),
            CancellationToken.None);

        Assert.Equal("Hello 世界。", result);
        Assert.Equal(1, llm.Calls);
    }

    private sealed class FakeSettingsStore(
        DeterministicTextProcessingSettings settings) : ITextProcessingSettingsStore
    {
        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(settings);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings value,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class CapturingLlmProcessor : IDictationTextPostProcessor
    {
        public int Calls { get; private set; }

        public string? Input { get; private set; }

        public Exception? Failure { get; set; }

        public ValueTask<string> ProcessAsync(
            string text,
            IProgress<string> streamingProgress,
            CancellationToken cancellationToken)
        {
            Calls++;
            Input = text;
            if (Failure is not null)
            {
                throw Failure;
            }

            return ValueTask.FromResult(text);
        }
    }

    private sealed class CapturingProgress : IProgress<string>
    {
        public List<string> Values { get; } = [];

        public void Report(string value) => Values.Add(value);
    }
}
