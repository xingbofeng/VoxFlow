using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public interface IAgentSidecarEventDispatcher
{
    Task DispatchAsync(Func<Task> action, CancellationToken cancellationToken);
}

public sealed class InlineAgentSidecarEventDispatcher : IAgentSidecarEventDispatcher
{
    public Task DispatchAsync(Func<Task> action, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return action();
    }
}

public sealed class BuiltinAgentJsonlPump
{
    private readonly IAgentSidecarEventDispatcher dispatcher;

    public BuiltinAgentJsonlPump(IAgentSidecarEventDispatcher? dispatcher = null) =>
        this.dispatcher = dispatcher ?? new InlineAgentSidecarEventDispatcher();

    public async Task PumpAsync(
        TextReader output,
        TextWriter input,
        Func<BuiltinAgentSidecarEvent, Task> onEvent,
        Func<AgentToolCall, CancellationToken, Task<AgentToolResult>> executeTool,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(output);
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(onEvent);
        ArgumentNullException.ThrowIfNull(executeTool);

        var pendingUiEvents = new List<Task>();
        while (await output.ReadLineAsync(cancellationToken).ConfigureAwait(false) is { } line)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var parsed = BuiltinAgentSidecarEventParser.ParseLine(line);
            if (parsed.Status == BuiltinAgentSidecarParseStatus.Empty)
            {
                continue;
            }
            if (parsed.Status != BuiltinAgentSidecarParseStatus.Event || parsed.Event is null)
            {
                throw new BuiltinAgentSidecarProtocolException(
                    parsed.SafeMessage ?? "invalid_sidecar_event");
            }

            // UI delivery is deliberately scheduled and tracked, never awaited
            // by the pipe reader. Rust waits for ToolResult only at a tool
            // boundary, so the controlled host operation remains ordered.
            pendingUiEvents.Add(dispatcher.DispatchAsync(
                () => onEvent(parsed.Event), cancellationToken));
            if (parsed.Event.Event != "toolRequested" || parsed.Event.ToolCall is null)
            {
                continue;
            }

            // A cancellation can arrive while the event callback updates the
            // UI. Do not begin a side-effecting host tool for that stale event.
            cancellationToken.ThrowIfCancellationRequested();
            var result = await executeTool(parsed.Event.ToolCall, cancellationToken)
                .ConfigureAwait(false);
            var json = JsonSerializer.Serialize(result, DomainJson.Options);
            await input.WriteLineAsync(json).ConfigureAwait(false);
            await input.FlushAsync(cancellationToken).ConfigureAwait(false);
        }
        await Task.WhenAll(pendingUiEvents).ConfigureAwait(false);
    }
}

public sealed class BuiltinAgentSidecarProtocolException : Exception
{
    public BuiltinAgentSidecarProtocolException(string safeCode)
        : base(safeCode)
    {
    }
}
