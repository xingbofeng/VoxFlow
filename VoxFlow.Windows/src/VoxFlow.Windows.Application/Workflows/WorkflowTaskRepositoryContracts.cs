using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Workflows;

public sealed class WorkflowTaskQuery
{
    public WorkflowTaskQuery(
        string? searchText,
        WorkflowTaskKind? kind,
        int offset,
        int limit)
    {
        if (kind is not null && !Enum.IsDefined(kind.Value))
        {
            throw new ArgumentOutOfRangeException(nameof(kind), kind, null);
        }
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        if (limit is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(limit));
        }

        SearchText = string.IsNullOrWhiteSpace(searchText)
            ? null
            : searchText.Trim();
        Kind = kind;
        Offset = offset;
        Limit = limit;
    }

    public string? SearchText { get; }

    public WorkflowTaskKind? Kind { get; }

    public int Offset { get; }

    public int Limit { get; }
}

public sealed record WorkflowTaskPage(
    IReadOnlyList<WorkflowTaskRecord> Items,
    int TotalCount,
    int Offset,
    int Limit);

public interface IWorkflowTaskRepository
{
    void Create(WorkflowTaskRecord task);

    WorkflowTaskRecord? Get(string id);

    WorkflowTaskPage Search(WorkflowTaskQuery query);

    bool TryUpdate(WorkflowTaskRecord task, Guid expectedGeneration);

    bool Delete(string id);

    IReadOnlyList<string> ListActiveIds();

    int PruneTerminalBefore(long cutoffUnixMs);

    int MarkActiveAsInterrupted(long interruptedAtUnixMs);
}
