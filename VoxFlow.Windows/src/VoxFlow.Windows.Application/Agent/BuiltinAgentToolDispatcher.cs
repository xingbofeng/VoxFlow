using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed class BuiltinAgentToolDispatcher
{
    private readonly IReadOnlyDictionary<string, Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>> handlers;

    public BuiltinAgentToolDispatcher(IReadOnlyDictionary<string, Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>> handlers)
    {
        ArgumentNullException.ThrowIfNull(handlers);
        if (handlers.Keys.Any(name => !BuiltinAgentToolRegistry.IsApproved(name)))
            throw new ArgumentException("Only approved Agent tools can be registered.", nameof(handlers));
        this.handlers = new Dictionary<string, Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>>(handlers, StringComparer.Ordinal);
    }

    public Task<AgentToolResult> DispatchAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (!BuiltinAgentToolRegistry.TryGetSchema(call.Name, out var schema)
            || !handlers.TryGetValue(call.Name, out var handler))
            return Task.FromResult(AgentToolResult.Failure(call.Name, "unknown_tool"));
        if (!schema!.TryValidate(call, out _))
        {
            return Task.FromResult(AgentToolResult.Failure(
                call.Name,
                "invalid_tool_arguments"));
        }
        return handler(call, cancellationToken);
    }
}
