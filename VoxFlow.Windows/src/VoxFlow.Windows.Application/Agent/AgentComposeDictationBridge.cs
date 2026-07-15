using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public interface IAgentComposeTargetSnapshotProvider
{
    ForegroundTargetSnapshot? Capture();
}

/// <summary>
/// Captures the frozen foreground target at the same lifecycle point as
/// dictation's output guard, then reads untrusted desktop context in parallel
/// with recording. No UI Automation result can alter the voice instruction.
/// </summary>
public sealed class AgentComposeContextCapture : IDictationTargetCapture
{
    private readonly IAgentComposeTargetSnapshotProvider targets;
    private readonly AgentContextPipeline pipeline;
    private readonly AgentComposeWorkflowTracker? workflow;
    private readonly Action? readingWindowStarted;
    private readonly Func<string, string>? workspaceForTask;
    private Task<AgentContextSnapshot>? capture;
    private string? taskId;

    public AgentComposeContextCapture(
        IAgentComposeTargetSnapshotProvider targets,
        AgentContextPipeline pipeline,
        AgentComposeWorkflowTracker? workflow = null,
        Action? readingWindowStarted = null,
        Func<string, string>? workspaceForTask = null)
    {
        this.targets = targets ?? throw new ArgumentNullException(nameof(targets));
        this.pipeline = pipeline ?? throw new ArgumentNullException(nameof(pipeline));
        this.workflow = workflow;
        this.readingWindowStarted = readingWindowStarted;
        this.workspaceForTask = workspaceForTask;
    }

    public string TaskId => taskId ?? throw new InvalidOperationException("Agent context was not captured before its task id was requested.");

    public void CaptureOriginalTarget()
    {
        var target = targets.Capture()
            ?? throw new InvalidOperationException("The Agent target is unavailable.");
        taskId = workflow?.Start(target) ?? Guid.NewGuid().ToString("N");
        readingWindowStarted?.Invoke();
        capture = workspaceForTask is { } workspace
            ? pipeline.CaptureAsync(target, workspace(taskId), CancellationToken.None)
            : pipeline.CaptureAsync(target, CancellationToken.None);
    }

    public Task<AgentContextSnapshot> GetAsync(CancellationToken cancellationToken)
    {
        var task = capture ?? throw new InvalidOperationException("Agent context was not captured before recording.");
        return task.WaitAsync(cancellationToken);
    }
}

/// <summary>
/// Dictation post-processor for Agent Compose. It is invoked only after the
/// existing ASR lifecycle has produced a final (or its timeout fallback), so
/// partial ASR text can never start a sidecar run.
/// </summary>
public sealed class AgentComposeDictationPostProcessor : IDictationTextPostProcessor,
    IDictationTextPostProcessorFailurePolicy
{
    private readonly AgentComposeContextCapture context;
    private readonly IAgentComposeExecutionService execution;
    private readonly Func<string, string> workspaceForTask;
    private readonly IHistoryStore? history;
    private readonly Action<BuiltinAgentSidecarEvent>? eventSink;
    private readonly AgentComposeOutputCoordinator output;
    private readonly AgentComposeWorkflowTracker? workflow;
    private readonly AgentSessionWorkspaceRetentionService? sessionWorkspaces;

    public AgentComposeDictationPostProcessor(
        AgentComposeContextCapture context,
        IAgentComposeExecutionService execution,
        Func<string, string> workspaceForTask,
        IHistoryStore? history = null,
        Action<BuiltinAgentSidecarEvent>? eventSink = null,
        AgentComposeOutputCoordinator? output = null,
        AgentComposeWorkflowTracker? workflow = null,
        AgentSessionWorkspaceRetentionService? sessionWorkspaces = null)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.execution = execution ?? throw new ArgumentNullException(nameof(execution));
        this.workspaceForTask = workspaceForTask ?? throw new ArgumentNullException(nameof(workspaceForTask));
        this.history = history;
        this.eventSink = eventSink;
        this.output = output ?? new AgentComposeOutputCoordinator(
            new NoopClipboard(), new NoopSummary());
        this.workflow = workflow;
        this.sessionWorkspaces = sessionWorkspaces;
    }

    public bool UseAuthoritativeTextOnFailure => false;

    public async ValueTask<string> ProcessAsync(
        string text,
        IProgress<string> streamingProgress,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        ArgumentNullException.ThrowIfNull(streamingProgress);
        workflow?.RecordAsrFinal(text);
        workflow?.BeginContextCollection();
        var taskId = context.TaskId;
        try
        {
            return await ProcessTaskAsync(
                taskId,
                text,
                streamingProgress,
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _ = sessionWorkspaces?.CleanupEphemeralArtifactsForSession(taskId);
        }
    }

    private async Task<string> ProcessTaskAsync(
        string taskId,
        string text,
        IProgress<string> streamingProgress,
        CancellationToken cancellationToken)
    {
        var workspace = workspaceForTask(taskId);
        Directory.CreateDirectory(workspace);
        AgentContextSnapshot contextSnapshot;
        try
        {
            contextSnapshot = await context.GetAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            workflow?.RecordCancellation();
            throw;
        }
        catch
        {
            workflow?.RecordFailure("agent_context_failed");
            throw;
        }
        workflow?.RecordContext(contextSnapshot);
        string? finalText = null;
        var toolResults = new List<AgentToolResult>();
        streamingProgress.Report("Agent is processing your request.");
        var outcome = await execution.ExecuteWithBuiltinToolsAsync(
            taskId,
            text,
            contextSnapshot,
            workspace,
            history,
            runtimeEvent =>
            {
                eventSink?.Invoke(runtimeEvent);
                workflow?.RecordSidecarEvent(runtimeEvent);
                if (runtimeEvent.Event == "modelDelta" && !string.IsNullOrWhiteSpace(runtimeEvent.Text))
                {
                    streamingProgress.Report(runtimeEvent.Text);
                }
                if (runtimeEvent.Event == "turnCompleted")
                {
                    finalText = runtimeEvent.Summary;
                }
                if (runtimeEvent.Event == "toolResolved" && runtimeEvent.Result is { } result)
                {
                    toolResults.Add(result);
                }
                return Task.CompletedTask;
            },
            cancellationToken).ConfigureAwait(false);
        if (!outcome.Succeeded)
        {
            if (cancellationToken.IsCancellationRequested
                || string.Equals(
                    outcome.SidecarOutcome?.SafeFailureCode,
                    "cancelled",
                    StringComparison.Ordinal))
            {
                workflow?.RecordCancellation();
                throw new OperationCanceledException(cancellationToken);
            }
            workflow?.RecordFailure("agent_compose_failed");
            throw new InvalidOperationException("agent_compose_failed");
        }
        var outputResult = output.Complete(finalText, toolResults);
        if (outputResult.Status is AgentComposeOutputStatus.CopyFailed or AgentComposeOutputStatus.Failed)
        {
            workflow?.RecordFailure(outputResult.SafeErrorCode ?? "agent_compose_output_failed");
            throw new InvalidOperationException(outputResult.SafeErrorCode ?? "agent_compose_output_failed");
        }
        workflow?.Complete(finalText, toolResults, outputResult);
        // The final output has already been copied or presented by the Agent
        // coordinator. The dedicated Agent output implementation discards this
        // value, so the regular dictation injector can never paste it into the
        // foreground application.
        return finalText ?? "Agent completed.";
    }

    private sealed class NoopClipboard : IAgentOutputClipboard
    {
        public bool TryCopy(string text) => false;
    }

    private sealed class NoopSummary : IAgentOutputSummaryPresenter
    {
        public void ShowSummary(string? text) { }
    }
}
