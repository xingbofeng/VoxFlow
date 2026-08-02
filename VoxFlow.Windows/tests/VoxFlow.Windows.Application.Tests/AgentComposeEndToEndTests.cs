using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

/// <summary>Contract-level runs through the JSONL runner and managed tool
/// hosts. These use no network, real model, keyboard or desktop target.</summary>
public sealed class AgentComposeEndToEndTests
{
    [Fact]
    public async Task Read_only_answer_copies_on_success_and_reports_copy_failure_honestly()
    {
        var (service, _) = Service("""{"schemaVersion":1,"event":"turnCompleted","summary":"reply"}""");
        var run = await service.ExecuteWithBuiltinToolsAsync("task-copy", "reply", Context(), Workspace(), null, _ => Task.CompletedTask, CancellationToken.None);

        Assert.True(run.Succeeded);
        var copied = new Clipboard(true);
        var copiedResult = new AgentComposeOutputCoordinator(copied, new Summary()).Complete("reply", []);
        var failedResult = new AgentComposeOutputCoordinator(new Clipboard(false), new Summary()).Complete("reply", []);

        Assert.Equal(AgentComposeOutputStatus.Copied, copiedResult.Status);
        Assert.Equal("reply", copied.Text);
        Assert.Equal(AgentComposeOutputStatus.CopyFailed, failedResult.Status);
        Assert.Equal("clipboard_copy_failed", failedResult.SafeErrorCode);
    }

