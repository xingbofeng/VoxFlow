namespace VoxFlow.Windows.Application.History;

public interface IHistoryStore
{
    HistoryMaintenanceResult WriteAndPrune(
        HistoryEntry entry,
        DateTimeOffset? deleteBeforeUtcExclusive);

    int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive);

    IReadOnlyList<HistoryEntry> ReadAll();

    /// <summary>Searches retained dictation history. Implementations backed by
    /// SQL must bind the query instead of interpolating it.</summary>
    IReadOnlyList<HistoryEntry> Search(
        string query,
        DateTimeOffset? dateFromUtc,
        DateTimeOffset? dateToUtc,
        int limit)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(query);
        if (limit is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(limit));
        return ReadAll()
            .Where(entry => (dateFromUtc is null || entry.CreatedAtUtc >= dateFromUtc)
                && (dateToUtc is null || entry.CreatedAtUtc <= dateToUtc)
                && (entry.RawText.Contains(query, StringComparison.OrdinalIgnoreCase)
                    || entry.FinalText.Contains(query, StringComparison.OrdinalIgnoreCase)))
            .Take(limit)
            .ToArray();
    }

    int Delete(IReadOnlyCollection<string> ids);

    int Clear();

    bool UpdateFinalText(string id, string finalText);
}
