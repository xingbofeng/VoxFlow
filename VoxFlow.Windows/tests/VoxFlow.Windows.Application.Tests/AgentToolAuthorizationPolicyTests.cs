using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.History;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentToolAuthorizationPolicyTests
{
    [Theory]
    [InlineData("帮我搜索上次的语音记录", true)]
    [InlineData("find my dictation history about launch plans", true)]
    [InlineData("帮我总结屏幕上的邮件", false)]
    public void Only_the_trusted_voice_instruction_can_authorize_history_search(string instruction, bool expected)
    {
        Assert.Equal(expected, new AgentToolAuthorizationPolicy(instruction).AllowsTranscriptionSearch());
    }

    [Fact]
    public async Task Tool_host_rejects_history_search_without_trusted_voice_authorization()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-agent-auth-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var history = new EmptyHistoryStore();
            var call = new VoxFlow.Windows.Domain.AgentToolCall("call", "search_transcriptions", JsonSerializer.SerializeToElement(new { query = "anything" }));
            var denied = await new BuiltinAgentFileToolHost(root, history: history,
                authorization: new AgentToolAuthorizationPolicy("总结屏幕内容"))
                .ExecuteAsync(call, CancellationToken.None);
            var allowed = await new BuiltinAgentFileToolHost(root, history: history,
                authorization: new AgentToolAuthorizationPolicy("搜索我之前的转写"))
                .ExecuteAsync(call, CancellationToken.None);

            Assert.Equal("user_intent_required", denied.Error?.Code);
            Assert.True(allowed.Ok, allowed.Error?.Code);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private sealed class EmptyHistoryStore : IHistoryStore
    {
        public HistoryMaintenanceResult WriteAndPrune(HistoryEntry entry, DateTimeOffset? deleteBeforeUtcExclusive) => throw new NotSupportedException();
        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) => throw new NotSupportedException();
        public IReadOnlyList<HistoryEntry> ReadAll() => [];
        public int Delete(IReadOnlyCollection<string> ids) => throw new NotSupportedException();
        public int Clear() => throw new NotSupportedException();
        public bool UpdateFinalText(string id, string finalText) => throw new NotSupportedException();
    }
}
