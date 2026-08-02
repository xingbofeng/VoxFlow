using System.Text.Json;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

/// <summary>
/// Persists the non-terminal portion of an Agent Compose run. It is created
/// when the foreground target is frozen, before microphone capture starts, so
/// an interrupted recording still has one recoverable workflow record.
/// Completion output/trace persistence is intentionally owned by the later
/// output coordinator rather than by this acquisition tracker.
/// </summary>
public sealed class AgentComposeWorkflowTracker
{
    private readonly object gate = new();
    private readonly WorkflowTaskService tasks;
    private readonly HistoryRetentionPolicy retentionPolicy;
    private readonly TimeProvider timeProvider;
    private readonly Func<AsrSelection?> selectedAsr;
    private WorkflowTaskRecord? current;
    private AgentContextSnapshot? context;
    private readonly List<AgentActionEvent> events = [];

    public AgentComposeWorkflowTracker(
        WorkflowTaskService tasks,
        HistoryRetentionPolicy retentionPolicy,
        TimeProvider timeProvider,
        Func<AsrSelection?> selectedAsr)
    {
        this.tasks = tasks ?? throw new ArgumentNullException(nameof(tasks));
        this.retentionPolicy = retentionPolicy ?? throw new ArgumentNullException(nameof(retentionPolicy));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        this.selectedAsr = selectedAsr ?? throw new ArgumentNullException(nameof(selectedAsr));
    }

    public string? TaskId
    {
        get { lock (gate) return current?.Id; }
    }

    public string Start(ForegroundTargetSnapshot target)
    {
        ArgumentNullException.ThrowIfNull(target);
        lock (gate)
        {
            if (current is not null && !current.IsTerminal)
            {
                throw new InvalidOperationException("An Agent workflow is already active.");
            }

            var selection = selectedAsr();
            var now = Now();
            current = new WorkflowTaskRecord(
                Guid.NewGuid().ToString("N"),
                WorkflowTaskKind.AgentCompose,
                WorkflowTaskStage.Recording,
                WorkflowTaskStatus.Running,
                Guid.NewGuid(),
                rawText: null,
                partialText: null,
                finalText: null,
                providerId: selection?.Provider.ToString(),
                model: selection?.QwenVariant?.DisplayName(),
                targetJson: JsonSerializer.SerializeToElement(target, DomainJson.Options),
                contextJson: null,
                traceJson: null,
                outputJson: null,
                failureJson: null,
                warningsJson: null,
                createdAtUnixMs: now,
                updatedAtUnixMs: now,
                completedAtUnixMs: null);
            tasks.Create(current, retentionPolicy);
            return current.Id;
        }
    }

