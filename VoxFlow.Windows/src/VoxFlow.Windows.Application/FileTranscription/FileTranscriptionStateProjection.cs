using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public sealed record FileTranscriptionTaskSummary
{
    public static FileTranscriptionTaskSummary Empty { get; } = new(0, 0, 0, 0, 0);

    public FileTranscriptionTaskSummary(
        int totalCount,
        int queuedCount,
        int runningCount,
        int needsAttentionCount,
        int completedCount)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(totalCount);
        ArgumentOutOfRangeException.ThrowIfNegative(queuedCount);
        ArgumentOutOfRangeException.ThrowIfNegative(runningCount);
        ArgumentOutOfRangeException.ThrowIfNegative(needsAttentionCount);
        ArgumentOutOfRangeException.ThrowIfNegative(completedCount);
        if (queuedCount + runningCount + needsAttentionCount + completedCount > totalCount)
        {
            throw new ArgumentOutOfRangeException(nameof(totalCount));
        }

        TotalCount = totalCount;
        QueuedCount = queuedCount;
        RunningCount = runningCount;
        NeedsAttentionCount = needsAttentionCount;
        CompletedCount = completedCount;
    }

    public int TotalCount { get; }
    public int QueuedCount { get; }
    public int RunningCount { get; }
    public int NeedsAttentionCount { get; }
    public int CompletedCount { get; }
    public int ActiveCount => QueuedCount + RunningCount;
}

public sealed class UpdateFileTranscriptionSummaryCommand(
    FileTranscriptionTaskSummary summary) : IVoxFlowStateCommand
{
    private readonly FileTranscriptionTaskSummary summary = summary
        ?? throw new ArgumentNullException(nameof(summary));

    public StateMutation Apply(VoxFlowState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        return new StateMutation(
            state.WithFileTranscriptionSummary(summary),
            StateChangeKind.FileTranscription);
    }
}

public sealed class FileTranscriptionStateProjection
{
    private readonly IFileTranscriptionJobRepository jobs;
    private readonly VoxFlowStateStore stateStore;

    public FileTranscriptionStateProjection(
        IFileTranscriptionJobRepository jobs,
        VoxFlowStateStore stateStore)
    {
        this.jobs = jobs ?? throw new ArgumentNullException(nameof(jobs));
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
    }

    public FileTranscriptionTaskSummary Refresh()
    {
        var all = jobs.List();
        var summary = new FileTranscriptionTaskSummary(
            all.Count,
            all.Count(job => job.Status == FileTranscriptionJobStatus.Queued),
            all.Count(job => job.Status == FileTranscriptionJobStatus.Running),
            all.Count(job => job.Status is FileTranscriptionJobStatus.Interrupted
                or FileTranscriptionJobStatus.PartiallyFailed
                or FileTranscriptionJobStatus.Failed),
            all.Count(job => job.Status == FileTranscriptionJobStatus.Completed));
        stateStore.Dispatch(new UpdateFileTranscriptionSummaryCommand(summary));
        return summary;
    }
}
