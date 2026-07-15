using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class UnifiedHistoryQueryServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 11, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Dictation_workflow_and_file_summaries_merge_in_one_stable_newest_first_order()
    {
        var service = Service(
            dictations:
            [
                Dictation("dictation", Now.AddMinutes(-3)),
            ],
            workflows:
            [
                Workflow("workflow", Now.AddMinutes(-1)),
            ],
            files:
            [
                FileJob("file", Now.AddMinutes(-2)),
            ]);

        var all = service.ReadAll();

        Assert.Equal(
            new[] { "workflow:workflow", "file:file", "dictation" },
            all.Select(entry => entry.Id));
        Assert.Equal(
            new[]
            {
                UnifiedHistoryKind.SelectionSummary,
                UnifiedHistoryKind.FileTranscription,
                UnifiedHistoryKind.Dictation,
            },
            all.Select(entry => entry.Kind));
        Assert.Equal("workflow", all[0].StorageId);
        Assert.Equal(UnifiedHistoryStorageKind.WorkflowTask, all[0].StorageKind);
        Assert.Equal("保留的部分总结", all[0].CopyText);
        Assert.Equal("文件最终转写", all[1].CopyText);
        Assert.Equal("听写最终文本", all[2].CopyText);
    }

    [Fact]
    public void Search_kind_filter_and_pagination_apply_after_cross_store_merge()
    {
        var service = Service(
            dictations:
            [
                Dictation("dictation-old", Now.AddMinutes(-5), "raw dictation needle"),
                Dictation("dictation-new", Now.AddMinutes(-1), "other raw"),
            ],
            workflows:
            [
                Workflow("summary", Now.AddMinutes(-2), "partial workflow needle"),
            ],
            files:
            [
                FileJob("file", Now.AddMinutes(-3), "translated file needle"),
            ]);

        var firstPage = service.Search(new UnifiedHistoryQuery(
            searchText: null,
            kind: null,
            offset: 0,
            limit: 2));
        var secondPage = service.Search(new UnifiedHistoryQuery(
            searchText: null,
            kind: null,
            offset: 2,
            limit: 2));
        var workflowSearch = service.Search(new UnifiedHistoryQuery(
            "workflow needle",
            UnifiedHistoryKind.SelectionSummary,
            offset: 0,
            limit: 10));
        var fileSearch = service.Search(new UnifiedHistoryQuery(
            "translated file needle",
            UnifiedHistoryKind.FileTranscription,
            offset: 0,
            limit: 10));

        Assert.Equal(4, firstPage.TotalCount);
        Assert.Equal(
            new[] { "dictation-new", "workflow:summary" },
            firstPage.Items.Select(entry => entry.Id));
        Assert.Equal(
            new[] { "file:file", "dictation-old" },
            secondPage.Items.Select(entry => entry.Id));
        Assert.Equal("workflow:summary", Assert.Single(workflowSearch.Items).Id);
        Assert.Equal("file:file", Assert.Single(fileSearch.Items).Id);
    }

    [Fact]
    public void Deleting_agent_history_removes_only_its_managed_session()
    {
        var workflows = new MemoryWorkflowRepository(
        [
            Workflow(
                "agent-task",
                Now,
                kind: WorkflowTaskKind.AgentCompose),
        ]);
        var workspaceStore = new CapturingWorkspaceStore(
        [
            new AgentSessionWorkspaceDescriptor("agent-task", Now, false),
            new AgentSessionWorkspaceDescriptor("other-task", Now, false),
        ]);
        var workspaces = new AgentSessionWorkspaceRetentionService(
            workspaceStore,
            new ControlledTimeProvider(Now));
        var service = new UnifiedHistoryQueryService(
            new MemoryHistoryStore([]),
            workflows,
            fileTranscriptionJobs: null,
            agentSessionWorkspaces: workspaces);

        Assert.Equal(1, service.Delete(["workflow:agent-task"]));
        Assert.Equal(["agent-task"], workspaceStore.DeletedIds);
        Assert.NotNull(workspaceStore.ListSessions().SingleOrDefault(session =>
            session.SessionId == "other-task"));
    }

    private static UnifiedHistoryQueryService Service(
        IReadOnlyList<HistoryEntry> dictations,
        IReadOnlyList<WorkflowTaskRecord> workflows,
        IReadOnlyList<FileTranscriptionJob> files) => new(
        new MemoryHistoryStore(dictations),
        new MemoryWorkflowRepository(workflows),
        new MemoryFileRepository(files));

    private static HistoryEntry Dictation(
        string id,
        DateTimeOffset createdAt,
        string rawText = "听写原文") => new(
        id,
        "qwen",
        rawText,
        "听写最终文本",
        new HistoryMetadata(asrProvider: AsrProviderId.Qwen),
        createdAt);

    private static WorkflowTaskRecord Workflow(
        string id,
        DateTimeOffset createdAt,
        string partialText = "保留的部分总结",
        WorkflowTaskKind kind = WorkflowTaskKind.SelectionSummary) => new(
        id,
        kind,
        WorkflowTaskStage.Processing,
        WorkflowTaskStatus.PartiallyCompleted,
        Guid.NewGuid(),
        rawText: "划词原文",
        partialText,
        finalText: null,
        providerId: "fixture-provider",
        model: "fixture-model",
        targetJson: null,
        contextJson: null,
        traceJson: null,
        outputJson: null,
        failureJson: null,
        warningsJson: null,
        createdAtUnixMs: createdAt.ToUnixTimeMilliseconds(),
        updatedAtUnixMs: createdAt.AddSeconds(1).ToUnixTimeMilliseconds(),
        completedAtUnixMs: createdAt.AddSeconds(1).ToUnixTimeMilliseconds());

    private static FileTranscriptionJob FileJob(
        string id,
        DateTimeOffset createdAt,
        string translatedText = "文件译文") => new(
        id,
        sourcePath: $@"C:\Media\{id}.mp3",
        displayName: $"{id}.mp3",
        provider: AsrProviderId.Qwen,
        language: RecognitionLanguage.Automatic,
        createdAtUnixMs: createdAt.ToUnixTimeMilliseconds(),
        status: FileTranscriptionJobStatus.Completed,
        durationMs: 1_000,
        progress: 1,
        rawText: "文件原始转写",
        finalText: "文件最终转写",
        segmentCount: 1,
        segmentCompleted: 1,
        translationStatus: FileTranscriptionTranslationStatus.Completed,
        translatedText: translatedText,
        translationTargetLanguage: "zh-Hans",
        translationUpdatedAtUnixMs: createdAt.AddSeconds(2).ToUnixTimeMilliseconds(),
        updatedAtUnixMs: createdAt.AddSeconds(2).ToUnixTimeMilliseconds(),
        completedAtUnixMs: createdAt.AddSeconds(1).ToUnixTimeMilliseconds());

    private sealed class MemoryHistoryStore(IReadOnlyList<HistoryEntry> entries)
        : IHistoryStore
    {
        public HistoryMaintenanceResult WriteAndPrune(
            HistoryEntry entry,
            DateTimeOffset? deleteBeforeUtcExclusive) => throw new NotSupportedException();
        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) => 0;
        public IReadOnlyList<HistoryEntry> ReadAll() => entries;
        public int Delete(IReadOnlyCollection<string> ids) => 0;
        public int Clear() => 0;
        public bool UpdateFinalText(string id, string finalText) => false;
    }

    private sealed class MemoryWorkflowRepository(
        IReadOnlyList<WorkflowTaskRecord> initialTasks) : IWorkflowTaskRepository
    {
        private readonly List<WorkflowTaskRecord> tasks = [.. initialTasks];

        public void Create(WorkflowTaskRecord task) => throw new NotSupportedException();
        public WorkflowTaskRecord? Get(string id) => tasks.FirstOrDefault(task => task.Id == id);
        public WorkflowTaskPage Search(WorkflowTaskQuery query)
        {
            var page = tasks.Skip(query.Offset).Take(query.Limit).ToArray();
            return new WorkflowTaskPage(page, tasks.Count, query.Offset, query.Limit);
        }
        public bool TryUpdate(WorkflowTaskRecord task, Guid expectedGeneration) => false;
        public bool Delete(string id) => tasks.RemoveAll(task => task.Id == id) == 1;
        public IReadOnlyList<string> ListActiveIds() => [];
        public int PruneTerminalBefore(long cutoffUnixMs) => 0;
        public int MarkActiveAsInterrupted(long interruptedAtUnixMs) => 0;
    }

    private sealed class CapturingWorkspaceStore(
        IReadOnlyList<AgentSessionWorkspaceDescriptor> initialSessions)
        : IAgentSessionWorkspaceStore
    {
        private readonly List<AgentSessionWorkspaceDescriptor> sessions =
            [.. initialSessions];

        public List<string> DeletedIds { get; } = [];

        public IReadOnlyList<AgentSessionWorkspaceDescriptor> ListSessions() =>
            sessions.ToArray();

        public bool DeleteSession(string sessionId)
        {
            DeletedIds.Add(sessionId);
            return sessions.RemoveAll(session => session.SessionId == sessionId) == 1;
        }

        public AgentSessionWorkspaceEphemeralCleanupResult CleanupEphemeralArtifacts(
            string sessionId) => new(0, 0);
    }

    private sealed class MemoryFileRepository(IReadOnlyList<FileTranscriptionJob> jobs)
        : IFileTranscriptionJobRepository
    {
        public void Create(FileTranscriptionJob job) => throw new NotSupportedException();
        public FileTranscriptionJob? Get(string id) => jobs.FirstOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs;
        public bool Update(FileTranscriptionJob job) => false;
        public bool Delete(string id) => false;
        public int MarkRunningAsInterrupted() => 0;
    }
}