    public void RecordAsrFinal(string voiceInstruction)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(voiceInstruction);
        Update(WorkflowTaskStage.Transcribing, task => Copy(
            task,
            stage: WorkflowTaskStage.Transcribing,
            rawText: voiceInstruction.Trim()));
    }

    public void BeginContextCollection() =>
        Update(WorkflowTaskStage.CollectingContext, task => Copy(
            task,
            stage: WorkflowTaskStage.CollectingContext));

    public void RecordContext(AgentContextSnapshot context)
    {
        ArgumentNullException.ThrowIfNull(context);
        this.context = context;
        Update(WorkflowTaskStage.Processing, task => Copy(
            task,
            stage: WorkflowTaskStage.Processing,
            contextJson: JsonSerializer.SerializeToElement(context, DomainJson.Options)));
    }

    public void RecordSidecarEvent(BuiltinAgentSidecarEvent runtimeEvent)
    {
        ArgumentNullException.ThrowIfNull(runtimeEvent);
        var stage = runtimeEvent.Event switch
        {
            "toolRequested" when string.Equals(runtimeEvent.ToolCall?.Name, "ask_user_question", StringComparison.Ordinal) => WorkflowTaskStage.WaitingForUser,
            "toolRequested" or "toolProgress" or "toolResolved" => WorkflowTaskStage.Operating,
            "turnCompleted" => WorkflowTaskStage.Outputting,
            _ => WorkflowTaskStage.Processing,
        };
        Update(stage, task => Copy(task, stage: stage));
        var kind = runtimeEvent.Event switch
        {
            "turnStarted" => AgentActionEventKind.TurnStarted,
            "modelDelta" => AgentActionEventKind.ModelDelta,
            "planUpdated" => AgentActionEventKind.PlanUpdated,
            "toolRequested" => AgentActionEventKind.ToolRequested,
            "toolProgress" => AgentActionEventKind.ToolProgress,
            "toolResolved" => AgentActionEventKind.ToolResolved,
            "turnCompleted" => AgentActionEventKind.TurnCompleted,
            "warning" => AgentActionEventKind.Warning,
            "error" => AgentActionEventKind.Error,
            _ => (AgentActionEventKind?)null,
        };
        if (kind is not null)
        {
            lock (gate)
            {
                if (current is not null)
                {
                    var toolName = runtimeEvent.ToolCall?.Name ?? runtimeEvent.ToolName
                        ?? runtimeEvent.Result?.ToolName;
                    events.Add(new AgentActionEvent(
                        Guid.NewGuid().ToString("N"),
                        kind.Value,
                        toolName ?? runtimeEvent.Event,
                        detail: null,
                        timestampUnixMs: Now(),
                        elapsedMs: null,
                        toolName,
                        isFailure: runtimeEvent.Event == "error"
                            || runtimeEvent.Result?.Ok == false));
                }
            }
        }
    }

    public void Complete(
        string? finalText,
        IReadOnlyList<AgentToolResult> toolResults,
        AgentComposeOutputResult output)
    {
        ArgumentNullException.ThrowIfNull(toolResults);
        ArgumentNullException.ThrowIfNull(output);
        lock (gate)
        {
            if (current is null || current.IsTerminal)
            {
                return;
            }
            var now = Now();
            var trace = new AgentActionTrace(
                current.ProviderId ?? "unavailable",
                AgentExecutionMode.BuiltinAgent,
                WorkflowTaskStatus.Completed,
                current.RawText ?? "Agent Compose",
                current.CreatedAtUnixMs,
                screenContext: TraceContext(),
                events: events,
                resultSummary: finalText,
                model: current.Model,
                artifacts: Artifacts(toolResults),
                completedAtUnixMs: now);
            var completed = new WorkflowTaskRecord(
                current.Id,
                current.Kind,
                WorkflowTaskStage.Completed,
                WorkflowTaskStatus.Completed,
                current.Generation,
                current.RawText,
                current.PartialText,
                finalText,
                current.ProviderId,
                current.Model,
                current.TargetJson,
                current.ContextJson,
                JsonSerializer.SerializeToElement(trace, DomainJson.Options),
                JsonSerializer.SerializeToElement(new
                {
                    status = output.Status.ToString(),
                    errorCode = output.SafeErrorCode,
                }, DomainJson.Options),
                current.FailureJson,
                current.WarningsJson,
                current.CreatedAtUnixMs,
                now,
                now);
            if (tasks.TryUpdate(completed, current.Generation, retentionPolicy))
            {
                current = completed;
            }
        }
    }

    public void RecordFailure(string safeCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(safeCode);
        lock (gate)
        {
            if (current is null || current.IsTerminal)
            {
                return;
            }
            var now = Now();
            var failed = Copy(
                current,
                status: WorkflowTaskStatus.Failed,
                failureJson: JsonSerializer.SerializeToElement(
                    new { code = safeCode.Trim() }, DomainJson.Options),
                updatedAtUnixMs: now,
                completedAtUnixMs: now);
            if (tasks.TryUpdate(failed, current.Generation, retentionPolicy))
            {
                current = failed;
            }
        }
    }

    public void RecordCancellation()
    {
        lock (gate)
        {
            if (current is null || current.IsTerminal)
            {
                return;
            }
            var now = Now();
            var cancelled = Copy(
                current,
                status: WorkflowTaskStatus.Cancelled,
                updatedAtUnixMs: now,
                completedAtUnixMs: now);
            if (tasks.TryUpdate(cancelled, current.Generation, retentionPolicy))
            {
                current = cancelled;
            }
        }
    }

    private void Update(
        WorkflowTaskStage expectedStage,
        Func<WorkflowTaskRecord, WorkflowTaskRecord> transform)
    {
        ArgumentNullException.ThrowIfNull(transform);
        lock (gate)
        {
            if (current is null || current.IsTerminal)
            {
                return;
            }
            var updated = transform(current);
            if (updated.Stage != expectedStage)
            {
                throw new InvalidOperationException("The Agent workflow stage did not match its update.");
            }
            updated = Copy(updated, updatedAtUnixMs: Now());
            if (tasks.TryUpdate(updated, current.Generation, retentionPolicy))
            {
                current = updated;
            }
        }
    }

    private long Now() => timeProvider.GetUtcNow().ToUnixTimeMilliseconds();

    private AgentScreenContextMetadata? TraceContext()
    {
        if (context is null)
        {
            return null;
        }
        var sources = new List<string>();
        if (!string.IsNullOrWhiteSpace(context.SelectedText)) sources.Add("selected_text");
        if (!string.IsNullOrWhiteSpace(context.FocusedInputText)) sources.Add("focused_input");
        if (!string.IsNullOrWhiteSpace(context.VisibleText)) sources.Add("visible_text");
        if (!string.IsNullOrWhiteSpace(context.OcrText)) sources.Add("ocr_text");
        return new AgentScreenContextMetadata(
            context.Target.ProcessName,
            context.Target.ProcessName,
            context.Target.WindowTitle,
            sources,
            context.Warnings,
            context.Target.CapturedAtUnixMs);
    }

    private static IReadOnlyList<AgentArtifact> Artifacts(
        IReadOnlyList<AgentToolResult> toolResults)
    {
        var artifacts = new List<AgentArtifact>();
        foreach (var result in toolResults.Where(result => result.Ok
            && result.ToolName is "write_file" or "edit_file" or "notebook_edit"))
        {
            if (result.Result is not { ValueKind: JsonValueKind.Object } value
                || !value.TryGetProperty("path", out var path)
                || string.IsNullOrWhiteSpace(path.GetString()))
            {
                continue;
            }
            artifacts.Add(new AgentArtifact(
                $"artifact-{artifacts.Count + 1}",
                AgentArtifactKind.File,
                path.GetString()!,
                summary: null,
                updatedAtUnixMs: null));
        }
        return artifacts;
    }

    private static WorkflowTaskRecord Copy(
        WorkflowTaskRecord task,
        WorkflowTaskStage? stage = null,
        WorkflowTaskStatus? status = null,
        string? rawText = null,
        JsonElement? contextJson = null,
        JsonElement? failureJson = null,
        long? updatedAtUnixMs = null,
        long? completedAtUnixMs = null) => new(
        task.Id,
        task.Kind,
        stage ?? task.Stage,
        status ?? task.Status,
        task.Generation,
        rawText ?? task.RawText,
        task.PartialText,
        task.FinalText,
        task.ProviderId,
        task.Model,
        task.TargetJson,
        contextJson ?? task.ContextJson,
        task.TraceJson,
        task.OutputJson,
        failureJson ?? task.FailureJson,
        task.WarningsJson,
        task.CreatedAtUnixMs,
        updatedAtUnixMs ?? task.UpdatedAtUnixMs,
        completedAtUnixMs ?? task.CompletedAtUnixMs);
}
