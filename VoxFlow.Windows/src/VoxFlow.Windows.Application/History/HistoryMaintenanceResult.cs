namespace VoxFlow.Windows.Application.History;

public sealed record HistoryMaintenanceResult(
    bool WasWritten,
    int PrunedCount);
