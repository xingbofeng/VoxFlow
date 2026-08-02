using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentToolDispatcherTests
{
    [Fact]
    public async Task Rejects_unknown_tools_without_invoking_handlers()
    {
        var dispatcher = new BuiltinAgentToolDispatcher(new Dictionary<string, Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>>());
        var result = await dispatcher.DispatchAsync(new AgentToolCall("1", "shell", JsonSerializer.SerializeToElement(new { })), CancellationToken.None);
        Assert.False(result.Ok); Assert.Equal("unknown_tool", result.Error?.Code);
    }
}
