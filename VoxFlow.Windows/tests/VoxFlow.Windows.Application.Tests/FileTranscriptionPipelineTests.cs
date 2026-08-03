using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionPipelineTests
{
    [Fact]
    public void Windows_follow_the_macos_thirty_second_and_one_point_five_second_overlap_contract()
    {
        var windows = FileTranscriptionWindow.CreateForDuration(60_000);

        Assert.Equal(
        [
            new FileTranscriptionWindow(0, 0, 30_000),
            new FileTranscriptionWindow(1, 28_500, 58_500),
            new FileTranscriptionWindow(2, 57_000, 60_000),
        ], windows);

        Assert.Equal(
            [new FileTranscriptionWindow(0, 0, 30_000)],
            FileTranscriptionWindow.CreateForDuration(30_000));
        Assert.Equal(
            [
                new FileTranscriptionWindow(0, 0, 30_000),
                new FileTranscriptionWindow(1, 28_500, 58_500),
            ],
            FileTranscriptionWindow.CreateForDuration(58_500));
    }

    [Fact]
    public async Task Pipeline_reuses_completed_segments_and_sends_a_bounded_context_to_later_windows()
    {
        var requests = new List<FileTranscriptionSegmentRequest>();
        var worker = new CapturingWorker(requests, "new result");
        var windows = new CapturingWindowSource();
        var events = new CapturingSegmentSink();
        var pipeline = new FileTranscriptionPipeline(worker, windows, events);
        var completed = new FileTranscriptionSegment(
            "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Completed,
            AsrProviderId.TencentCloud,
            new string('a', 210));

        var result = await pipeline.RunAsync(
            "job-1",
            AsrProviderId.TencentCloud,
            RecognitionLanguage.English,
            58_500,
            [completed],
            CancellationToken.None);

        Assert.Single(requests);
        Assert.Equal(1, requests[0].Window.Index);
        Assert.Equal(AsrProviderId.TencentCloud, requests[0].Provider);
        Assert.Equal(RecognitionLanguage.English, requests[0].Language);
        Assert.Equal("segment-000001.wav", requests[0].AudioPath);
        Assert.Equal(200, requests[0].PromptContext.Length);
        Assert.Equal([1], windows.CreatedIndexes);
        Assert.Equal(
            [FileTranscriptionSegmentStatus.Completed, FileTranscriptionSegmentStatus.Running, FileTranscriptionSegmentStatus.Completed],
            events.Segments.Select(segment => segment.Status));
        Assert.Equal(2, result.Segments.Count);
        Assert.Equal(new string('a', 210) + Environment.NewLine + "new result", result.FinalText);
    }

    [Fact]
    public async Task Pipeline_retries_empty_results_twice_then_marks_the_segment_failed()
    {
        var worker = new CapturingWorker([], string.Empty);
        var events = new CapturingSegmentSink();
        var pipeline = new FileTranscriptionPipeline(worker, new CapturingWindowSource(), events);

        var result = await pipeline.RunAsync(
            "job-1",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            28_500,
            [],
            CancellationToken.None);

        var segment = Assert.Single(result.Segments);
        Assert.Equal(FileTranscriptionSegmentStatus.Failed, segment.Status);
        Assert.Equal(2, segment.RetryCount);
        Assert.Equal(SegmentFallbackReason.RetryAfterEmptyResult, segment.FallbackReason);
        Assert.Equal(FileTranscriptionErrorCode.ProviderFailure, segment.ErrorCode);
        Assert.Equal(3, worker.CallCount);
        Assert.Equal(
            [FileTranscriptionSegmentStatus.Running, FileTranscriptionSegmentStatus.Failed],
            events.Segments.Select(segment => segment.Status));
    }

    [Fact]
    public async Task Pipeline_classifies_provider_errors_and_retries_them_twice()
    {
        var worker = new FailingWorker();
        var pipeline = new FileTranscriptionPipeline(
            worker,
            new CapturingWindowSource(),
            new CapturingSegmentSink());

        var result = await pipeline.RunAsync(
            "job-1",
            AsrProviderId.AliyunDashScope,
            RecognitionLanguage.ChineseMandarin,
            10_000,
            [],
            CancellationToken.None);

        var segment = Assert.Single(result.Segments);
        Assert.Equal(SegmentFallbackReason.RetryAfterProviderError, segment.FallbackReason);
        Assert.Equal(3, worker.CallCount);
    }

    [Fact]
    public async Task Pipeline_trims_at_most_thirty_leading_overlap_characters()
    {
        var requests = new List<FileTranscriptionSegmentRequest>();
        var worker = new CapturingWorker(requests, "overlap phrase continuation");
        var pipeline = new FileTranscriptionPipeline(
            worker,
            new CapturingWindowSource(),
            new CapturingSegmentSink());
        var completed = new FileTranscriptionSegment(
            "job-1",
            0,
            0,
            30_000,
            FileTranscriptionSegmentStatus.Completed,
            AsrProviderId.Volcengine,
            "first overlap phrase ");

        var result = await pipeline.RunAsync(
            "job-1",
            AsrProviderId.Volcengine,
            RecognitionLanguage.Japanese,
            58_500,
            [completed],
            CancellationToken.None);

        Assert.Equal("continuation", result.Segments[1].Text);
        Assert.Equal(
            "first overlap phrase " + Environment.NewLine + "continuation",
            result.FinalText);
    }

    [Fact]
    public async Task Pipeline_retries_an_exact_duplicate_twice_then_fails_the_segment()
    {
        var worker = new CapturingWorker([], "duplicate text");
        var pipeline = new FileTranscriptionPipeline(
            worker,
            new CapturingWindowSource(),
            new CapturingSegmentSink());
        var completed = new FileTranscriptionSegment(
            "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Completed,
            AsrProviderId.TencentCloud, "duplicate text");

        var result = await pipeline.RunAsync(
            "job-1",
            AsrProviderId.TencentCloud,
            RecognitionLanguage.Korean,
            58_500,
            [completed],
            CancellationToken.None);

        Assert.Equal(3, worker.CallCount);
        Assert.Equal(FileTranscriptionSegmentStatus.Failed, result.Segments[1].Status);
        Assert.Equal(
            SegmentFallbackReason.RetryAfterDuplicateResult,
            result.Segments[1].FallbackReason);
    }

    private sealed class CapturingWorker(
        List<FileTranscriptionSegmentRequest> requests,
        params string[] results) : IFileTranscriptionWorker
    {
        private readonly Queue<string> results = new(results);

        public int CallCount { get; private set; }

        public ValueTask<FileTranscriptionWorkerResult> TranscribeAsync(
            FileTranscriptionSegmentRequest request,
            CancellationToken cancellationToken)
        {
            requests.Add(request);
            CallCount++;
            var text = results.Count > 1 ? results.Dequeue() : results.Peek();
            return ValueTask.FromResult(new FileTranscriptionWorkerResult(text));
        }
    }

    private sealed class FailingWorker : IFileTranscriptionWorker
    {
        public int CallCount { get; private set; }

        public ValueTask<FileTranscriptionWorkerResult> TranscribeAsync(
            FileTranscriptionSegmentRequest request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            return ValueTask.FromResult(new FileTranscriptionWorkerResult(
                null,
                FileTranscriptionErrorCode.ProviderFailure));
        }
    }

    private sealed class CapturingWindowSource : IFileTranscriptionWindowSource
    {
        public List<int> CreatedIndexes { get; } = [];

        public ValueTask<IFileTranscriptionWindowLease> CreateAsync(
            FileTranscriptionWindow window,
            CancellationToken cancellationToken)
        {
            CreatedIndexes.Add(window.Index);
            return ValueTask.FromResult<IFileTranscriptionWindowLease>(
                new FakeWindowLease($"segment-{window.Index:D6}.wav"));
        }
    }

    private sealed class FakeWindowLease(string audioPath) : IFileTranscriptionWindowLease
    {
        public string AudioPath { get; } = audioPath;

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class CapturingSegmentSink : IFileTranscriptionSegmentSink
    {
        public List<FileTranscriptionSegment> Segments { get; } = [];

        public ValueTask PublishAsync(
            FileTranscriptionSegment segment,
            CancellationToken cancellationToken)
        {
            Segments.Add(segment);
            return ValueTask.CompletedTask;
        }
    }
}
