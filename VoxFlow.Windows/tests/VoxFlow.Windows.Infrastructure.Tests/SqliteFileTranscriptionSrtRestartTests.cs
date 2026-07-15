using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class SqliteFileTranscriptionSrtRestartTests
{
    [Fact]
    public async Task Srt_uses_persisted_segment_timestamps_after_database_reopen()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.sqlite");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        var factory = new SqliteConnectionFactory(databasePath, pooling: false);
        using (var writer = new SqliteTransactionRunner(factory))
        {
            var jobs = new SqliteFileTranscriptionJobRepository(writer);
            var segments = new SqliteFileTranscriptionSegmentRepository(writer);
            jobs.Create(new FileTranscriptionJob(
                "job-1",
                @"C:\Recordings\meeting.wav",
                "meeting.wav",
                AsrProviderId.Qwen,
                RecognitionLanguage.Automatic,
                1,
                status: FileTranscriptionJobStatus.Completed,
                progress: 1,
                finalText: "persisted text"));
            segments.Upsert(new FileTranscriptionSegment(
                "job-1",
                0,
                1_234,
                65_678,
                FileTranscriptionSegmentStatus.Completed,
                AsrProviderId.Qwen,
                "persisted text"));
        }

        var destination = new CapturingDestination();
        using (var reader = new SqliteTransactionRunner(factory))
        {
            var jobs = new SqliteFileTranscriptionJobRepository(reader);
            var segments = new SqliteFileTranscriptionSegmentRepository(reader);
            var service = new FileTranscriptionExportService(
                segments,
                destination,
                new FileTranscriptionExportLabels("Original", "Translation"));

            await service.ExportAsync(
                jobs.Get("job-1")!,
                FileTranscriptionExportFormat.Srt,
                CancellationToken.None);
        }

        Assert.Contains(
            "00:00:01,234 --> 00:01:05,678",
            destination.Document!.Content,
            StringComparison.Ordinal);
    }

    private sealed class CapturingDestination : IFileTranscriptionExportDestination
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
}
