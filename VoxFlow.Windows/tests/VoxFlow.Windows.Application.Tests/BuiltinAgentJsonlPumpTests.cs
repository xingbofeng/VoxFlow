using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentJsonlPumpTests
{
    [Fact]
    public async Task Tool_request_is_dispatched_then_structured_result_is_written_back()
    {
        var output = new StringReader("""
        {"event":"modelDelta","text":"working"}
        {"event":"toolRequested","toolCall":{"id":"tool-1","name":"read_file","arguments":{"path":"a.txt"}}}
        {"event":"turnCompleted","summary":"done"}
        """);
        var input = new StringWriter();
        var events = new List<string>();
        var pump = new BuiltinAgentJsonlPump();

        await pump.PumpAsync(
            output,
            input,
            sidecarEvent => { events.Add(sidecarEvent.Event); return Task.CompletedTask; },
            (call, _) => Task.FromResult(AgentToolResult.Success(
                call.Name,
                JsonSerializer.SerializeToElement(new { path = "a.txt" }))),
            CancellationToken.None);

        Assert.Equal(["modelDelta", "toolRequested", "turnCompleted"], events);
        var result = JsonSerializer.Deserialize<AgentToolResult>(input.ToString(), DomainJson.Options);
        Assert.True(result?.Ok);
        Assert.Equal("read_file", result?.ToolName);
    }

    [Fact]
    public async Task Unknown_and_partial_lines_fail_closed_before_reaching_host_callbacks()
    {
        var output = new StringReader("{\"event\":\"future\"}\n{\"event\":\"modelDelta\"\n");
        var events = 0;

        var exception = await Assert.ThrowsAsync<BuiltinAgentSidecarProtocolException>(() =>
            new BuiltinAgentJsonlPump().PumpAsync(
                output,
                new StringWriter(),
                _ => { events++; return Task.CompletedTask; },
                (_, _) => throw new InvalidOperationException("no tool expected"),
                CancellationToken.None));

        Assert.Equal(0, events);
        Assert.Equal("unknown_event", exception.Message);
    }

    [Fact]
    public async Task Truncated_line_fails_closed_without_exposing_the_line()
    {
        var output = new StringReader("{\"event\":\"modelDelta\"");
        var callbacks = 0;

        var exception = await Assert.ThrowsAsync<BuiltinAgentSidecarProtocolException>(() =>
            new BuiltinAgentJsonlPump().PumpAsync(
                output,
                new StringWriter(),
                _ => { callbacks++; return Task.CompletedTask; },
                (_, _) => throw new InvalidOperationException("no tool expected"),
                CancellationToken.None));

        Assert.Equal(0, callbacks);
        Assert.Equal("invalid_sidecar_event", exception.Message);
    }

    [Fact]
    public async Task Cancellation_after_a_tool_event_does_not_start_the_late_tool()
    {
        var output = new StringReader("""
        {"event":"toolRequested","toolCall":{"id":"late-1","name":"write_file","arguments":{}}}
        """);
        using var cancellation = new CancellationTokenSource();
        var toolExecutions = 0;

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new BuiltinAgentJsonlPump().PumpAsync(
                output,
                new StringWriter(),
                _ =>
                {
                    cancellation.Cancel();
                    return Task.CompletedTask;
                },
                (_, _) =>
                {
                    toolExecutions++;
                    return Task.FromResult(AgentToolResult.Success(
                        "write_file",
                        JsonSerializer.SerializeToElement(new { })));
                },
                cancellation.Token));

        Assert.Equal(0, toolExecutions);
    }

    [Fact]
    public async Task Slow_dispatcher_does_not_block_pipe_reader_or_tool_result_writeback()
    {
        var dispatcher = new BlockingDispatcher();
        var toolStarted = new TaskCompletionSource();
        var pumpTask = new BuiltinAgentJsonlPump(dispatcher).PumpAsync(
            new StringReader("""{"event":"toolRequested","toolCall":{"id":"tool-1","name":"read_file","arguments":{}}}"""),
            new StringWriter(),
            _ => Task.CompletedTask,
            (_, _) => { toolStarted.SetResult(); return Task.FromResult(AgentToolResult.Success("read_file")); },
            CancellationToken.None);

        await toolStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Assert.False(pumpTask.IsCompleted);
        dispatcher.Release();
        await pumpTask;
    }

    private sealed class BlockingDispatcher : IAgentSidecarEventDispatcher
    {
        private readonly TaskCompletionSource gate = new();
        public async Task DispatchAsync(Func<Task> action, CancellationToken cancellationToken)
        {
            await gate.Task.WaitAsync(cancellationToken);
            await action();
        }
        public void Release() => gate.SetResult();
    }
}
