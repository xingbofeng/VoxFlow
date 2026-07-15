using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public sealed record FileTranscriptionWindow(int Index, long StartMs, long EndMs)
{
    public const long DurationMs = 30_000;
    public const long StepMs = 28_500;

    public static IReadOnlyList<FileTranscriptionWindow> CreateForDuration(long durationMs)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(durationMs);
        if (durationMs == 0)
        {
            return [];
        }

        List<FileTranscriptionWindow> windows = [];
        for (var startMs = 0L; startMs < durationMs; startMs += StepMs)
        {
            var window = new FileTranscriptionWindow(
                windows.Count,
                startMs,
                Math.Min(startMs + DurationMs, durationMs));
            windows.Add(window);
            if (window.EndMs >= durationMs)
            {
                break;
            }
        }

        return windows;
    }
}

public sealed record FileTranscriptionSegmentRequest(
    string JobId,
    AsrProviderId Provider,
    RecognitionLanguage Language,
    FileTranscriptionWindow Window,
    string AudioPath,
    string PromptContext,
    int Attempt);

public sealed record FileTranscriptionWorkerResult(
    string? Text,
    FileTranscriptionErrorCode? ErrorCode = null);

public interface IFileTranscriptionWorker
{
    ValueTask<FileTranscriptionWorkerResult> TranscribeAsync(
        FileTranscriptionSegmentRequest request,
        CancellationToken cancellationToken);
}

public interface IFileTranscriptionWindowLease : IAsyncDisposable
{
    string AudioPath { get; }
}

public interface IFileTranscriptionWindowSource
{
    ValueTask<IFileTranscriptionWindowLease> CreateAsync(
        FileTranscriptionWindow window,
        CancellationToken cancellationToken);
}

public interface IFileTranscriptionSegmentSink
{
    ValueTask PublishAsync(
        FileTranscriptionSegment segment,
        CancellationToken cancellationToken);
}

public sealed record FileTranscriptionPipelineResult(
    IReadOnlyList<FileTranscriptionSegment> Segments,
    string FinalText);

public sealed class FileTranscriptionPipeline
{
    private const int PromptContextCharacterLimit = 200;
    private const int OverlapCharacterLimit = 30;
    private const int RetryCount = 2;
    private readonly IFileTranscriptionWorker worker;
    private readonly IFileTranscriptionWindowSource windowSource;
    private readonly IFileTranscriptionSegmentSink segmentSink;

    public FileTranscriptionPipeline(
        IFileTranscriptionWorker worker,
        IFileTranscriptionWindowSource windowSource,
        IFileTranscriptionSegmentSink segmentSink)
    {
        this.worker = worker ?? throw new ArgumentNullException(nameof(worker));
        this.windowSource = windowSource ?? throw new ArgumentNullException(nameof(windowSource));
        this.segmentSink = segmentSink ?? throw new ArgumentNullException(nameof(segmentSink));
    }

    public async ValueTask<FileTranscriptionPipelineResult> RunAsync(
        string jobId,
        AsrProviderId provider,
        RecognitionLanguage language,
        long durationMs,
        IReadOnlyCollection<FileTranscriptionSegment> completedSegments,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        ArgumentNullException.ThrowIfNull(completedSegments);

        var completedByIndex = completedSegments
            .Where(segment => segment.Status == FileTranscriptionSegmentStatus.Completed)
            .ToDictionary(segment => segment.Index);
        List<FileTranscriptionSegment> segments = [];
        var combinedText = string.Empty;

        foreach (var window in FileTranscriptionWindow.CreateForDuration(durationMs))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (completedByIndex.TryGetValue(window.Index, out var completed))
            {
                segments.Add(completed);
                combinedText = AppendText(combinedText, completed.Text!);
                await segmentSink.PublishAsync(completed, cancellationToken).ConfigureAwait(false);
                continue;
            }

            var running = new FileTranscriptionSegment(
                jobId,
                window.Index,
                window.StartMs,
                window.EndMs,
                FileTranscriptionSegmentStatus.Running,
                provider);
            await segmentSink.PublishAsync(running, cancellationToken).ConfigureAwait(false);
            await using var windowLease = await windowSource
                .CreateAsync(window, cancellationToken)
                .ConfigureAwait(false);
            var segment = await TranscribeWindowAsync(
                jobId,
                provider,
                language,
                window,
                windowLease.AudioPath,
                combinedText,
                cancellationToken).ConfigureAwait(false);
            segments.Add(segment);
            await segmentSink.PublishAsync(segment, cancellationToken).ConfigureAwait(false);
            if (segment.Status == FileTranscriptionSegmentStatus.Completed)
            {
                combinedText = AppendText(combinedText, segment.Text!);
            }
        }

