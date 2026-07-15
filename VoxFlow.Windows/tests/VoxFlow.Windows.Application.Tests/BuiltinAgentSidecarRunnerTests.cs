using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentSidecarRunnerTests
{
    [Fact]
    public async Task Run_pumps_events_executes_tools_and_returns_a_successful_completion()
    {
        var session = new FakeSession(
            """
            {"schemaVersion":1,"event":"runStarted"}
            {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"read-1","name":"read_file","arguments":{"path":"note.txt"}}}
            {"schemaVersion":1,"event":"turnCompleted","summary":"done"}
            """,
            exitCode: 0);
        var events = new List<string>();
        var runner = new BuiltinAgentSidecarRunner(new FakeFactory(session));

        var outcome = await runner.RunAsync(
            Request(),
            runtimeEvent =>
            {
                events.Add(runtimeEvent.Event);
                return Task.CompletedTask;
            },
            (call, _) => Task.FromResult(AgentToolResult.Success(call.Name)),
            CancellationToken.None);

        Assert.True(outcome.Succeeded);
        Assert.Null(outcome.SafeFailureCode);
        Assert.Equal(["runStarted", "toolRequested", "turnCompleted"], events);
        Assert.Contains("read_file", session.WrittenInput, StringComparison.Ordinal);
        Assert.False(session.Cancelled);
    }

    [Fact]
    public async Task Malformed_or_unknown_jsonl_is_a_terminal_safe_failure_and_cancels_the_session()
    {
        var session = new FakeSession("{\"schemaVersion\":1,\"event\":\"futureEvent\"}", exitCode: 0);
        var runner = new BuiltinAgentSidecarRunner(new FakeFactory(session));

        var outcome = await runner.RunAsync(
            Request(),
            _ => Task.CompletedTask,
            (_, _) => throw new InvalidOperationException("A tool must not run for unknown events."),
            CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Equal("sidecar_protocol_failure", outcome.SafeFailureCode);
        Assert.True(session.Cancelled);
    }

    [Fact]
    public async Task Cancellation_rejects_late_tool_requests_without_executing_them()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var session = new FakeSession(
            """{"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"late-1","name":"write_file","arguments":{}}}""",
            exitCode: 0);
        var runner = new BuiltinAgentSidecarRunner(new FakeFactory(session));

        var outcome = await runner.RunAsync(
            Request(),
            _ => Task.CompletedTask,
            (_, _) => throw new InvalidOperationException("Late tools must not execute."),
            cancellation.Token);

        Assert.False(outcome.Succeeded);
        Assert.Equal("cancelled", outcome.SafeFailureCode);
        Assert.True(session.Cancelled);
    }

    private static BuiltinAgentSidecarRunRequest Request() => new(
        "task-1",
        "read the note",
        new BuiltinAgentSidecarProviderConfig("provider", "https://example.test/v1", "model", "secret", 30),
        [new BuiltinAgentSidecarContentPart("trusted intent")],
        new BuiltinAgentSidecarLoopLimits());

    private sealed class FakeFactory(IBuiltinAgentProcessSession session) : IBuiltinAgentProcessSessionFactory
    {
        public Task<IBuiltinAgentProcessSession> StartAsync(BuiltinAgentSidecarRunRequest request, CancellationToken cancellationToken) =>
            Task.FromResult(session);
    }

    private sealed class FakeSession : IBuiltinAgentProcessSession
    {
        private readonly StringReader output;
        private readonly StringReader error = new(string.Empty);
        private readonly StringWriter input = new();
        private readonly int exitCode;

        public FakeSession(string stdout, int exitCode)
        {
            output = new StringReader(stdout);
            this.exitCode = exitCode;
        }

        public TextReader StandardOutput => output;
        public TextReader StandardError => error;
        public TextWriter StandardInput => input;
        public bool Cancelled { get; private set; }
        public string WrittenInput => input.ToString();

        public Task<int> WaitForExitAsync(CancellationToken cancellationToken, TimeSpan? timeout = null) => Task.FromResult(exitCode);
        public Task<BuiltinAgentStderrSummary> DrainStandardErrorAsync(CancellationToken cancellationToken) => Task.FromResult(new BuiltinAgentStderrSummary(false, false));
        public Task CancelAsync()
        {
            Cancelled = true;
            return Task.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
