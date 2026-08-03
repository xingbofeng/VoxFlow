using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionTranslationServiceTests
{
    [Fact]
    public async Task Explicit_translation_persists_pending_running_and_completed_without_changing_transcription()
    {
        var repository = new TranslationJobRepository(Job());
        var translator = new FakeTranslator("完整译文");
        var service = new FileTranscriptionTranslationService(
            repository,
            translator,
            new FixedTimeProvider(10));

        var result = await service.TranslateAsync(
            "job-1",
            "zh-Hans",
            CancellationToken.None);

        Assert.Equal(FileTranscriptionTranslationResult.Succeeded, result);
        Assert.Equal(
        [
            FileTranscriptionTranslationStatus.Pending,
            FileTranscriptionTranslationStatus.Running,
            FileTranscriptionTranslationStatus.Completed,
        ], repository.Updates.Select(job => job.TranslationStatus));
        var restored = repository.Get("job-1")!;
        Assert.Equal(FileTranscriptionJobStatus.Completed, restored.Status);
        Assert.Equal("original text", restored.FinalText);
        Assert.Equal("完整译文", restored.TranslatedText);
        Assert.Equal("zh-Hans", restored.TranslationTargetLanguage);
        Assert.Equal(("original text", "zh-Hans"), translator.Request);

        var destination = new CapturingTranslationDestination();
        var exporter = new FileTranscriptionExportService(
            new NoSegments(),
            destination,
            new FileTranscriptionExportLabels("Original", "Translation"));
        await exporter.ExportAsync(
            restored,
            FileTranscriptionExportFormat.BilingualMarkdown,
            CancellationToken.None);
        Assert.Contains("original text", destination.Document!.Content, StringComparison.Ordinal);
        Assert.Contains("完整译文", destination.Document.Content, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(TranslationFailureMode.Unavailable, FileTranscriptionTranslationResult.Unavailable)]
    [InlineData(TranslationFailureMode.HttpOrSse, FileTranscriptionTranslationResult.Failed)]
    [InlineData(TranslationFailureMode.Empty, FileTranscriptionTranslationResult.Failed)]
    public async Task Translation_failures_preserve_original_result_and_persist_failed_state(
        TranslationFailureMode mode,
        FileTranscriptionTranslationResult expected)
    {
        var repository = new TranslationJobRepository(Job());
        var service = new FileTranscriptionTranslationService(
            repository,
            new FakeTranslator(mode),
            new FixedTimeProvider(10));

        var result = await service.TranslateAsync(
            "job-1",
            "ja",
            CancellationToken.None);

        Assert.Equal(expected, result);
        var restored = repository.Get("job-1")!;
        Assert.Equal(FileTranscriptionTranslationStatus.Failed, restored.TranslationStatus);
        Assert.Equal(FileTranscriptionErrorCode.TranslationFailure, restored.TranslationErrorCode);
        Assert.Equal(FileTranscriptionJobStatus.Completed, restored.Status);
        Assert.Equal("original text", restored.FinalText);
        Assert.Null(restored.TranslatedText);
    }

    [Fact]
    public async Task Cancellation_stops_translation_and_preserves_original_result()
    {
        var repository = new TranslationJobRepository(Job());
        var service = new FileTranscriptionTranslationService(
            repository,
            new FakeTranslator(TranslationFailureMode.BlockUntilCancelled),
            new FixedTimeProvider(10));
        using var cancellation = new CancellationTokenSource();
        cancellation.CancelAfter(TimeSpan.FromMilliseconds(20));

        var result = await service.TranslateAsync("job-1", "ko", cancellation.Token);

        Assert.Equal(FileTranscriptionTranslationResult.Cancelled, result);
        var restored = repository.Get("job-1")!;
        Assert.Equal(FileTranscriptionTranslationStatus.Failed, restored.TranslationStatus);
        Assert.Equal(FileTranscriptionJobStatus.Completed, restored.Status);
        Assert.Equal("original text", restored.FinalText);
    }

    public enum TranslationFailureMode
    {
        Unavailable,
        HttpOrSse,
        Empty,
        BlockUntilCancelled,
    }

    private static FileTranscriptionJob Job() => new(
        "job-1",
        @"C:\Recordings\meeting.wav",
        "meeting.wav",
        AsrProviderId.Qwen,
        RecognitionLanguage.Automatic,
        1,
        status: FileTranscriptionJobStatus.Completed,
        progress: 1,
        finalText: "original text",
        updatedAtUnixMs: 2,
        completedAtUnixMs: 2);

    private sealed class FakeTranslator : IFileTranscriptionTranslator
    {
        private readonly string? result;
        private readonly TranslationFailureMode? failureMode;

        public FakeTranslator(string result) => this.result = result;
        public FakeTranslator(TranslationFailureMode failureMode) => this.failureMode = failureMode;

        public (string Text, string TargetLanguage)? Request { get; private set; }

        public async ValueTask<string> TranslateAsync(
            string text,
            string targetLanguage,
            CancellationToken cancellationToken)
        {
            Request = (text, targetLanguage);
            switch (failureMode)
            {
                case TranslationFailureMode.Unavailable:
                    throw new FileTranscriptionTranslationUnavailableException();
                case TranslationFailureMode.HttpOrSse:
                    throw new InvalidOperationException("safe fake failure");
                case TranslationFailureMode.Empty:
                    return string.Empty;
                case TranslationFailureMode.BlockUntilCancelled:
                    await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                    return string.Empty;
                default:
                    return result!;
            }
        }
    }

    private sealed class TranslationJobRepository(FileTranscriptionJob initial)
        : IFileTranscriptionJobRepository
    {
        private FileTranscriptionJob job = initial;

        public List<FileTranscriptionJob> Updates { get; } = [];
        public void Create(FileTranscriptionJob job) => throw new NotSupportedException();
        public FileTranscriptionJob? Get(string id) => id == job.Id ? job : null;
        public IReadOnlyList<FileTranscriptionJob> List() => [job];
        public bool Update(FileTranscriptionJob value)
        {
            job = value;
            Updates.Add(value);
            return true;
        }
        public bool Delete(string id) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }

    private sealed class FixedTimeProvider(long unixMilliseconds) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            DateTimeOffset.FromUnixTimeMilliseconds(unixMilliseconds);
    }

    private sealed class CapturingTranslationDestination : IFileTranscriptionExportDestination
    {
        public FileTranscriptionExportDocument? Document { get; private set; }

        public ValueTask<FileTranscriptionExportResult> SaveAsync(
            FileTranscriptionExportDocument document,
            CancellationToken cancellationToken)
        {
            Document = document;
            return ValueTask.FromResult(FileTranscriptionExportResult.Saved);
        }
    }

    private sealed class NoSegments : IFileTranscriptionSegmentRepository
    {
        public void Upsert(FileTranscriptionSegment segment) => throw new NotSupportedException();
        public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId) => [];
        public int DeleteByJob(string jobId) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }
}