    [Fact]
    public async Task File_history_and_text_field_tools_run_without_a_submit_path()
    {
        var workspace = Workspace();
        Directory.CreateDirectory(workspace);
        try
        {
            var history = new History();
            var field = new TextField(AgentTextFieldWriteStatus.Succeeded);
            var script = """
                {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"write","name":"write_file","arguments":{"file_path":"reply.txt","content":"draft"}}}
                {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"history","name":"search_transcriptions","arguments":{"query":"plan","limit":5}}}
                {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"field","name":"text_field","arguments":{"action":"insert","text":"draft"}}}
                {"schemaVersion":1,"event":"turnCompleted","summary":"finished"}
                """;
            var (service, factory) = Service(script, history, new TextFieldFactory(field));

            var run = await service.ExecuteWithBuiltinToolsAsync(
                "task-tools", "search my dictation history and create reply.txt", EditableContext(), workspace,
                history, _ => Task.CompletedTask, CancellationToken.None);

            Assert.True(run.Succeeded);
            Assert.Equal("draft", await File.ReadAllTextAsync(Path.Combine(workspace, "reply.txt")));
            Assert.Equal(1, history.SearchCalls);
            Assert.Equal(["draft"], field.Inserted);
            Assert.Equal(0, field.ReplaceCalls);
            Assert.Contains("history answer", factory.Session!.WrittenInput, StringComparison.Ordinal);
            Assert.DoesNotContain("Enter", factory.Session.WrittenInput, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(workspace, recursive: true);
        }
    }

    [Fact]
    public async Task Target_change_is_returned_to_the_model_and_does_not_send_or_claim_a_side_effect()
    {
        var field = new TextField(AgentTextFieldWriteStatus.TargetChanged);
        var script = """
            {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"field","name":"text_field","arguments":{"action":"insert","text":"draft"}}}
            {"schemaVersion":1,"event":"turnCompleted","summary":"could not insert"}
            """;
        var (service, factory) = Service(script, textField: new TextFieldFactory(field));

        var run = await service.ExecuteWithBuiltinToolsAsync("task-target", "insert this", EditableContext(), Workspace(), null, _ => Task.CompletedTask, CancellationToken.None);

        Assert.True(run.Succeeded);
        Assert.Empty(field.Inserted);
        Assert.Contains("target_changed", factory.Session!.WrittenInput, StringComparison.Ordinal);
        var clipboard = new Clipboard(true);
        var output = new AgentComposeOutputCoordinator(clipboard, new Summary()).Complete(
            "could not insert", [AgentToolResult.Failure("text_field", "target_changed")]);
        Assert.Equal(AgentComposeOutputStatus.Copied, output.Status);
        Assert.Equal("could not insert", clipboard.Text);
    }

    [Fact]
    public async Task Cancellation_after_a_successful_file_write_keeps_the_effect_and_stops_later_work()
    {
        var workspace = Workspace();
        Directory.CreateDirectory(workspace);
        try
        {
            using var cancellation = new CancellationTokenSource();
            var output = new CancelAfterFirstLineReader(
                """{"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"write","name":"write_file","arguments":{"file_path":"partial.txt","content":"persisted"}}}""",
                cancellation);
            var factory = new Factory(new Session(output));
            var service = new AgentComposeExecutionService(new Resolver(), new AgentComposePromptBuilder(), new BuiltinAgentSidecarRunner(factory));

            var run = await service.ExecuteWithBuiltinToolsAsync("task-cancel", "create partial.txt", Context(), workspace, null, _ => Task.CompletedTask, cancellation.Token);

            Assert.False(run.Succeeded);
            Assert.Equal("cancelled", run.SidecarOutcome?.SafeFailureCode);
            Assert.Equal("persisted", await File.ReadAllTextAsync(Path.Combine(workspace, "partial.txt")));
            Assert.True(factory.Session!.Cancelled);
        }
        finally
        {
            Directory.Delete(workspace, recursive: true);
        }
    }

    private static (AgentComposeExecutionService Service, Factory Factory) Service(
        string script,
        IHistoryStore? history = null,
        IAgentTextFieldGatewayFactory? textField = null)
    {
        var factory = new Factory(new Session(new StringReader(script)));
        return (new AgentComposeExecutionService(new Resolver(), new AgentComposePromptBuilder(), new BuiltinAgentSidecarRunner(factory), textField: textField), factory);
    }

    private static AgentContextSnapshot Context() => new(Target(), "selected", []);

    private static AgentContextSnapshot EditableContext()
    {
        var target = Target();
        var selection = new SelectionSnapshot("selected", SelectionAcquisitionSource.UiAutomation, target, [1],
            [new SelectionRangeSnapshot(0, "selected", [new WindowBounds(0, 0, 1, 1)], null, null)],
            SelectionEditability.Editable, true, 1);
        return new AgentContextSnapshot(target, "selected", [], Selection: selection);
    }

    private static ForegroundTargetSnapshot Target() => new(1, 2, "notepad.exe", "draft", new WindowBounds(0, 0, 10, 10), ProcessIntegrityLevel.Medium, [1], 1);
    private static string Workspace() => Path.Combine(Path.GetTempPath(), "voxflow-agent-e2e-" + Guid.NewGuid().ToString("N"));

    private sealed class Resolver : IDefaultLlmProviderResolver
    {
        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(CancellationToken cancellationToken) => ValueTask.FromResult<LlmProviderClientConfiguration?>(new("provider", new Uri("https://example.test/v1"), "model", "secret", 0.2, TimeSpan.FromSeconds(30)));
    }

    private sealed class Factory(Session session) : IBuiltinAgentProcessSessionFactory
    {
        public Session? Session { get; private set; } = session;
        public Task<IBuiltinAgentProcessSession> StartAsync(BuiltinAgentSidecarRunRequest request, CancellationToken cancellationToken) => Task.FromResult<IBuiltinAgentProcessSession>(Session!);
    }

    private sealed class Session(TextReader output) : IBuiltinAgentProcessSession
    {
        private readonly StringReader error = new(string.Empty);
        private readonly StringWriter input = new();
        public TextReader StandardOutput { get; } = output;
        public TextReader StandardError => error;
        public TextWriter StandardInput => input;
        public bool Cancelled { get; private set; }
        public string WrittenInput => input.ToString();
        public Task<int> WaitForExitAsync(CancellationToken cancellationToken, TimeSpan? timeout = null) => Task.FromResult(0);
        public Task<BuiltinAgentStderrSummary> DrainStandardErrorAsync(CancellationToken cancellationToken) => Task.FromResult(new BuiltinAgentStderrSummary(false, false));
        public Task CancelAsync() { Cancelled = true; return Task.CompletedTask; }
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class CancelAfterFirstLineReader(string line, CancellationTokenSource cancellation) : TextReader
    {
        private bool delivered;
        public override ValueTask<string?> ReadLineAsync(CancellationToken cancellationToken)
        {
            if (delivered)
            {
                cancellation.Cancel();
                return ValueTask.FromResult<string?>("{\"schemaVersion\":1,\"event\":\"modelDelta\",\"text\":\"late\"}");
            }
            delivered = true;
            return ValueTask.FromResult<string?>(line);
        }
    }

    private sealed class Clipboard(bool succeeds) : IAgentOutputClipboard
    {
        public string? Text { get; private set; }
        public bool TryCopy(string text) { if (!succeeds) return false; Text = text; return true; }
    }

    private sealed class Summary : IAgentOutputSummaryPresenter { public void ShowSummary(string? text) { } }

    private sealed class TextField(AgentTextFieldWriteStatus status) : IAgentTextFieldGateway
    {
        public List<string> Inserted { get; } = [];
        public int ReplaceCalls { get; private set; }
        public Task<AgentTextFieldWriteStatus> InsertAsync(string text, CancellationToken cancellationToken) { if (status == AgentTextFieldWriteStatus.Succeeded) Inserted.Add(text); return Task.FromResult(status); }
        public Task<AgentTextFieldWriteStatus> ReplaceSelectionAsync(string text, CancellationToken cancellationToken) { ReplaceCalls++; return Task.FromResult(status); }
    }

    private sealed class TextFieldFactory(TextField field) : IAgentTextFieldGatewayFactory { public IAgentTextFieldGateway Create(SelectionSnapshot? selection) => field; }

    private sealed class History : IHistoryStore
    {
        public int SearchCalls { get; private set; }
        public HistoryMaintenanceResult WriteAndPrune(HistoryEntry entry, DateTimeOffset? deleteBeforeUtcExclusive) => new(false, 0);
        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) => 0;
        public IReadOnlyList<HistoryEntry> ReadAll() => [];
        public IReadOnlyList<HistoryEntry> Search(string query, DateTimeOffset? dateFromUtc, DateTimeOffset? dateToUtc, int limit) { SearchCalls++; return [new HistoryEntry("history-1", "dictation", "plan raw", "history answer", new HistoryMetadata(), DateTimeOffset.UtcNow)]; }
        public int Delete(IReadOnlyCollection<string> ids) => 0;
        public int Clear() => 0;
        public bool UpdateFinalText(string id, string finalText) => false;
    }
}
