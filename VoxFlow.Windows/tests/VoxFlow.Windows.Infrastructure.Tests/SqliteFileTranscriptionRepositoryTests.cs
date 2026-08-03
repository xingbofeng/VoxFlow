using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class SqliteFileTranscriptionRepositoryTests
{
    [Fact]
    public void Jobs_are_ordered_by_creation_and_keep_provider_language_and_translation()
    {
        using var fixture = new RepositoryFixture();
        fixture.Jobs.Create(CreateJob("later", 2));
        fixture.Jobs.Create(CreateJob("first", 1));

        fixture.Jobs.Update(CreateCompletedJob("first", 1));

        var jobs = fixture.Jobs.List();

        Assert.Equal(["first", "later"], jobs.Select(job => job.Id));
        var restored = Assert.Single(jobs, job => job.Id == "first");
        Assert.Equal(AsrProviderId.TencentCloud, restored.Provider);
        Assert.Equal(RecognitionLanguage.ChineseMandarin, restored.Language);
        Assert.Equal("raw text", restored.RawText);
        Assert.Equal("原始文本", restored.FinalText);
        Assert.Equal(2, restored.SegmentCount);
        Assert.Equal(2, restored.SegmentCompleted);
        Assert.Equal("translated text", restored.TranslatedText);
        Assert.Equal("en", restored.TranslationTargetLanguage);
        Assert.Equal(3, restored.TranslationUpdatedAtUnixMs);
        Assert.Equal(3, restored.CompletedAtUnixMs);
    }

    [Fact]
    public void Updating_progress_cannot_replace_the_enqueued_source_provider_or_language_snapshot()
    {
        using var fixture = new RepositoryFixture();
        fixture.Jobs.Create(CreateJob("job-1", 1));
        var attemptedReplacement = new FileTranscriptionJob(
            "job-1",
            @"C:\\Other\\replacement.mp3",
            "replacement.mp3",
            AsrProviderId.Volcengine,
            RecognitionLanguage.English,
            1,
            status: FileTranscriptionJobStatus.Completed,
            progress: 1,
            finalText: "done",
            updatedAtUnixMs: 2);

        Assert.True(fixture.Jobs.Update(attemptedReplacement));

        var restored = fixture.Jobs.Get("job-1")!;
        Assert.Equal(@"C:\\Recordings\\job-1.wav", restored.SourcePath);
        Assert.Equal("job-1.wav", restored.DisplayName);
        Assert.Equal(AsrProviderId.TencentCloud, restored.Provider);
        Assert.Equal(RecognitionLanguage.ChineseMandarin, restored.Language);
        Assert.Equal("done", restored.FinalText);
    }

    [Fact]
    public void Segments_are_upserted_in_stable_order_and_running_work_is_interrupted()
    {
        using var fixture = new RepositoryFixture();
        fixture.Jobs.Create(CreateJob("job-1", 1));
        fixture.Segments.Upsert(new FileTranscriptionSegment(
            "job-1", 1, 28_500, 58_500, FileTranscriptionSegmentStatus.Running,
            AsrProviderId.TencentCloud));
        fixture.Segments.Upsert(new FileTranscriptionSegment(
            "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Completed,
            AsrProviderId.TencentCloud, "first"));
        fixture.Jobs.Update(CreateRunningJob("job-1", 1));

        var interruptedCount = fixture.Jobs.MarkRunningAsInterrupted();
        var interruptedSegments = fixture.Segments.MarkRunningAsInterrupted();
        var restored = fixture.Segments.ListByJob("job-1");

        Assert.Equal(1, interruptedCount);
        Assert.Equal(1, interruptedSegments);
        Assert.Equal(FileTranscriptionJobStatus.Interrupted, fixture.Jobs.Get("job-1")!.Status);
        Assert.Equal([0, 1], restored.Select(segment => segment.Index));
        Assert.Equal(FileTranscriptionSegmentStatus.Completed, restored[0].Status);
        Assert.All(restored, segment => Assert.Equal(AsrProviderId.TencentCloud, segment.Provider));
        Assert.Equal(FileTranscriptionSegmentStatus.Interrupted, restored[1].Status);
    }

    [Fact]
    public void Deleting_a_job_removes_its_segments()
    {
        using var fixture = new RepositoryFixture();
        fixture.Jobs.Create(CreateJob("job-1", 1));
        fixture.Segments.Upsert(new FileTranscriptionSegment(
            "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Completed,
            AsrProviderId.TencentCloud, "text"));

        Assert.True(fixture.Jobs.Delete("job-1"));

        Assert.Null(fixture.Jobs.Get("job-1"));
        Assert.Empty(fixture.Segments.ListByJob("job-1"));
    }

    [Fact]
    public void Segment_upsert_replaces_mutable_state_without_creating_a_duplicate()
    {
        using var fixture = new RepositoryFixture();
        fixture.Jobs.Create(CreateJob("job-1", 1));
        fixture.Segments.Upsert(new FileTranscriptionSegment(
            "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Running,
            AsrProviderId.TencentCloud));
        fixture.Segments.Upsert(new FileTranscriptionSegment(
            "job-1",
            0,
            0,
            30_000,
            FileTranscriptionSegmentStatus.Failed,
            AsrProviderId.TencentCloud,
            retryCount: 2,
            fallbackReason: SegmentFallbackReason.RetryAfterProviderError,
            errorCode: FileTranscriptionErrorCode.ProviderFailure));

        var restored = Assert.Single(fixture.Segments.ListByJob("job-1"));
        Assert.Equal(FileTranscriptionSegmentStatus.Failed, restored.Status);
        Assert.Equal(2, restored.RetryCount);
        Assert.Equal(SegmentFallbackReason.RetryAfterProviderError, restored.FallbackReason);
        Assert.Equal(FileTranscriptionErrorCode.ProviderFailure, restored.ErrorCode);
    }

    private static FileTranscriptionJob CreateJob(string id, long createdAtUnixMs) => new(
        id,
        $@"C:\\Recordings\\{id}.wav",
        $"{id}.wav",
        AsrProviderId.TencentCloud,
        RecognitionLanguage.ChineseMandarin,
        createdAtUnixMs);

    private static FileTranscriptionJob CreateRunningJob(string id, long createdAtUnixMs) => new(
        id,
        $@"C:\\Recordings\\{id}.wav",
        $"{id}.wav",
        AsrProviderId.TencentCloud,
        RecognitionLanguage.ChineseMandarin,
        createdAtUnixMs,
        status: FileTranscriptionJobStatus.Running);

    private static FileTranscriptionJob CreateCompletedJob(string id, long createdAtUnixMs) => new(
        id,
        $@"C:\\Recordings\\{id}.wav",
        $"{id}.wav",
        AsrProviderId.TencentCloud,
        RecognitionLanguage.ChineseMandarin,
        createdAtUnixMs,
        status: FileTranscriptionJobStatus.Completed,
        progress: 1,
        rawText: "raw text",
        finalText: "原始文本",
        segmentCount: 2,
        segmentCompleted: 2,
        translationStatus: FileTranscriptionTranslationStatus.Completed,
        translatedText: "translated text",
        translationTargetLanguage: "en",
        translationUpdatedAtUnixMs: 3,
        updatedAtUnixMs: 3,
        completedAtUnixMs: 3);

    private sealed class RepositoryFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly SqliteTransactionRunner transactionRunner;

        public RepositoryFixture()
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.sqlite");
            new VoxFlowDatabaseMigrator().Migrate(databasePath);
            transactionRunner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(databasePath, pooling: false));
            Jobs = new SqliteFileTranscriptionJobRepository(transactionRunner);
            Segments = new SqliteFileTranscriptionSegmentRepository(transactionRunner);
        }

        public SqliteFileTranscriptionJobRepository Jobs { get; }

        public SqliteFileTranscriptionSegmentRepository Segments { get; }

        public void Dispose()
        {
            transactionRunner.Dispose();
            directory.Dispose();
        }
    }
}
