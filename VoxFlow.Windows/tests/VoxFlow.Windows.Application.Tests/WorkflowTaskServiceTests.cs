using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;
using System.Text.Json;
using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class WorkflowTaskServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 11, 8, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(WorkflowTaskKind.SelectionTranslation, WorkflowTaskStatus.PartiallyCompleted)]
    [InlineData(WorkflowTaskKind.SelectionSummary, WorkflowTaskStatus.Completed)]
    [InlineData(WorkflowTaskKind.AgentCompose, WorkflowTaskStatus.Failed)]
    [InlineData(WorkflowTaskKind.AgentCompose, WorkflowTaskStatus.Cancelled)]
    [InlineData(WorkflowTaskKind.AgentCompose, WorkflowTaskStatus.Interrupted)]
    public void Three_kinds_and_every_terminal_outcome_are_persisted_only_once(
        WorkflowTaskKind kind,
        WorkflowTaskStatus terminalStatus)
    {
        var repository = new MemoryWorkflowTaskRepository();
        var service = Service(repository);
        var generation = Guid.NewGuid();
        var started = Task(
            $"{kind}-{terminalStatus}",
            kind,
            InitialStage(kind),
            WorkflowTaskStatus.Running,
            generation,
            createdAt: Ms(Now),
            updatedAt: Ms(Now));
        service.Create(started, HistoryRetentionPolicy.Default);

        var terminalStage = terminalStatus == WorkflowTaskStatus.Completed
            ? WorkflowTaskStage.Completed
            : kind is WorkflowTaskKind.SelectionTranslation
                or WorkflowTaskKind.SelectionSummary
                ? WorkflowTaskStage.Processing
                : WorkflowTaskStage.Recording;
        var terminal = Task(
            started.Id,
            kind,
            terminalStage,
            terminalStatus,
            generation,
            rawText: "原始内容",
            partialText: terminalStatus == WorkflowTaskStatus.PartiallyCompleted
                ? "保留的 partial"
                : null,
            finalText: terminalStatus == WorkflowTaskStatus.Completed
                ? "最终结果"
                : null,
            createdAt: started.CreatedAtUnixMs,
            updatedAt: Ms(Now.AddSeconds(1)),
            completedAt: Ms(Now.AddSeconds(1)));

        Assert.True(service.TryUpdate(
            terminal,
            generation,
            HistoryRetentionPolicy.Default));
        var stored = Assert.IsType<WorkflowTaskRecord>(repository.Get(started.Id));
        Assert.Equal(terminalStatus, stored.Status);
        Assert.Equal(terminal.PartialText, stored.PartialText);
        Assert.Equal(terminal.FinalText, stored.FinalText);
        Assert.False(service.TryUpdate(
            Task(
                started.Id,
                kind,
                terminalStage == WorkflowTaskStage.Completed
                    ? WorkflowTaskStage.Processing
                    : terminalStage,
                WorkflowTaskStatus.Running,
                generation,
                createdAt: started.CreatedAtUnixMs,
                updatedAt: Ms(Now.AddSeconds(2))),
            generation,
            HistoryRetentionPolicy.Default));
        Assert.Equal(1, repository.UpdateCalls);
    }

    [Fact]
    public void Disabled_history_keeps_runtime_state_but_deletes_the_new_task_at_terminal()
    {
        var repository = new MemoryWorkflowTaskRepository();
        var existing = Task(
            "existing-history",
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            Guid.NewGuid(),
            finalText: "用户以前保存的历史",
            createdAt: Ms(Now.AddDays(-2)),
            updatedAt: Ms(Now.AddDays(-2)),
            completedAt: Ms(Now.AddDays(-2)));
        repository.Seed(existing);
        var service = Service(repository);
        var generation = Guid.NewGuid();
        var active = Task(
            "no-history-agent",
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Operating,
            WorkflowTaskStatus.Running,
            generation,
            rawText: "帮我做",
            partialText: "运行所需状态",
            createdAt: Ms(Now),
            updatedAt: Ms(Now));

        service.Create(active, HistoryRetentionPolicy.Disabled);
        Assert.NotNull(repository.Get(active.Id));
        Assert.True(service.TryUpdate(
            Task(
                active.Id,
                active.Kind,
                active.Stage,
                WorkflowTaskStatus.Cancelled,
                generation,
                rawText: active.RawText,
                partialText: "已取消",
                createdAt: active.CreatedAtUnixMs,
                updatedAt: Ms(Now.AddSeconds(1)),
                completedAt: Ms(Now.AddSeconds(1))),
            generation,
            HistoryRetentionPolicy.Disabled));

        Assert.Null(repository.Get(active.Id));
        Assert.NotNull(repository.Get(existing.Id));
    }

    [Fact]
    public void Thirty_day_cleanup_prunes_only_older_terminal_tasks_and_forever_prunes_none()
    {
        var repository = new MemoryWorkflowTaskRepository();
        repository.Seed(
            Completed("too-old", Now.AddDays(-30).AddMilliseconds(-1)),
            Completed("boundary", Now.AddDays(-30)),
            Task(
                "old-active",
                WorkflowTaskKind.AgentCompose,
                WorkflowTaskStage.Processing,
                WorkflowTaskStatus.Running,
                Guid.NewGuid(),
                createdAt: Ms(Now.AddDays(-40)),
                updatedAt: Ms(Now.AddDays(-40))));
        var service = Service(repository);

        service.Create(
            Task(
                "new-active",
                WorkflowTaskKind.SelectionTranslation,
                WorkflowTaskStage.CapturingSelection,
                WorkflowTaskStatus.Running,
                Guid.NewGuid(),
                createdAt: Ms(Now),
                updatedAt: Ms(Now)),
            HistoryRetentionPolicy.Default);

        Assert.Null(repository.Get("too-old"));
        Assert.NotNull(repository.Get("boundary"));
        Assert.NotNull(repository.Get("old-active"));

        repository.Seed(Completed("forever-old", Now.AddYears(-2)));
        service.Create(
            Task(
                "forever-active",
                WorkflowTaskKind.SelectionSummary,
                WorkflowTaskStage.CapturingSelection,
                WorkflowTaskStatus.Running,
                Guid.NewGuid(),
                createdAt: Ms(Now),
                updatedAt: Ms(Now)),
            HistoryRetentionPolicy.Forever);
        Assert.NotNull(repository.Get("forever-old"));
    }

    [Theory]
    [InlineData(HistoryRetentionMode.RetainForDays, true)]
    [InlineData(HistoryRetentionMode.Disabled, false)]
    public void Startup_recovery_preserves_partial_only_when_history_is_retained(
        HistoryRetentionMode mode,
        bool shouldRetainInterrupted)
    {
        var repository = new MemoryWorkflowTaskRepository();
        var active = Task(
            "crashed-agent",
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.WaitingForUser,
            WorkflowTaskStatus.Running,
            Guid.NewGuid(),
            rawText: "语音指令",
            partialText: "等待用户回答",
            createdAt: Ms(Now.AddMinutes(-1)),
            updatedAt: Ms(Now.AddMinutes(-1)));
        repository.Seed(active);
        var service = Service(repository);
        var policy = mode == HistoryRetentionMode.Disabled
            ? HistoryRetentionPolicy.Disabled
            : HistoryRetentionPolicy.Default;

        var result = service.CleanupOnStartup(policy);

        Assert.Equal(1, result.InterruptedCount);
        Assert.Equal(shouldRetainInterrupted ? 0 : 1, result.PrunedCount);
        var stored = repository.Get(active.Id);
        if (shouldRetainInterrupted)
        {
            Assert.Equal(WorkflowTaskStatus.Interrupted, stored?.Status);
            Assert.Equal("等待用户回答", stored?.PartialText);
        }
        else
        {
            Assert.Null(stored);
        }
    }

    [Fact]
    public void Startup_recovery_cleans_only_ephemeral_agent_workspace_directories()
    {
        using var directory = new TemporaryDirectory();
        var sessionsRoot = Path.Combine(directory.Path, "sessions");
        var workspace = Path.Combine(sessionsRoot, "crashed-agent");
        Directory.CreateDirectory(Path.Combine(workspace, "screenshots"));
        Directory.CreateDirectory(Path.Combine(workspace, "tmp"));
        File.WriteAllText(Path.Combine(workspace, "screenshots", "capture.png"), "pixels");
        File.WriteAllText(Path.Combine(workspace, "tmp", "request.json"), "transient");
        File.WriteAllText(Path.Combine(workspace, "result.md"), "artifact");
        var workspaces = new AgentSessionWorkspaceRetentionService(
            new FileSystemAgentSessionWorkspaceStore(sessionsRoot),
            new ControlledTimeProvider(Now));
        var service = new WorkflowTaskService(
            new MemoryWorkflowTaskRepository(),
            new ControlledTimeProvider(Now),
            agentSessionWorkspaces: workspaces);

        var result = service.CleanupOnStartup(HistoryRetentionPolicy.Default);

        Assert.Equal(2, result.PrunedEphemeralDirectoryCount);
        Assert.Equal(0, result.SkippedUnsafeEphemeralCount);
        Assert.False(Directory.Exists(Path.Combine(workspace, "screenshots")));
        Assert.False(Directory.Exists(Path.Combine(workspace, "tmp")));
        Assert.Equal("artifact", File.ReadAllText(Path.Combine(workspace, "result.md")));
    }

    [Fact]
    public void Agent_trace_is_sanitized_before_the_repository_can_observe_it()
    {
        using var trace = JsonDocument.Parse("""
        {
          "schemaVersion": 99,
          "providerId": "fixture-provider",
          "executionMode": "builtinAgent",
          "status": "running",
          "userInstruction": "use sk-task-secret",
          "startedAtUnixMs": 100,
          "artifacts": [
            {
              "id": "artifact-1",
              "kind": "file",
              "path": "C:\\Users\\Alice\\report.md",
              "summary": "safe",
              "updatedAtUnixMs": 100
            }
          ],
          "future": { "authorization": "Bearer future-secret" }
        }
        """);
        var repository = new MemoryWorkflowTaskRepository();
        var service = Service(repository);
        var task = Task(
            "sanitized-agent",
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Processing,
            WorkflowTaskStatus.Running,
            Guid.NewGuid(),
            rawText: "use sk-task-secret",
            traceJson: trace.RootElement,
            createdAt: Ms(Now),
            updatedAt: Ms(Now));

        service.Create(
            task,
            HistoryRetentionPolicy.Default,
            new AgentTraceSanitizationContext(
                knownSecrets: ["sk-task-secret"],
                homeDirectories: [@"C:\Users\Alice"]));

        var stored = Assert.IsType<WorkflowTaskRecord>(repository.Get(task.Id));
        var safeJson = stored.TraceJson?.GetRawText() ?? string.Empty;
        Assert.DoesNotContain("sk-task-secret", safeJson, StringComparison.Ordinal);
        Assert.DoesNotContain("future-secret", safeJson, StringComparison.Ordinal);
        Assert.DoesNotContain(@"C:\Users\Alice", safeJson, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(
            AgentTraceSchema.CurrentVersion,
            stored.TraceJson?.GetProperty("schemaVersion").GetInt32());
    }

    private static WorkflowTaskService Service(MemoryWorkflowTaskRepository repository) =>
        new(repository, new ControlledTimeProvider(Now));

    private static WorkflowTaskStage InitialStage(WorkflowTaskKind kind) => kind switch
    {
        WorkflowTaskKind.SelectionTranslation or WorkflowTaskKind.SelectionSummary =>
            WorkflowTaskStage.Processing,
        WorkflowTaskKind.AgentCompose => WorkflowTaskStage.Recording,
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    private static WorkflowTaskRecord Completed(string id, DateTimeOffset completedAt) =>
        Task(
            id,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            Guid.NewGuid(),
            finalText: "历史结果",
            createdAt: Ms(completedAt),
            updatedAt: Ms(completedAt),
            completedAt: Ms(completedAt));

    private static WorkflowTaskRecord Task(
        string id,
        WorkflowTaskKind kind,
        WorkflowTaskStage stage,
        WorkflowTaskStatus status,
        Guid generation,
        string? rawText = null,
        string? partialText = null,
        string? finalText = null,
        JsonElement? traceJson = null,
        long? createdAt = null,
        long? updatedAt = null,
        long? completedAt = null) => new(
        id,
        kind,
        stage,
        status,
        generation,
        rawText,
        partialText,
        finalText,
        providerId: "fixture-provider",
        model: "fixture-model",
        targetJson: null,
        contextJson: null,
        traceJson,
        outputJson: null,
        failureJson: null,
        warningsJson: null,
        createdAtUnixMs: createdAt ?? Ms(Now),
        updatedAtUnixMs: updatedAt ?? createdAt ?? Ms(Now),
        completedAtUnixMs: completedAt);

    private static long Ms(DateTimeOffset value) => value.ToUnixTimeMilliseconds();

    private sealed class MemoryWorkflowTaskRepository : IWorkflowTaskRepository
    {
        private readonly Dictionary<string, WorkflowTaskRecord> tasks =
            new(StringComparer.Ordinal);

        public int UpdateCalls { get; private set; }

        public void Seed(params WorkflowTaskRecord[] values)
        {
            foreach (var value in values)
            {
                tasks[value.Id] = value;
            }
        }

        public void Create(WorkflowTaskRecord task) => tasks.Add(task.Id, task);

        public WorkflowTaskRecord? Get(string id) =>
            tasks.TryGetValue(id, out var task) ? task : null;

        public WorkflowTaskPage Search(WorkflowTaskQuery query)
        {
            var values = tasks.Values
                .OrderByDescending(task => task.CreatedAtUnixMs)
                .Skip(query.Offset)
                .Take(query.Limit)
                .ToArray();
            return new WorkflowTaskPage(
                values,
                tasks.Count,
                query.Offset,
                query.Limit);
        }

        public bool TryUpdate(WorkflowTaskRecord task, Guid expectedGeneration)
        {
            if (!tasks.TryGetValue(task.Id, out var current)
                || current.IsTerminal
                || current.Generation != expectedGeneration
                || task.Generation != expectedGeneration)
            {
                return false;
            }
            UpdateCalls++;
            tasks[task.Id] = task;
            return true;
        }

        public bool Delete(string id) => tasks.Remove(id);

        public IReadOnlyList<string> ListActiveIds() => tasks.Values
            .Where(task => !task.IsTerminal)
            .Select(task => task.Id)
            .ToArray();

        public int PruneTerminalBefore(long cutoffUnixMs)
        {
            var ids = tasks.Values
                .Where(task => task.IsTerminal
                    && task.CompletedAtUnixMs < cutoffUnixMs)
                .Select(task => task.Id)
                .ToArray();
            foreach (var id in ids)
            {
                tasks.Remove(id);
            }
            return ids.Length;
        }

        public int MarkActiveAsInterrupted(long interruptedAtUnixMs)
        {
            var active = tasks.Values.Where(task => !task.IsTerminal).ToArray();
            foreach (var task in active)
            {
                tasks[task.Id] = CopyAsInterrupted(task, interruptedAtUnixMs);
            }
            return active.Length;
        }

        private static WorkflowTaskRecord CopyAsInterrupted(
            WorkflowTaskRecord task,
            long interruptedAtUnixMs) => new(
            task.Id,
            task.Kind,
            task.Stage,
            WorkflowTaskStatus.Interrupted,
            task.Generation,
            task.RawText,
            task.PartialText,
            task.FinalText,
            task.ProviderId,
            task.Model,
            task.TargetJson,
            task.ContextJson,
            task.TraceJson,
            task.OutputJson,
            task.FailureJson,
            task.WarningsJson,
            task.CreatedAtUnixMs,
            interruptedAtUnixMs,
            interruptedAtUnixMs);
    }
}
