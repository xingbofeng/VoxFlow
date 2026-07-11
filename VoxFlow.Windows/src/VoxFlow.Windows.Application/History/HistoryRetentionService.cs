using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.History;

public sealed class HistoryRetentionService
{
    private static readonly HistoryMaintenanceResult NoChanges = new(false, 0);

    private readonly IHistoryStore store;
    private readonly TimeProvider timeProvider;

    public HistoryRetentionService(IHistoryStore store, TimeProvider timeProvider)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public HistoryMaintenanceResult Record(
        HistoryEntry entry,
        HistoryRetentionPolicy policy)
    {
        ArgumentNullException.ThrowIfNull(entry);
        ArgumentNullException.ThrowIfNull(policy);

        return policy.Mode switch
        {
            HistoryRetentionMode.Disabled => NoChanges,
            HistoryRetentionMode.Forever => store.WriteAndPrune(entry, null),
            HistoryRetentionMode.RetainForDays => store.WriteAndPrune(
                entry,
                RetentionCutoff(policy)),
            _ => throw new ArgumentOutOfRangeException(nameof(policy)),
        };
    }

    public HistoryMaintenanceResult CleanupOnStartup(HistoryRetentionPolicy policy)
    {
        ArgumentNullException.ThrowIfNull(policy);

        return policy.Mode switch
        {
            HistoryRetentionMode.Disabled or HistoryRetentionMode.Forever => NoChanges,
            HistoryRetentionMode.RetainForDays => new HistoryMaintenanceResult(
                false,
                store.PruneBefore(RetentionCutoff(policy))),
            _ => throw new ArgumentOutOfRangeException(nameof(policy)),
        };
    }

    private DateTimeOffset RetentionCutoff(HistoryRetentionPolicy policy) =>
        timeProvider.GetUtcNow().AddDays(-policy.Days!.Value);
}
