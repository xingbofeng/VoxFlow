using VoxFlow.Windows.Application.History;

namespace VoxFlow.Windows.App.Home;

internal sealed class EmptyHistoryStore : IHistoryStore
{
    public HistoryMaintenanceResult WriteAndPrune(
        HistoryEntry entry,
        DateTimeOffset? deleteBeforeUtcExclusive) =>
        new(false, 0);

    public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) => 0;

    public IReadOnlyList<HistoryEntry> ReadAll() => [];

    public int Delete(IReadOnlyCollection<string> ids) => 0;

    public int Clear() => 0;

    public bool UpdateFinalText(string id, string finalText) => false;
}
