using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests.Screenshot;

public sealed class ScreenshotMaintenanceServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 8, 30, 0, TimeSpan.Zero);

    [Fact]
    public async Task Startup_purges_only_expired_soft_deleted_records_then_cleans_safe_orphans()
    {
        var active = Record("active");
        var recent = Record("recent", Now.AddDays(-10));
        var expired = Record(
            "expired",
            Now.AddDays(-31),
            translatedImagePath: "Screenshots/expired-translated.png");
        var records = new MemoryRepository([active, recent, expired]);
        var assets = new CapturingAssetStore { OrphanDeleteCount = 2 };
        var service = new ScreenshotMaintenanceService(
            records,
            assets,
            new FixedTimeProvider(Now));

        var result = await service.CleanupOnStartupAsync(
            HistoryRetentionPolicy.Default,
            CancellationToken.None);

        Assert.Equal(1, result.ExpiredRecordCount);
        Assert.Equal(1, result.PurgedRecordCount);
        Assert.Equal(0, result.DeferredRecordCount);
        Assert.Equal(4, result.DeletedManagedFileCount);
        Assert.Equal(2, result.DeletedOrphanFileCount);
        Assert.False(result.HadFailure);
        Assert.Null(records.Get(expired.Id, includeDeleted: true));
        Assert.NotNull(records.Get(active.Id));
        Assert.NotNull(records.Get(recent.Id, includeDeleted: true));
        var deleted = Assert.Single(assets.DeleteRequests);
        Assert.Equal(expired.OriginalImagePath, deleted.OriginalImagePath);
        Assert.Equal(
            Now - ScreenshotMaintenanceService.OrphanSafetyPeriod,
            assets.OrphanCutoff);
        Assert.Equal(
            records.ListReferencedAssetPaths().Order(),
            assets.OrphanReferences.Order());
        Assert.DoesNotContain(expired.OriginalImagePath, assets.OrphanReferences);
    }

    [Fact]
    public async Task Failed_asset_cleanup_keeps_soft_deleted_row_as_a_retry_marker()
    {
        var expired = Record("retry", Now.AddDays(-31));
        var records = new MemoryRepository([expired]);
        var assets = new CapturingAssetStore();
        assets.BlockedPaths.Add(expired.RenderedImagePath);
        var service = new ScreenshotMaintenanceService(
            records,
            assets,
            new FixedTimeProvider(Now));

        var blocked = await service.CleanupOnStartupAsync(
            HistoryRetentionPolicy.Default,
            CancellationToken.None);

        Assert.Equal(0, blocked.PurgedRecordCount);
        Assert.Equal(1, blocked.DeferredRecordCount);
        Assert.True(blocked.HadFailure);
        Assert.NotNull(records.Get(expired.Id, includeDeleted: true));
        Assert.Contains(expired.RenderedImagePath, assets.OrphanReferences);

        assets.BlockedPaths.Clear();
        var retried = await service.CleanupOnStartupAsync(
            HistoryRetentionPolicy.Default,
            CancellationToken.None);

        Assert.Equal(1, retried.PurgedRecordCount);
        Assert.Equal(0, retried.DeferredRecordCount);
        Assert.Null(records.Get(expired.Id, includeDeleted: true));
        Assert.Equal(2, assets.DeleteRequests.Count);
    }

    private static ScreenshotRecord Record(
        string id,
        DateTimeOffset? deletedAtUtc = null,
        string? translatedImagePath = null) => new(
            id,
            $"Screenshots/{id}-original.png",
            $"Screenshots/{id}.png",
            $"Screenshots/{id}-thumbnail.png",
            widthPixels: 1200,
            heightPixels: 800,
            fileSizeBytes: 100,
            ocrText: id,
            createdAtUtc: Now.AddDays(-90),
            translatedImagePath: translatedImagePath,
            updatedAtUtc: deletedAtUtc ?? Now.AddDays(-90),
            deletedAtUtc: deletedAtUtc);

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class CapturingAssetStore : IScreenshotAssetStore
    {
        public List<ScreenshotAssetSet> DeleteRequests { get; } = [];

        public HashSet<string> BlockedPaths { get; } =
            new(StringComparer.OrdinalIgnoreCase);

        public IReadOnlySet<string> OrphanReferences { get; private set; } =
            new HashSet<string>();

        public DateTimeOffset? OrphanCutoff { get; private set; }

        public int OrphanDeleteCount { get; init; }

        public Task<ScreenshotAssetSet> SaveAsync(
            ScreenshotAssetWriteRequest request,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ScreenshotAssetDeleteResult> DeleteAsync(
            ScreenshotAssetSet assets,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            DeleteRequests.Add(assets);
            var remaining = assets.AllRelativePaths
                .Where(BlockedPaths.Contains)
                .ToArray();
            return Task.FromResult(new ScreenshotAssetDeleteResult(
                assets.AllRelativePaths.Count - remaining.Length,
                remaining));
        }

        public string ResolveAbsolutePath(string relativePath) =>
            throw new NotSupportedException();

        public Task<int> CleanupOrphansAsync(
            IReadOnlySet<string> referencedRelativePaths,
            DateTimeOffset deleteBeforeUtcExclusive,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            OrphanReferences = referencedRelativePaths.ToHashSet(
                StringComparer.OrdinalIgnoreCase);
            OrphanCutoff = deleteBeforeUtcExclusive;
            return Task.FromResult(OrphanDeleteCount);
        }
    }

    private sealed class MemoryRepository(
        IEnumerable<ScreenshotRecord> seed) : IScreenshotRecordRepository
    {
        private readonly Dictionary<string, ScreenshotRecord> values =
            seed.ToDictionary(record => record.Id, StringComparer.Ordinal);

        public void Add(ScreenshotRecord record) => values.Add(record.Id, record);

        public ScreenshotRecord? Get(string id, bool includeDeleted = false) =>
            values.TryGetValue(id, out var record)
            && (includeDeleted || record.DeletedAtUtc is null)
                ? record
                : null;

        public ScreenshotRecordPage Search(ScreenshotRecordQuery query) =>
            throw new NotSupportedException();

        public ScreenshotRecordAggregate GetAggregate(ScreenshotRecordAggregateQuery query) =>
            throw new NotSupportedException();

        public ScreenshotRecordStats GetStats() => throw new NotSupportedException();

        public IReadOnlyList<ScreenshotRecord> ListDeletedBefore(
            DateTimeOffset deletedBeforeUtcExclusive) => values.Values
                .Where(record => record.DeletedAtUtc < deletedBeforeUtcExclusive)
                .OrderBy(record => record.DeletedAtUtc)
                .ThenBy(record => record.Id, StringComparer.Ordinal)
                .ToArray();

        public IReadOnlySet<string> ListReferencedAssetPaths() => values.Values
            .SelectMany(record => new[]
            {
                record.OriginalImagePath,
                record.RenderedImagePath,
                record.ThumbnailPath,
                record.TranslatedImagePath,
            })
            .Where(path => path is not null)
            .Cast<string>()
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        public bool SetFavorite(
            string id,
            bool isFavorite,
            DateTimeOffset updatedAtUtc) => throw new NotSupportedException();

        public bool SoftDelete(string id, DateTimeOffset deletedAtUtc) =>
            throw new NotSupportedException();

        public bool PurgeDeleted(
            string id,
            DateTimeOffset deletedBeforeUtcExclusive)
        {
            var record = Get(id, includeDeleted: true);
            return record?.DeletedAtUtc < deletedBeforeUtcExclusive
                && values.Remove(id);
        }

        public bool ReplaceOcrAndInvalidateTransforms(
            string id,
            string text,
            DateTimeOffset updatedAtUtc) => throw new NotSupportedException();

        public bool UpdateTransform(
            string id,
            ScreenshotTransformOperation operation,
            string text,
            DateTimeOffset updatedAtUtc,
            string? translatedImagePath = null) => throw new NotSupportedException();
    }
}
