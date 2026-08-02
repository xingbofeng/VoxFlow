using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class FileTranscriptionActionFailureTests
{
    private const string SensitiveDiagnostic = @"C:\Users\Alice\private\provider-key.txt";

    [Fact]
    public async Task Export_unexpected_exception_becomes_safe_localized_feedback()
    {
        var jobs = new JobRepository(CompletedJob());
        var segments = new SegmentRepository();
        var service = new FileTranscriptionExportService(
            segments,
            new ThrowingExportDestination(),
            new FileTranscriptionExportLabels("Original", "Translation"));
        var viewModel = Create(jobs, segments, exportService: service);

        var result = await viewModel.ExportSelectedAsync(
            FileTranscriptionExportFormat.Text,
            CancellationToken.None);

        Assert.Null(result);
        Assert.Equal(L10n.Localize("FileTranscriptionFeedbackExportFailed"), viewModel.LastError);
        Assert.DoesNotContain("Alice", viewModel.Status, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("provider-key", viewModel.Status, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Translation_unexpected_exception_becomes_safe_localized_feedback()
    {
        var job = CompletedJob();
        var jobs = new JobRepository(job);
        var segments = new SegmentRepository();
        var service = new FileTranscriptionTranslationService(
            new ThrowingLookupJobRepository(job, () => new InvalidOperationException(SensitiveDiagnostic)),
            new UnusedTranslator(),
            TimeProvider.System);
        var viewModel = Create(jobs, segments, translationService: service);

        var result = await viewModel.TranslateSelectedAsync("zh-Hans", CancellationToken.None);

        Assert.Equal(FileTranscriptionTranslationResult.Failed, result);
        Assert.Equal(
            L10n.Localize("FileTranscriptionFeedbackTranslationFailed"),
            viewModel.LastError);
        Assert.DoesNotContain("Alice", viewModel.Status, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("provider-key", viewModel.Status, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Playback_unexpected_exception_becomes_safe_localized_feedback()
    {
        var jobs = new JobRepository(CompletedJob());
        var segments = new SegmentRepository();
        var playback = CreatePlaybackService();
        await playback.DisposeAsync();
        var viewModel = Create(jobs, segments, playbackService: playback);

        var result = await viewModel.TogglePlaybackSelectedAsync(CancellationToken.None);

        Assert.Equal(FileTranscriptionPlaybackState.Failed, result.State);
        Assert.Equal(
            L10n.Localize("FileTranscriptionFeedbackPlaybackFailed"),
            viewModel.LastError);
        Assert.DoesNotContain("ObjectDisposed", viewModel.Status, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Delete_playback_teardown_exception_becomes_safe_localized_feedback()
    {
        var jobs = new JobRepository(CompletedJob());
        var segments = new SegmentRepository();
        var playback = CreatePlaybackService();
        var viewModel = Create(jobs, segments, playbackService: playback);
        var started = await viewModel.TogglePlaybackSelectedAsync(CancellationToken.None);
        Assert.Equal(FileTranscriptionPlaybackState.Playing, started.State);
        await playback.DisposeAsync();

        var deleted = await viewModel.DeleteSelectedAsync(CancellationToken.None);

        Assert.False(deleted);
        Assert.Equal(
            L10n.Localize("FileTranscriptionFeedbackDeleteFailed"),
            viewModel.LastError);
        Assert.DoesNotContain("ObjectDisposed", viewModel.Status, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Requested_cancellation_is_not_converted_to_failure_feedback()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var job = CompletedJob();
        var jobs = new JobRepository(job);
        var segments = new SegmentRepository();
        var export = new FileTranscriptionExportService(
            segments,
            new CancellingExportDestination(),
            new FileTranscriptionExportLabels("Original", "Translation"));
        var translation = new FileTranscriptionTranslationService(
            new ThrowingLookupJobRepository(
                job,
                () => new OperationCanceledException(cancellation.Token)),
            new UnusedTranslator(),
            TimeProvider.System);
        var playback = CreatePlaybackService();
        var deletePlayback = CreatePlaybackService();
        var exportViewModel = Create(jobs, segments, exportService: export);
        var translationViewModel = Create(jobs, segments, translationService: translation);
        var playbackViewModel = Create(jobs, segments, playbackService: playback);
        var deleteViewModel = Create(jobs, segments, playbackService: deletePlayback);
        var started = await deleteViewModel.TogglePlaybackSelectedAsync(CancellationToken.None);
        Assert.Equal(FileTranscriptionPlaybackState.Playing, started.State);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await exportViewModel.ExportSelectedAsync(
                FileTranscriptionExportFormat.Text,
                cancellation.Token));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await translationViewModel.TranslateSelectedAsync("zh-Hans", cancellation.Token));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await playbackViewModel.TogglePlaybackSelectedAsync(cancellation.Token));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await deleteViewModel.DeleteSelectedAsync(cancellation.Token));

        Assert.Null(exportViewModel.LastError);
        Assert.Null(translationViewModel.LastError);
        Assert.Null(playbackViewModel.LastError);
        Assert.Null(deleteViewModel.LastError);

        await playback.DisposeAsync();
        await deletePlayback.DisposeAsync();
    }

    private static FileTranscriptionPageViewModel Create(
        IFileTranscriptionJobRepository jobs,
        IFileTranscriptionSegmentRepository segments,
        FileTranscriptionExportService? exportService = null,
        FileTranscriptionTranslationService? translationService = null,
        FileTranscriptionPlaybackService? playbackService = null) => new(
            "heading",
            "subtitle",
            jobs,
            queue: null,
            () => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B),
            () => RecognitionLanguage.Automatic,
            TimeProvider.System,
            segments: segments,
            exportService: exportService,
            translationService: translationService,
            playbackService: playbackService);

    private static FileTranscriptionPlaybackService CreatePlaybackService() => new(
        new PlaybackDecoder(),
        new PlaybackOutput());

    private static FileTranscriptionJob CompletedJob() => new(
        "job-1",
        @"C:\Media\meeting.wav",
        "meeting.wav",
        AsrProviderId.Qwen,
        RecognitionLanguage.Automatic,
        1,
        status: FileTranscriptionJobStatus.Completed,
        progress: 1,
        rawText: "source text",
        finalText: "source text",
        segmentCount: 1,
        segmentCompleted: 1,
        updatedAtUnixMs: 2,
        completedAtUnixMs: 2);

    private sealed class JobRepository(params FileTranscriptionJob[] initial)
        : IFileTranscriptionJobRepository
    {
        private readonly List<FileTranscriptionJob> jobs = [.. initial];

        public void Create(FileTranscriptionJob job) => jobs.Add(job);
        public FileTranscriptionJob? Get(string id) => jobs.SingleOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs.ToArray();
        public bool Update(FileTranscriptionJob job) => false;
        public bool Delete(string id) => false;
        public int MarkRunningAsInterrupted() => 0;
    }

    private sealed class ThrowingLookupJobRepository(
        FileTranscriptionJob job,
        Func<Exception> exception)
        : IFileTranscriptionJobRepository
    {
        public void Create(FileTranscriptionJob value) => throw new NotSupportedException();
        public FileTranscriptionJob? Get(string id) => throw exception();
        public IReadOnlyList<FileTranscriptionJob> List() => [job];
        public bool Update(FileTranscriptionJob value) => false;
        public bool Delete(string id) => false;
        public int MarkRunningAsInterrupted() => 0;
    }

    private sealed class SegmentRepository : IFileTranscriptionSegmentRepository
    {
        public void Upsert(FileTranscriptionSegment segment) { }
        public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId) => [];
        public int DeleteByJob(string jobId) => 0;
        public int MarkRunningAsInterrupted() => 0;
    }

    private sealed class ThrowingExportDestination : IFileTranscriptionExportDestination
    {
        public ValueTask<FileTranscriptionExportResult> SaveAsync(
            FileTranscriptionExportDocument document,
            CancellationToken cancellationToken) =>
            ValueTask.FromException<FileTranscriptionExportResult>(
                new InvalidOperationException(SensitiveDiagnostic));
    }

    private sealed class CancellingExportDestination : IFileTranscriptionExportDestination
    {
        public ValueTask<FileTranscriptionExportResult> SaveAsync(
            FileTranscriptionExportDocument document,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(FileTranscriptionExportResult.Saved);
        }
    }

    private sealed class UnusedTranslator : IFileTranscriptionTranslator
    {
        public ValueTask<string> TranslateAsync(
            string text,
            string targetLanguage,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult("unused");
    }

    private sealed class PlaybackDecoder : IFileTranscriptionPlaybackDecoder
    {
        public ValueTask<IFileTranscriptionPlaybackLease> DecodeAsync(
            FileTranscriptionJob job,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult<IFileTranscriptionPlaybackLease>(new PlaybackLease());
    }

    private sealed class PlaybackLease : IFileTranscriptionPlaybackLease
    {
        public string AudioPath => @"C:\Temp\voxflow-preview.wav";
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class PlaybackOutput : IFileTranscriptionPlaybackOutput
    {
        public void Start(string preparedAudioPath) { }
        public void Pause() { }
        public void Resume() { }
        public void Stop() { }
        public void Dispose() { }
    }
}
