using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Application.Tests.Screenshot;

public sealed class ScreenshotCompletionServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 13, 9, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Successful_completion_saves_assets_runs_ocr_and_commits_one_consistent_record()
    {
        var runId = Guid.NewGuid();
        var assets = Assets("record");
        var assetStore = new FakeAssetStore(assets);
        var ocr = new FakeOcrService(request => new(
            request.RunId,
            request.ScreenshotId,
            request.OriginalImagePath,
            ScreenshotOcrOutcomeStatus.Succeeded,
            "recognized text",
            [new ScreenshotOcrLine("recognized text", 98, new(1, 2, 30, 10))]));
        var repository = new FakeRepository();
        var service = new ScreenshotCompletionService(
            assetStore,
            ocr,
            repository,
            new FixedRunValidity(runId));

        var result = await service.CompleteAsync(Request(runId), CancellationToken.None);

        Assert.Equal(ScreenshotCompletionStatus.Succeeded, result.Status);
        Assert.NotNull(repository.Added);
        var record = repository.Added;
        Assert.Equal("record", record.Id);
        Assert.Equal(assets.RenderedImagePath, record.RenderedImagePath);
        Assert.Equal("recognized text", record.OcrText);
        Assert.Equal(1440, record.WidthPixels);
        Assert.Equal(900, record.HeightPixels);
        Assert.Equal(1, assetStore.SaveCalls);
        Assert.Equal(0, assetStore.DeleteCalls);
        Assert.Equal(1, ocr.Calls);
    }

    [Fact]
    public async Task Inline_translation_ocr_uses_source_rendered_asset_and_keeps_translation_separate()
    {
        var runId = Guid.NewGuid();
        var stored = new ScreenshotAssetSet(
            "Screenshots/record/original.png",
            "Screenshots/record/rendered.png",
            "Screenshots/record/thumbnail.png",
            "Screenshots/record/translated.png",
            renderedFileSizeBytes: 9);
        var assetStore = new FakeAssetStore(stored);
        var repository = new FakeRepository();
        var service = new ScreenshotCompletionService(
            assetStore,
            new FakeOcrService(request => new ScreenshotOcrOutcome(
                request.RunId,
                request.ScreenshotId,
                request.OriginalImagePath,
                ScreenshotOcrOutcomeStatus.Succeeded,
                "source text")),
            repository,
            new FixedRunValidity(runId));

        var result = await service.CompleteAsync(
            Request(runId, "translated text"),
            CancellationToken.None);

        Assert.Equal(ScreenshotCompletionStatus.Succeeded, result.Status);
        Assert.Equal(stored.RenderedImagePath, assetStore.ResolvedRelativePath);
        Assert.Equal("source text", repository.Added!.OcrText);
        Assert.Equal("translated text", repository.Added.TranslatedText);
        Assert.Equal(stored.TranslatedImagePath, repository.Added.TranslatedImagePath);
    }

    [Theory]
    [InlineData(ScreenshotOcrOutcomeStatus.RuntimeUnavailable)]
    [InlineData(ScreenshotOcrOutcomeStatus.Empty)]
    [InlineData(ScreenshotOcrOutcomeStatus.TimedOut)]
    [InlineData(ScreenshotOcrOutcomeStatus.Failed)]
    public async Task Ocr_failure_preserves_image_and_commits_record_with_empty_text(
        ScreenshotOcrOutcomeStatus ocrStatus)
    {
        var runId = Guid.NewGuid();
        var repository = new FakeRepository();
        var service = new ScreenshotCompletionService(
            new FakeAssetStore(Assets("record")),
            new FakeOcrService(request => new(
                request.RunId,
                request.ScreenshotId,
                request.OriginalImagePath,
                ocrStatus)),
            repository,
            new FixedRunValidity(runId));

        var result = await service.CompleteAsync(Request(runId), CancellationToken.None);

        Assert.Equal(ScreenshotCompletionStatus.Succeeded, result.Status);
        Assert.Equal(ocrStatus, result.OcrOutcome!.Status);
        Assert.Equal(string.Empty, repository.Added!.OcrText);
    }

    [Fact]
    public async Task Repository_failure_compensates_all_new_assets_and_returns_safe_failure()
    {
        var runId = Guid.NewGuid();
        var assetStore = new FakeAssetStore(Assets("record"));
        var repository = new FakeRepository { ThrowOnAdd = true };
        var service = new ScreenshotCompletionService(
            assetStore,
            new FakeOcrService(request => new(
                request.RunId,
                request.ScreenshotId,
                request.OriginalImagePath,
                ScreenshotOcrOutcomeStatus.Empty)),
            repository,
            new FixedRunValidity(runId));

        var result = await service.CompleteAsync(Request(runId), CancellationToken.None);

        Assert.Equal(ScreenshotCompletionStatus.PersistenceFailed, result.Status);
        Assert.Equal("screenshot.persistence.record_failed", result.SafeErrorCode);
        Assert.Equal(1, assetStore.DeleteCalls);
        Assert.Null(repository.Added);
        Assert.DoesNotContain("Screenshots/", result.ToString(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(ScreenshotOcrOutcomeStatus.Cancelled, ScreenshotCompletionStatus.Cancelled)]
    [InlineData(ScreenshotOcrOutcomeStatus.Stale, ScreenshotCompletionStatus.Stale)]
    public async Task Cancelled_or_stale_ocr_compensates_assets_without_writing_history(
        ScreenshotOcrOutcomeStatus ocrStatus,
        ScreenshotCompletionStatus expected)
    {
        var runId = Guid.NewGuid();
        var assetStore = new FakeAssetStore(Assets("record"));
        var repository = new FakeRepository();
        var service = new ScreenshotCompletionService(
            assetStore,
            new FakeOcrService(request => new(
                request.RunId,
                request.ScreenshotId,
                request.OriginalImagePath,
                ocrStatus)),
            repository,
            new FixedRunValidity(runId));

        var result = await service.CompleteAsync(Request(runId), CancellationToken.None);

        Assert.Equal(expected, result.Status);
        Assert.Equal(1, assetStore.DeleteCalls);
        Assert.Null(repository.Added);
    }

    [Fact]
    public void Transform_persistence_updates_same_id_and_notifies_only_after_success()
    {
        var repository = new FakeRepository();
        var time = new FixedTimeProvider(Now.AddMinutes(2));
        var runId = Guid.NewGuid();
        var coordinator = new ScreenshotTransformPersistenceCoordinator(
            repository,
            time,
            new FixedResultRunValidity(runId));
        string? refreshed = null;
        coordinator.RecordUpdated += (_, args) => refreshed = args.ScreenshotId;
        var completed = new ScreenshotTransformCompleted(
            runId,
            "record",
            ScreenshotTransformOperation.Summary,
            "summary",
            false);

        Assert.True(coordinator.Persist(completed));
        Assert.Equal("record", repository.UpdatedId);
        Assert.Equal("record", refreshed);

        repository.UpdateResult = false;
        refreshed = null;
        Assert.False(coordinator.Persist(completed));
        Assert.Null(refreshed);
    }

    [Fact]
    public void Transform_persistence_rejects_late_result_from_stale_run()
    {
        var repository = new FakeRepository();
        var currentRunId = Guid.NewGuid();
        var coordinator = new ScreenshotTransformPersistenceCoordinator(
            repository,
            new FixedTimeProvider(Now),
            new FixedResultRunValidity(currentRunId));
        var stale = new ScreenshotTransformCompleted(
            Guid.NewGuid(),
            "record",
            ScreenshotTransformOperation.Translation,
            "late result",
            false);

        Assert.False(coordinator.Persist(stale));
        Assert.Null(repository.UpdatedId);
    }

    private static ScreenshotCompletionRequest Request(
        Guid runId,
        string? initialTranslatedText = null) => new(
        runId,
        "record",
        new ScreenshotAssetWriteRequest(
            "record",
            Png(1),
            Png(2),
            Png(3),
            initialTranslatedText is null ? default : Png(4)),
        widthPixels: 1440,
        heightPixels: 900,
        createdAtUtc: Now,
        currentLanguage: "zh-Hans",
        sourceDisplayId: "display-1",
        sourceWindowTitle: "private title",
        initialTranslatedText: initialTranslatedText);

    private static ScreenshotAssetSet Assets(string id) => new(
        $"Screenshots/{id}/{id}-original.png",
        $"Screenshots/{id}/{id}.png",
        $"Screenshots/{id}/{id}-thumbnail.png",
        null,
        renderedFileSizeBytes: 9);

    private static byte[] Png(byte marker) =>
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, marker];

    private sealed class FixedRunValidity(Guid runId) : IScreenshotRunValidity
    {
        public bool IsCurrent(Guid candidate) => candidate == runId;
    }

    private sealed class FixedResultRunValidity(Guid runId) : IScreenshotResultRunValidity
    {
        public bool IsResultCurrent(Guid candidate) => candidate == runId;
    }

    private sealed class FakeOcrService(
        Func<ScreenshotOcrRequest, ScreenshotOcrOutcome> result) : IScreenshotOcrService
    {
        public int Calls { get; private set; }

        public Task<ScreenshotOcrOutcome> RecognizeAsync(
            ScreenshotOcrRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Calls++;
            return Task.FromResult(result(request));
        }
    }

    private sealed class FakeAssetStore(ScreenshotAssetSet assets) : IScreenshotAssetStore
    {
        public int SaveCalls { get; private set; }
        public int DeleteCalls { get; private set; }
        public string? ResolvedRelativePath { get; private set; }

        public Task<ScreenshotAssetSet> SaveAsync(
            ScreenshotAssetWriteRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            SaveCalls++;
            return Task.FromResult(assets);
        }

        public Task<ScreenshotAssetDeleteResult> DeleteAsync(
            ScreenshotAssetSet value,
            CancellationToken cancellationToken)
        {
            DeleteCalls++;
            return Task.FromResult(new ScreenshotAssetDeleteResult(
                value.AllRelativePaths.Count));
        }

        public string ResolveAbsolutePath(string relativePath)
        {
            ResolvedRelativePath = relativePath;
            return @"C:\private\rendered.png";
        }

        public Task<int> CleanupOrphansAsync(
            IReadOnlySet<string> referencedRelativePaths,
            DateTimeOffset deleteBeforeUtcExclusive,
            CancellationToken cancellationToken) => Task.FromResult(0);
    }

    private sealed class FakeRepository : IScreenshotRecordRepository
    {
        public ScreenshotRecord? Added { get; private set; }
        public bool ThrowOnAdd { get; init; }
        public bool UpdateResult { get; set; } = true;
        public string? UpdatedId { get; private set; }

        public void Add(ScreenshotRecord record)
        {
            if (ThrowOnAdd) throw new InvalidOperationException("database failed");
            Added = record;
        }

        public ScreenshotRecord? Get(string id, bool includeDeleted = false) => Added;
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

        public bool UpdateTransform(
            string id,
            ScreenshotTransformOperation operation,
            string text,
            DateTimeOffset updatedAtUtc,
            string? translatedImagePath = null)
        {
            UpdatedId = id;
            return UpdateResult;
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
