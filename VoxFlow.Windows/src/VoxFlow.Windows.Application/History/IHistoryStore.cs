namespace VoxFlow.Windows.Application.History;

public interface IHistoryStore
{
    HistoryMaintenanceResult WriteAndPrune(
        HistoryEntry entry,
        DateTimeOffset? deleteBeforeUtcExclusive);

    int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive);

    IReadOnlyList<HistoryEntry> ReadAll();

    int Delete(IReadOnlyCollection<string> ids);

    int Clear();

    bool UpdateFinalText(string id, string finalText);
}