        return new FileTranscriptionPipelineResult(
            segments.OrderBy(segment => segment.Index).ToArray(),
            combinedText);
    }

    private async ValueTask<FileTranscriptionSegment> TranscribeWindowAsync(
        string jobId,
        AsrProviderId provider,
        RecognitionLanguage language,
        FileTranscriptionWindow window,
        string audioPath,
        string accumulatedText,
        CancellationToken cancellationToken)
    {
        var promptContext = TakeTrailing(accumulatedText, PromptContextCharacterLimit);
        var fallbackReason = SegmentFallbackReason.None;
        for (var attempt = 0; attempt <= RetryCount; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            FileTranscriptionWorkerResult result;
            try
            {
                result = await worker.TranscribeAsync(
                    new FileTranscriptionSegmentRequest(
                        jobId,
                        provider,
                        language,
                        window,
                        audioPath,
                        promptContext,
                        attempt),
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                result = new FileTranscriptionWorkerResult(null, FileTranscriptionErrorCode.ProviderFailure);
            }

            var text = result.Text?.Trim();
            if (result.ErrorCode is null &&
                !string.IsNullOrEmpty(text) &&
                !IsDuplicate(text, accumulatedText))
            {
                return new FileTranscriptionSegment(
                    jobId,
                    window.Index,
                    window.StartMs,
                    window.EndMs,
                    FileTranscriptionSegmentStatus.Completed,
                    provider,
                    TrimOverlap(accumulatedText, text),
                    attempt,
                    FileTranscriptionProviderMode.SegmentedPcm,
                    fallbackReason);
            }

            fallbackReason = result.ErrorCode is not null
                ? SegmentFallbackReason.RetryAfterProviderError
                : string.IsNullOrEmpty(text)
                    ? SegmentFallbackReason.RetryAfterEmptyResult
                    : SegmentFallbackReason.RetryAfterDuplicateResult;
        }

        return new FileTranscriptionSegment(
            jobId,
            window.Index,
            window.StartMs,
            window.EndMs,
            FileTranscriptionSegmentStatus.Failed,
            provider,
            retryCount: RetryCount,
            fallbackReason: fallbackReason,
            errorCode: FileTranscriptionErrorCode.ProviderFailure);
    }

    private static bool IsDuplicate(string text, string accumulatedText) =>
        accumulatedText.EndsWith(text, StringComparison.Ordinal);

    private static string TrimOverlap(string accumulatedText, string text)
    {
        var max = Math.Min(OverlapCharacterLimit, Math.Min(accumulatedText.Length, text.Length));
        for (var length = max; length > 0; length--)
        {
            if (accumulatedText.EndsWith(text[..length], StringComparison.Ordinal))
            {
                return text[length..];
            }
        }

        return text;
    }

    private static string TakeTrailing(string value, int maximumLength) =>
        value.Length <= maximumLength ? value : value[^maximumLength..];

    private static string AppendText(string accumulatedText, string text) =>
        string.IsNullOrEmpty(accumulatedText)
            ? text
            : accumulatedText + Environment.NewLine + text;
}
