using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Application.Agent;
using System.Text.Json;

namespace VoxFlow.Windows.Application.Workflows;

public sealed record WorkflowTaskCleanupResult(
    int InterruptedCount,
    int PrunedCount,
    int PrunedSessionCount = 0,
    int SkippedUnsafeSessionCount = 0,
    int PrunedEphemeralDirectoryCount = 0,
    int SkippedUnsafeEphemeralCount = 0);

/// <summary>
/// Centralizes workflow task persistence and the P1 history-retention policy.
/// Disabled history still keeps an active task long enough to coordinate its
/// generation, but removes that task as soon as it reaches a terminal state.
/// </summary>
public sealed class WorkflowTaskService
{
    private readonly IWorkflowTaskRepository repository;
    private readonly TimeProvider timeProvider;
    private readonly AgentTraceSanitizer traceSanitizer;
    private readonly AgentSessionWorkspaceRetentionService? agentSessionWorkspaces;

    public WorkflowTaskService(
        IWorkflowTaskRepository repository,
        TimeProvider timeProvider,
        AgentTraceSanitizer? traceSanitizer = null,
        AgentSessionWorkspaceRetentionService? agentSessionWorkspaces = null)
    {
        this.repository = repository
            ?? throw new ArgumentNullException(nameof(repository));
        this.timeProvider = timeProvider
            ?? throw new ArgumentNullException(nameof(timeProvider));
        this.traceSanitizer = traceSanitizer ?? new AgentTraceSanitizer();
        this.agentSessionWorkspaces = agentSessionWorkspaces;
    }

    public void Create(
        WorkflowTaskRecord task,
        HistoryRetentionPolicy retentionPolicy,
        AgentTraceSanitizationContext? traceContext = null)
    {
        ArgumentNullException.ThrowIfNull(task);
        ArgumentNullException.ThrowIfNull(retentionPolicy);
        var safeTask = PrepareForPersistence(task, traceContext);
        repository.Create(safeTask);
        MaintainAfterWrite(safeTask, retentionPolicy);
    }

    public bool TryUpdate(
        WorkflowTaskRecord task,
        Guid expectedGeneration,
        HistoryRetentionPolicy retentionPolicy,
        AgentTraceSanitizationContext? traceContext = null)
    {
        ArgumentNullException.ThrowIfNull(task);
        ArgumentNullException.ThrowIfNull(retentionPolicy);
        var safeTask = PrepareForPersistence(task, traceContext);
        if (!repository.TryUpdate(safeTask, expectedGeneration))
        {
            return false;
        }

        MaintainAfterWrite(safeTask, retentionPolicy);
        return true;
    }

    public WorkflowTaskCleanupResult CleanupOnStartup(
        HistoryRetentionPolicy retentionPolicy)
    {
        ArgumentNullException.ThrowIfNull(retentionPolicy);
        var activeIds = repository.ListActiveIds();
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        var interrupted = repository.MarkActiveAsInterrupted(now);
        var pruned = retentionPolicy.Mode switch
        {
            HistoryRetentionMode.Disabled => DeleteRecovered(activeIds),
            HistoryRetentionMode.RetainForDays => repository.PruneTerminalBefore(
                Cutoff(retentionPolicy)),
            HistoryRetentionMode.Forever => 0,
            _ => throw new ArgumentOutOfRangeException(nameof(retentionPolicy)),
        };
        var sessionCleanup = agentSessionWorkspaces?.CleanupExpired();
        var ephemeralCleanup = agentSessionWorkspaces?.CleanupEphemeralArtifacts();
        return new WorkflowTaskCleanupResult(
            interrupted,
            pruned,
            sessionCleanup?.DeletedCount ?? 0,
            sessionCleanup?.SkippedUnsafeCount ?? 0,
            ephemeralCleanup?.DeletedDirectoryCount ?? 0,
            ephemeralCleanup?.SkippedUnsafeCount ?? 0);
    }

    private void MaintainAfterWrite(
        WorkflowTaskRecord task,
        HistoryRetentionPolicy retentionPolicy)
    {
        switch (retentionPolicy.Mode)
        {
            case HistoryRetentionMode.Disabled:
                if (task.IsTerminal)
                {
                    _ = repository.Delete(task.Id);
                }
                break;
            case HistoryRetentionMode.RetainForDays:
                _ = repository.PruneTerminalBefore(Cutoff(retentionPolicy));
                break;
            case HistoryRetentionMode.Forever:
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(retentionPolicy));
        }
    }

    private int DeleteRecovered(IReadOnlyList<string> activeIds)
    {
        var deleted = 0;
        foreach (var id in activeIds.Distinct(StringComparer.Ordinal))
        {
            if (repository.Delete(id))
            {
                deleted++;
            }
        }
        return deleted;
    }

    private WorkflowTaskRecord PrepareForPersistence(
        WorkflowTaskRecord task,
        AgentTraceSanitizationContext? traceContext)
    {
        if (task.Kind != WorkflowTaskKind.AgentCompose || task.TraceJson is null)
        {
            return task;
        }

        var sanitized = traceSanitizer.Sanitize(
            task.TraceJson.Value,
            traceContext?.KnownSecrets,
            traceContext?.HomeDirectories);
        var safeTrace = JsonSerializer.SerializeToElement(
            sanitized.Trace,
            DomainJson.Options);
        return new WorkflowTaskRecord(
            task.Id,
            task.Kind,
            task.Stage,
            task.Status,
            task.Generation,
            task.RawText,
            task.PartialText,
            task.FinalText,
            task.ProviderId,
            task.Model,
            task.TargetJson,
            task.ContextJson,
            safeTrace,
            task.OutputJson,
            task.FailureJson,
            task.WarningsJson,
            task.CreatedAtUnixMs,
            task.UpdatedAtUnixMs,
            task.CompletedAtUnixMs);
    }

    private long Cutoff(HistoryRetentionPolicy retentionPolicy) =>
        timeProvider.GetUtcNow()
            .AddDays(-retentionPolicy.Days!.Value)
            .ToUnixTimeMilliseconds();
}
