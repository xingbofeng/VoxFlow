using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Screenshots;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Screenshots;

public sealed class ScreenshotCompletionPersistenceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 13, 9, 30, 0, TimeSpan.Zero);

    [Fact]
    public async Task Real_asset_and_sqlite_completion_survives_repository_restart_and_missing_file()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        Migrate(databasePath);
        var runId = Guid.NewGuid();
        var store = new FileScreenshotAssetStore(directory.Path);
        using (var runner = NewRunner(databasePath))
        {
            var service = new ScreenshotCompletionService(
                store,
                new FixedOcrService(ScreenshotOcrOutcomeStatus.Succeeded, "persistent OCR"),
                new SqliteScreenshotRecordRepository(runner),
                new FixedRunValidity(runId));

            var result = await service.CompleteAsync(Request(runId), CancellationToken.None);

            Assert.Equal(ScreenshotCompletionStatus.Succeeded, result.Status);
            Assert.All(
                new[]
                {
                    result.Record!.OriginalImagePath,
                    result.Record.RenderedImagePath,
                    result.Record.ThumbnailPath,
                },
                path => Assert.True(File.Exists(store.ResolveAbsolutePath(path))));
        }

        using (var restarted = NewRunner(databasePath))
        {
            var record = new SqliteScreenshotRecordRepository(restarted).Get("persistent");
            Assert.NotNull(record);
            Assert.Equal("persistent OCR", record.OcrText);
            File.Delete(store.ResolveAbsolutePath(record.RenderedImagePath));
        }

        using var afterMissingFile = NewRunner(databasePath);
        var preserved = new SqliteScreenshotRecordRepository(afterMissingFile).Get("persistent");
        Assert.NotNull(preserved);
        Assert.Equal("persistent OCR", preserved.OcrText);
        Assert.False(File.Exists(store.ResolveAbsolutePath(preserved.RenderedImagePath)));
    }

    [Fact]
    public async Task Real_asset_files_are_compensated_when_repository_commit_fails()
    {
        using var directory = new TemporaryDirectory();
        var runId = Guid.NewGuid();
        var store = new FileScreenshotAssetStore(directory.Path);
        var service = new ScreenshotCompletionService(
            store,
            new FixedOcrService(ScreenshotOcrOutcomeStatus.Empty, string.Empty),
            new ThrowingRepository(),
            new FixedRunValidity(runId));

        var result = await service.CompleteAsync(Request(runId), CancellationToken.None);

        Assert.Equal(ScreenshotCompletionStatus.PersistenceFailed, result.Status);
        var screenshotRoot = Path.Combine(directory.Path, "Screenshots");
        Assert.Empty(Directory.EnumerateFiles(screenshotRoot, "*.png", SearchOption.AllDirectories));
        Assert.Empty(Directory.EnumerateFiles(screenshotRoot, "*.tmp-*", SearchOption.AllDirectories));
    }

    private static ScreenshotCompletionRequest Request(Guid runId) => new(
        runId,
        "persistent",
        new ScreenshotAssetWriteRequest("persistent", Png(1), Png(2), Png(3)),
        800,
        600,
        Now,
        "en-US");

    private static byte[] Png(byte marker) =>
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, marker];

    private static void Migrate(string databasePath)
    {
        var flags = new WindowsInteractiveFeatureFlags(
            selectionTransformEnabled: true,
            builtinAgentEnabled: true);
        new VoxFlowDatabaseMigrator(
        [
            .. InteractiveFeatureMigrationCatalog.For(flags),
            .. ScreenshotMigrationCatalog.All(),
        ]).Migrate(databasePath);
    }

    private static SqliteTransactionRunner NewRunner(string databasePath) => new(
        new SqliteConnectionFactory(databasePath, pooling: false));

    private sealed class FixedRunValidity(Guid runId) : IScreenshotRunValidity
    {
        public bool IsCurrent(Guid candidate) => candidate == runId;
    }

    private sealed class FixedOcrService(
        ScreenshotOcrOutcomeStatus status,
        string text) : IScreenshotOcrService
    {
        public Task<ScreenshotOcrOutcome> RecognizeAsync(
            ScreenshotOcrRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(status == ScreenshotOcrOutcomeStatus.Succeeded
                ? new ScreenshotOcrOutcome(
                    request.RunId,
                    request.ScreenshotId,
                    request.OriginalImagePath,
                    status,
                    text,
                    [new ScreenshotOcrLine(text, 90, new(0, 0, 100, 20))])
                : new ScreenshotOcrOutcome(
                    request.RunId,
                    request.ScreenshotId,
                    request.OriginalImagePath,
                    status));
        }
    }

    private sealed class ThrowingRepository : IScreenshotRecordRepository
    {
        public void Add(ScreenshotRecord record) =>
            throw new InvalidOperationException("forced database failure");

        public ScreenshotRecord? Get(string id, bool includeDeleted = false) => null;
        public ScreenshotRecordPage Search(ScreenshotRecordQuery query) => new([], 0, 0, query.Limit);
        public ScreenshotRecordAggregate GetAggregate(ScreenshotRecordAggregateQuery query) =>
            new(0, 0, 0);
        public ScreenshotRecordStats GetStats() => new(0, 0, 0, 0);
        public IReadOnlyList<ScreenshotRecord> ListDeletedBefore(
            DateTimeOffset deletedBeforeUtcExclusive) => [];
        public IReadOnlySet<string> ListReferencedAssetPaths() => new HashSet<string>();
        public bool SetFavorite(string id, bool isFavorite, DateTimeOffset updatedAtUtc) => false;
        public bool SoftDelete(string id, DateTimeOffset deletedAtUtc) => false;
        public bool PurgeDeleted(
            string id,
            DateTimeOffset deletedBeforeUtcExclusive) => false;
        public bool ReplaceOcrAndInvalidateTransforms(
            string id,
            string text,
            DateTimeOffset updatedAtUtc) => false;
        public bool UpdateTransform(string id, ScreenshotTransformOperation operation, string text, DateTimeOffset updatedAtUtc, string? translatedImagePath = null) => false;
    }
}
