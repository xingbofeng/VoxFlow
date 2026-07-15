using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentComposeWorkflowTrackerTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 13, 8, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Freezes_target_before_recording_and_advances_asr_context_and_tool_stages()
    {
        var repository = new MemoryRepository();
        var tracker = Create(repository);
        var id = tracker.Start(Target());

        var recording = Assert.IsType<WorkflowTaskRecord>(repository.Get(id));
        Assert.Equal(WorkflowTaskStage.Recording, recording.Stage);
        Assert.Equal(WorkflowTaskStatus.Running, recording.Status);
        Assert.Equal("Qwen", recording.ProviderId);
        Assert.Equal("Qwen 0.6B", recording.Model);
        Assert.Equal("notepad.exe", recording.TargetJson?.GetProperty("processName").GetString());

        tracker.RecordAsrFinal("draft a reply");
        Assert.Equal(WorkflowTaskStage.Transcribing, repository.Get(id)?.Stage);
        Assert.Equal("draft a reply", repository.Get(id)?.RawText);

        tracker.BeginContextCollection();
        Assert.Equal(WorkflowTaskStage.CollectingContext, repository.Get(id)?.Stage);
        tracker.RecordContext(new AgentContextSnapshot(Target(), "selected text", ["context_timeout"]));
        var processing = Assert.IsType<WorkflowTaskRecord>(repository.Get(id));
        Assert.Equal(WorkflowTaskStage.Processing, processing.Stage);
        Assert.Equal("selected text", processing.ContextJson?.GetProperty("selectedText").GetString());

        tracker.RecordSidecarEvent(new BuiltinAgentSidecarEvent(
            "toolRequested",
            toolCall: new AgentToolCall("question-1", "ask_user_question", JsonSerializer.SerializeToElement(new { questions = Array.Empty<object>() }))));
        Assert.Equal(WorkflowTaskStage.WaitingForUser, repository.Get(id)?.Stage);
        tracker.RecordSidecarEvent(new BuiltinAgentSidecarEvent("toolResolved"));
        Assert.Equal(WorkflowTaskStage.Operating, repository.Get(id)?.Stage);
        tracker.RecordSidecarEvent(new BuiltinAgentSidecarEvent("turnCompleted"));
        Assert.Equal(WorkflowTaskStage.Outputting, repository.Get(id)?.Stage);
    }

    [Fact]
    public void Persists_a_safe_terminal_failure_without_exception_text()
    {
        var repository = new MemoryRepository();
        var tracker = Create(repository);
        var id = tracker.Start(Target());

        tracker.RecordFailure("agent_compose_failed");

        var failed = Assert.IsType<WorkflowTaskRecord>(repository.Get(id));
        Assert.Equal(WorkflowTaskStatus.Failed, failed.Status);
        Assert.NotNull(failed.CompletedAtUnixMs);
        Assert.Equal("agent_compose_failed", failed.FailureJson?.GetProperty("code").GetString());
    }

    [Fact]
    public void Completion_records_output_trace_and_file_artifacts_without_repeating_desktop_output()
    {
        var repository = new MemoryRepository();
        var tracker = Create(repository);
        var id = tracker.Start(Target());
        tracker.RecordAsrFinal("create report");
        tracker.RecordContext(new AgentContextSnapshot(Target(), null, []));
        tracker.RecordSidecarEvent(new BuiltinAgentSidecarEvent("turnCompleted", summary: "Created report."));

        tracker.Complete(
            "Created report.",
            [AgentToolResult.Success("write_file", JsonSerializer.SerializeToElement(new { path = "report.md" }))],
            new AgentComposeOutputResult(AgentComposeOutputStatus.Summarized));

        var completed = Assert.IsType<WorkflowTaskRecord>(repository.Get(id));
        Assert.Equal(WorkflowTaskStatus.Completed, completed.Status);
        Assert.Equal(WorkflowTaskStage.Completed, completed.Stage);
        Assert.Equal("Created report.", completed.FinalText);
        Assert.Equal("Summarized", completed.OutputJson?.GetProperty("status").GetString());
        Assert.Equal("report.md", completed.TraceJson?.GetProperty("artifacts")[0].GetProperty("path").GetString());
    }

    private static AgentComposeWorkflowTracker Create(MemoryRepository repository) => new(
        new WorkflowTaskService(repository, new ControlledTimeProvider(Now)),
        HistoryRetentionPolicy.Default,
        new ControlledTimeProvider(Now),
        () => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B));

    private static ForegroundTargetSnapshot Target() => new(
        1, 2, "notepad.exe", "draft", new WindowBounds(0, 0, 20, 20),
        ProcessIntegrityLevel.Medium, [1], 1);

    private sealed class MemoryRepository : IWorkflowTaskRepository
    {
        private readonly Dictionary<string, WorkflowTaskRecord> tasks = new(StringComparer.Ordinal);

        public void Create(WorkflowTaskRecord task) => tasks.Add(task.Id, task);

        public WorkflowTaskRecord? Get(string id) => tasks.GetValueOrDefault(id);

        public WorkflowTaskPage Search(WorkflowTaskQuery query) => new([], 0, query.Offset, query.Limit);

        public bool TryUpdate(WorkflowTaskRecord task, Guid expectedGeneration)
        {
            if (!tasks.TryGetValue(task.Id, out var current)
                || current.IsTerminal
                || current.Generation != expectedGeneration)
            {
                return false;
            }
            tasks[task.Id] = task;
            return true;
        }

        public bool Delete(string id) => tasks.Remove(id);

        public IReadOnlyList<string> ListActiveIds() => tasks.Values
            .Where(task => !task.IsTerminal).Select(task => task.Id).ToArray();

        public int PruneTerminalBefore(long cutoffUnixMs) => 0;

        public int MarkActiveAsInterrupted(long interruptedAtUnixMs) => 0;
    }
}
