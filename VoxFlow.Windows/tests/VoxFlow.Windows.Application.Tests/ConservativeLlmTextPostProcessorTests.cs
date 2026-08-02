using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.Tests;

public sealed class ConservativeLlmTextPostProcessorTests
{
    [Theory]
    [InlineData(LlmRefinerAvailability.NotConfigured)]
    [InlineData(LlmRefinerAvailability.Disabled)]
    public async Task Unavailable_or_disabled_LLM_returns_ASR_text_without_calling_network(
        LlmRefinerAvailability availability)
    {
        var refiner = new FakeStreamingTextRefiner { Availability = availability };
        var processor = new ConservativeLlmTextPostProcessor(refiner);
        var progress = new CapturingProgress();

        var result = await processor.ProcessAsync(
            "ASR 原文",
            progress,
            CancellationToken.None);

        Assert.Equal("ASR 原文", result);
        Assert.Equal(0, refiner.RefineCalls);
        Assert.Empty(progress.Values);
    }

    [Fact]
    public async Task Successful_stream_reports_cumulative_HUD_snapshots_but_returns_only_final_text()
    {
        var refiner = new FakeStreamingTextRefiner
        {
            Availability = LlmRefinerAvailability.Ready,
            Snapshots = ["修", "修正", "修正文本"],
        };
        var processor = new ConservativeLlmTextPostProcessor(refiner);
        var progress = new CapturingProgress();

        var result = await processor.ProcessAsync(
            "原始文本",
            progress,
            CancellationToken.None);

        Assert.Equal("修正文本", result);
        Assert.Equal(["修", "修正", "修正文本"], progress.Values);
        Assert.Equal(1, refiner.RefineCalls);
    }

    [Fact]
    public async Task Stream_failure_after_partial_discards_partial_and_falls_back_to_ASR_text()
    {
        var refiner = new FakeStreamingTextRefiner
        {
            Availability = LlmRefinerAvailability.Ready,
            Snapshots = ["partial"],
            Failure = new InvalidDataException("synthetic provider failure"),
        };
        var processor = new ConservativeLlmTextPostProcessor(refiner);
        var progress = new CapturingProgress();

        var result = await processor.ProcessAsync(
            "authoritative ASR",
            progress,
            CancellationToken.None);

        Assert.Equal("authoritative ASR", result);
        Assert.Equal(["partial", "authoritative ASR"], progress.Values);
    }

    [Fact]
    public async Task Empty_or_whitespace_stream_falls_back_to_ASR_text()
    {
        var refiner = new FakeStreamingTextRefiner
        {
            Availability = LlmRefinerAvailability.Ready,
            Snapshots = ["", "  "],
        };
        var processor = new ConservativeLlmTextPostProcessor(refiner);
        var progress = new CapturingProgress();

        var result = await processor.ProcessAsync(
            "raw",
            progress,
            CancellationToken.None);

        Assert.Equal("raw", result);
        Assert.Equal(["raw"], progress.Values);
    }

    [Fact]
    public async Task Cancellation_propagates_and_never_returns_a_partial_as_final()
    {
        var refiner = new FakeStreamingTextRefiner
        {
            Availability = LlmRefinerAvailability.Ready,
            Snapshots = ["partial"],
            BlockAfterSnapshots = true,
        };
        var processor = new ConservativeLlmTextPostProcessor(refiner);
        var progress = new CapturingProgress();
        using var cancellation = new CancellationTokenSource();
        var processing = processor.ProcessAsync(
            "raw",
            progress,
            cancellation.Token).AsTask();
        await refiner.BlockEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => processing);
        Assert.Equal(["partial"], progress.Values);
    }

    private sealed class CapturingProgress : IProgress<string>
    {
        public List<string> Values { get; } = [];

        public void Report(string value) => Values.Add(value);
    }

    private sealed class FakeStreamingTextRefiner : IStreamingTextRefiner
    {
        public LlmRefinerAvailability Availability { get; set; }

        public string[] Snapshots { get; set; } = [];

        public Exception? Failure { get; set; }

        public bool BlockAfterSnapshots { get; set; }

        public int RefineCalls { get; private set; }

        public TaskCompletionSource BlockEntered { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(Availability);

        public async IAsyncEnumerable<string> RefineAsync(
            string text,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            RefineCalls++;
            foreach (var snapshot in Snapshots)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return snapshot;
            }

            if (BlockAfterSnapshots)
            {
                BlockEntered.TrySetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }

            if (Failure is not null)
            {
                throw Failure;
            }
        }
    }
}
