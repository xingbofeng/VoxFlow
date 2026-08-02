using System.Text.Json;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class WorkflowTaskRepositoryTests
{
    [Fact]
    public void Crud_round_trips_text_provider_timestamps_and_all_json_fields()
    {
        using var fixture = new WorkflowDatabase();
        var generation = Guid.NewGuid();
        var original = TaskRecord(
            "task-1",
            generation,
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Recording,
            WorkflowTaskStatus.Pending,
            rawText: "帮我做",
            partialText: "正在",
            finalText: null,
            providerId: "openai",
            model: "gpt-test",
            targetJson: Json("""{"window":"editor"}"""),
            contextJson: Json("""{"sources":["uia"]}"""),
            traceJson: Json("""{"schemaVersion":1,"events":[]}"""),
            outputJson: Json("""{"artifacts":[]}"""),
            failureJson: Json("""{"code":"none"}"""),
            warningsJson: Json("""["partialFallback"]"""));

        fixture.Repository.Create(original);
        var stored = Assert.IsType<WorkflowTaskRecord>(
            fixture.Repository.Get("task-1"));

        AssertTaskEqual(original, stored);
        var running = TaskRecord(
            "task-1",
            generation,
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Recording,
            WorkflowTaskStatus.Running,
            rawText: "帮我做",
            partialText: "正在处理",
            finalText: null,
            providerId: "openai",
            model: "gpt-test",
            targetJson: original.TargetJson,
            contextJson: original.ContextJson,
            traceJson: Json("""{"schemaVersion":1,"events":[{"kind":"started"}]}"""),
            outputJson: original.OutputJson,
            failureJson: null,
            warningsJson: original.WarningsJson,
            createdAtUnixMs: 100,
            updatedAtUnixMs: 200);
        Assert.True(fixture.Repository.TryUpdate(running, generation));
        AssertTaskEqual(running, fixture.Repository.Get("task-1")!);
        Assert.True(fixture.Repository.Delete("task-1"));
        Assert.False(fixture.Repository.Delete("task-1"));
        Assert.Null(fixture.Repository.Get("task-1"));
    }

    [Fact]
    public void Legal_transitions_succeed_but_backwards_and_terminal_updates_are_rejected()
    {
        using var fixture = new WorkflowDatabase();
        var generation = Guid.NewGuid();
        fixture.Repository.Create(TaskRecord(
            "selection",
            generation,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.CapturingSelection,
            WorkflowTaskStatus.Pending));

        Assert.True(fixture.Repository.TryUpdate(TaskRecord(
            "selection",
            generation,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.CapturingSelection,
            WorkflowTaskStatus.Running,
            updatedAtUnixMs: 200), generation));
        Assert.True(fixture.Repository.TryUpdate(TaskRecord(
            "selection",
            generation,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.Processing,
            WorkflowTaskStatus.Running,
            partialText: "处理中",
            updatedAtUnixMs: 300), generation));
        Assert.False(fixture.Repository.TryUpdate(TaskRecord(
            "selection",
            generation,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.Processing,
            WorkflowTaskStatus.Pending,
            updatedAtUnixMs: 400), generation));
        Assert.True(fixture.Repository.TryUpdate(TaskRecord(
            "selection",
            generation,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            rawText: "hello",
            finalText: "你好",
            updatedAtUnixMs: 400,
            completedAtUnixMs: 400), generation));

        Assert.False(fixture.Repository.TryUpdate(TaskRecord(
            "selection",
            generation,
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.Processing,
            WorkflowTaskStatus.Running,
            finalText: "迟到覆盖",
            updatedAtUnixMs: 500), generation));
        var terminal = fixture.Repository.Get("selection")!;
        Assert.Equal(WorkflowTaskStatus.Completed, terminal.Status);
        Assert.Equal("你好", terminal.FinalText);
    }

    [Fact]
    public void Partial_terminal_result_and_json_trace_are_preserved_once()
    {
        using var fixture = new WorkflowDatabase();
        var generation = Guid.NewGuid();
        fixture.Repository.Create(TaskRecord(
            "partial",
            generation,
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Processing,
            WorkflowTaskStatus.Running));
        var partial = TaskRecord(
            "partial",
            generation,
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Processing,
            WorkflowTaskStatus.PartiallyCompleted,
            rawText: "很长的原文",
            partialText: "保留的部分总结",
            traceJson: Json("""{"events":[{"kind":"cancelled"}]}"""),
            outputJson: Json("""{"copied":false}"""),
            failureJson: Json("""{"code":"userCancelled"}"""),
            updatedAtUnixMs: 200,
            completedAtUnixMs: 200);

        Assert.True(fixture.Repository.TryUpdate(partial, generation));
        var stored = fixture.Repository.Get("partial")!;
        Assert.Equal(WorkflowTaskStatus.PartiallyCompleted, stored.Status);
        Assert.Equal("保留的部分总结", stored.PartialText);
        AssertJsonEqual(partial.TraceJson, stored.TraceJson);
        AssertJsonEqual(partial.OutputJson, stored.OutputJson);
        AssertJsonEqual(partial.FailureJson, stored.FailureJson);
        Assert.False(fixture.Repository.TryUpdate(partial, generation));
    }

    [Fact]
    public void Generation_condition_rejects_wrong_or_late_events()
    {
        using var fixture = new WorkflowDatabase();
        var generation = Guid.NewGuid();
        fixture.Repository.Create(TaskRecord(
            "generation",
            generation,
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Operating,
            WorkflowTaskStatus.Running));

        Assert.False(fixture.Repository.TryUpdate(TaskRecord(
            "generation",
            generation,
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Operating,
            WorkflowTaskStatus.Running,
            partialText: "wrong generation",
            updatedAtUnixMs: 200), Guid.NewGuid()));
        Assert.True(fixture.Repository.TryUpdate(TaskRecord(
            "generation",
            generation,
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Operating,
            WorkflowTaskStatus.Cancelled,
            partialText: "已取消",
            updatedAtUnixMs: 200,
            completedAtUnixMs: 200), generation));
        Assert.False(fixture.Repository.TryUpdate(TaskRecord(
            "generation",
            generation,
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            finalText: "late model final",
            updatedAtUnixMs: 300,
            completedAtUnixMs: 300), generation));
        Assert.Equal("已取消", fixture.Repository.Get("generation")?.PartialText);
        Assert.Null(fixture.Repository.Get("generation")?.FinalText);
    }

    [Fact]
    public void Maintenance_lists_active_and_prunes_only_terminal_rows_older_than_cutoff()
    {
        using var fixture = new WorkflowDatabase();
        fixture.Repository.Create(TaskRecord(
            "pending",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.CapturingSelection,
            WorkflowTaskStatus.Pending,
            createdAtUnixMs: 50,
            updatedAtUnixMs: 50));
        fixture.Repository.Create(TaskRecord(
            "running",
            Guid.NewGuid(),
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Operating,
            WorkflowTaskStatus.Running,
            createdAtUnixMs: 50,
            updatedAtUnixMs: 50));
        fixture.Repository.Create(TaskRecord(
            "old-terminal",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            finalText: "old",
            createdAtUnixMs: 50,
            updatedAtUnixMs: 99,
            completedAtUnixMs: 99));
        fixture.Repository.Create(TaskRecord(
            "boundary-terminal",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            finalText: "boundary",
            createdAtUnixMs: 50,
            updatedAtUnixMs: 100,
            completedAtUnixMs: 100));

        Assert.Equal(
            new[] { "pending", "running" },
            fixture.Repository.ListActiveIds().Order());
        Assert.Equal(1, fixture.Repository.PruneTerminalBefore(100));
        Assert.Null(fixture.Repository.Get("old-terminal"));
        Assert.NotNull(fixture.Repository.Get("boundary-terminal"));
        Assert.NotNull(fixture.Repository.Get("pending"));
        Assert.NotNull(fixture.Repository.Get("running"));
    }

    [Fact]
    public void Search_is_parameterized_filterable_and_paged_newest_first()
    {
        using var fixture = new WorkflowDatabase();
        fixture.Repository.Create(TaskRecord(
            "old-summary",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            rawText: "原文 A",
            finalText: "包含 unique-result 的总结",
            createdAtUnixMs: 100,
            updatedAtUnixMs: 100,
            completedAtUnixMs: 100));
        fixture.Repository.Create(TaskRecord(
            "new-summary",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            rawText: "原文 B",
            finalText: "另一个 unique-result，完成度 100%",
            createdAtUnixMs: 300,
            updatedAtUnixMs: 300,
            completedAtUnixMs: 300));
        fixture.Repository.Create(TaskRecord(
            "translation",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            rawText: "unique-result only in translation",
            finalText: "翻译",
            createdAtUnixMs: 200,
            updatedAtUnixMs: 200,
            completedAtUnixMs: 200));

        var firstPage = fixture.Repository.Search(new WorkflowTaskQuery(
            searchText: "unique-result",
            kind: WorkflowTaskKind.SelectionSummary,
            offset: 0,
            limit: 1));
        var secondPage = fixture.Repository.Search(new WorkflowTaskQuery(
            searchText: "unique-result",
            kind: WorkflowTaskKind.SelectionSummary,
            offset: 1,
            limit: 1));

        Assert.Equal(2, firstPage.TotalCount);
        Assert.Equal("new-summary", Assert.Single(firstPage.Items).Id);
        Assert.Equal(2, secondPage.TotalCount);
        Assert.Equal("old-summary", Assert.Single(secondPage.Items).Id);
        var literalPercent = fixture.Repository.Search(new WorkflowTaskQuery(
            searchText: "%",
            kind: null,
            offset: 0,
            limit: 100));
        Assert.Equal("new-summary", Assert.Single(literalPercent.Items).Id);
    }

    [Fact]
    public void Startup_recovery_interrupts_active_tasks_and_preserves_partial_and_trace()
    {
        using var fixture = new WorkflowDatabase();
        fixture.Repository.Create(TaskRecord(
            "pending",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionTranslation,
            WorkflowTaskStage.CapturingSelection,
            WorkflowTaskStatus.Pending,
            partialText: "pending partial"));
        fixture.Repository.Create(TaskRecord(
            "waiting",
            Guid.NewGuid(),
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.WaitingForUser,
            WorkflowTaskStatus.Running,
            partialText: "waiting partial",
            traceJson: Json("""{"events":[{"kind":"question"}]}""")));
        fixture.Repository.Create(TaskRecord(
            "operating",
            Guid.NewGuid(),
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Operating,
            WorkflowTaskStatus.Running,
            traceJson: Json("""{"events":[{"kind":"writeFile"}]}""")));
        fixture.Repository.Create(TaskRecord(
            "done",
            Guid.NewGuid(),
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            finalText: "done",
            completedAtUnixMs: 100));

        Assert.Equal(3, fixture.Repository.MarkActiveAsInterrupted(1_000));
        Assert.Equal(0, fixture.Repository.MarkActiveAsInterrupted(1_100));

        foreach (var id in new[] { "pending", "waiting", "operating" })
        {
            var interrupted = fixture.Repository.Get(id)!;
            Assert.Equal(WorkflowTaskStatus.Interrupted, interrupted.Status);
            Assert.Equal(1_000, interrupted.UpdatedAtUnixMs);
            Assert.Equal(1_000, interrupted.CompletedAtUnixMs);
        }
        Assert.Equal("waiting partial", fixture.Repository.Get("waiting")?.PartialText);
        Assert.Equal(
            "question",
            fixture.Repository.Get("waiting")?.TraceJson?
                .GetProperty("events")[0]
                .GetProperty("kind")
                .GetString());
        Assert.Equal(WorkflowTaskStatus.Completed, fixture.Repository.Get("done")?.Status);
        Assert.Equal("done", fixture.Repository.Get("done")?.FinalText);
    }

    private static WorkflowTaskRecord TaskRecord(
        string id,
        Guid generation,
        WorkflowTaskKind kind,
        WorkflowTaskStage stage,
        WorkflowTaskStatus status,
        string? rawText = null,
        string? partialText = null,
        string? finalText = null,
        string? providerId = null,
        string? model = null,
        JsonElement? targetJson = null,
        JsonElement? contextJson = null,
        JsonElement? traceJson = null,
        JsonElement? outputJson = null,
        JsonElement? failureJson = null,
        JsonElement? warningsJson = null,
        long createdAtUnixMs = 100,
        long updatedAtUnixMs = 100,
        long? completedAtUnixMs = null) => new(
            id,
            kind,
            stage,
            status,
            generation,
            rawText,
            partialText,
            finalText,
            providerId,
            model,
            targetJson,
            contextJson,
            traceJson,
            outputJson,
            failureJson,
            warningsJson,
            createdAtUnixMs,
            updatedAtUnixMs,
            completedAtUnixMs);

    private static JsonElement Json(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.Clone();
    }

    private static void AssertTaskEqual(
        WorkflowTaskRecord expected,
        WorkflowTaskRecord actual)
    {
        Assert.Equal(expected.Id, actual.Id);
        Assert.Equal(expected.Kind, actual.Kind);
        Assert.Equal(expected.Stage, actual.Stage);
        Assert.Equal(expected.Status, actual.Status);
        Assert.Equal(expected.Generation, actual.Generation);
        Assert.Equal(expected.RawText, actual.RawText);
        Assert.Equal(expected.PartialText, actual.PartialText);
        Assert.Equal(expected.FinalText, actual.FinalText);
        Assert.Equal(expected.ProviderId, actual.ProviderId);
        Assert.Equal(expected.Model, actual.Model);
        AssertJsonEqual(expected.TargetJson, actual.TargetJson);
        AssertJsonEqual(expected.ContextJson, actual.ContextJson);
        AssertJsonEqual(expected.TraceJson, actual.TraceJson);
        AssertJsonEqual(expected.OutputJson, actual.OutputJson);
        AssertJsonEqual(expected.FailureJson, actual.FailureJson);
        AssertJsonEqual(expected.WarningsJson, actual.WarningsJson);
        Assert.Equal(expected.CreatedAtUnixMs, actual.CreatedAtUnixMs);
        Assert.Equal(expected.UpdatedAtUnixMs, actual.UpdatedAtUnixMs);
        Assert.Equal(expected.CompletedAtUnixMs, actual.CompletedAtUnixMs);
    }

    private static void AssertJsonEqual(JsonElement? expected, JsonElement? actual) =>
        Assert.Equal(expected?.GetRawText(), actual?.GetRawText());

    private sealed class WorkflowDatabase : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly SqliteTransactionRunner runner;

        public WorkflowDatabase()
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.db");
            var flags = new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true);
            new VoxFlowDatabaseMigrator(
                InteractiveFeatureMigrationCatalog.For(flags))
                .Migrate(databasePath);
            runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(databasePath, pooling: false));
            Repository = new SqliteWorkflowTaskRepository(runner);
        }

        public SqliteWorkflowTaskRepository Repository { get; }

        public void Dispose()
        {
            runner.Dispose();
            directory.Dispose();
        }
    }
}
