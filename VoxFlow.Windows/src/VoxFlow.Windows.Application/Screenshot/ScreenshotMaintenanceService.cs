using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Screenshot;

public sealed record ScreenshotMaintenanceResult(
    int ExpiredRecordCount,
    int PurgedRecordCount,
    int DeferredRecordCount,
    int DeletedManagedFileCount,
    int DeletedOrphanFileCount,
    bool HadFailure);

/// <summary>
/// Applies screenshot retention without ever inspecting files outside the
/// application-managed screenshot asset store. A soft-deleted row remains the
/// retry marker until every one of its managed assets is gone.
/// </summary>
public sealed class ScreenshotMaintenanceService
{
    public static readonly TimeSpan OrphanSafetyPeriod = TimeSpan.FromHours(24);

    private readonly IScreenshotRecordRepository records;
    private readonly IScreenshotAssetStore assets;
    private readonly TimeProvider timeProvider;

    public ScreenshotMaintenanceService(
        IScreenshotRecordRepository records,
        IScreenshotAssetStore assets,
        TimeProvider timeProvider)
    {
        this.records = records ?? throw new ArgumentNullException(nameof(records));
        this.assets = assets ?? throw new ArgumentNullException(nameof(assets));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public async Task<ScreenshotMaintenanceResult> CleanupOnStartupAsync(
        HistoryRetentionPolicy retentionPolicy,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(retentionPolicy);
        cancellationToken.ThrowIfCancellationRequested();
        var now = timeProvider.GetUtcNow().ToUniversalTime();
        var retentionCutoff = RetentionCutoff(retentionPolicy, now);
        IReadOnlyList<ScreenshotRecord> expired = [];
        var hadFailure = false;
        if (retentionCutoff is { } cutoff)
        {
            try
            {
                expired = records.ListDeletedBefore(cutoff);
            }
            catch
            {
                hadFailure = true;
            }
        }

        var purged = 0;
        var deferred = 0;
        var deletedManagedFiles = 0;
        foreach (var record in expired)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ScreenshotAssetDeleteResult deletion;
            try
            {
                deletion = await assets.DeleteAsync(
                    AssetsFor(record),
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                deferred++;
                hadFailure = true;
                continue;
            }

            deletedManagedFiles += deletion.DeletedCount;
            if (!deletion.IsComplete)
            {
                deferred++;
                hadFailure = true;
                continue;
            }

            try
            {
                if (records.PurgeDeleted(record.Id, retentionCutoff!.Value))
                {
                    purged++;
                }
                else
                {
                    deferred++;
                    hadFailure = true;
                }
            }
            catch
            {
                deferred++;
                hadFailure = true;
            }
        }

        IReadOnlySet<string> referenced;
        try
        {
            referenced = records.ListReferencedAssetPaths();
        }
        catch
        {
            return new ScreenshotMaintenanceResult(
                expired.Count,
                purged,
                deferred,
                deletedManagedFiles,
                DeletedOrphanFileCount: 0,
                HadFailure: true);
        }

        var deletedOrphans = 0;
        try
        {
            deletedOrphans = await assets.CleanupOrphansAsync(
                referenced,
                now - OrphanSafetyPeriod,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            hadFailure = true;
        }

        return new ScreenshotMaintenanceResult(
            expired.Count,
            purged,
            deferred,
            deletedManagedFiles,
            deletedOrphans,
            hadFailure);
    }

    private static DateTimeOffset? RetentionCutoff(
        HistoryRetentionPolicy policy,
        DateTimeOffset now) => policy.Mode switch
        {
            HistoryRetentionMode.Disabled => now,
            HistoryRetentionMode.RetainForDays => now.AddDays(-policy.Days!.Value),
            HistoryRetentionMode.Forever => null,
            _ => throw new ArgumentOutOfRangeException(nameof(policy)),
        };

    private static ScreenshotAssetSet AssetsFor(ScreenshotRecord record) => new(
        record.OriginalImagePath,
        record.RenderedImagePath,
        record.ThumbnailPath,
        record.TranslatedImagePath,
        record.FileSizeBytes);
}
