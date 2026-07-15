using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentComposeReadinessGateTests
{
    [Theory]
    [InlineData(false, AsrProviderAvailability.Ready, true, LlmAgentCapabilityStatus.Supported, AgentComposeReadinessStatus.SidecarUnavailable)]
    [InlineData(true, AsrProviderAvailability.Unconfigured, true, LlmAgentCapabilityStatus.Supported, AgentComposeReadinessStatus.AsrUnavailable)]
    [InlineData(true, AsrProviderAvailability.Ready, false, LlmAgentCapabilityStatus.Supported, AgentComposeReadinessStatus.DefaultProviderUnavailable)]
    [InlineData(true, AsrProviderAvailability.Ready, true, LlmAgentCapabilityStatus.Unknown, AgentComposeReadinessStatus.AgentCapabilityUnavailable)]
    [InlineData(true, AsrProviderAvailability.Ready, true, LlmAgentCapabilityStatus.Unsupported, AgentComposeReadinessStatus.AgentCapabilityUnavailable)]
    public async Task A_missing_dependency_does_not_start_microphone(
        bool sidecarAvailable,
        AsrProviderAvailability asrAvailability,
        bool hasDefaultProvider,
        LlmAgentCapabilityStatus agentCapability,
        AgentComposeReadinessStatus expected)
    {
        var starts = 0;
        var result = await new AgentComposeReadinessGate().StartIfReadyAsync(
            new AgentComposeReadinessInput(sidecarAvailable, asrAvailability, hasDefaultProvider, agentCapability),
            _ =>
            {
                starts++;
                return Task.CompletedTask;
            },
            CancellationToken.None);

        Assert.Equal(expected, result.Status);
        Assert.False(result.CanStartRecording);
        Assert.Equal(0, starts);
    }

    [Fact]
    public async Task A_ready_agent_starts_microphone_once()
    {
        var starts = 0;
        var result = await new AgentComposeReadinessGate().StartIfReadyAsync(
            new AgentComposeReadinessInput(
                SidecarAvailable: true,
                AsrAvailability: AsrProviderAvailability.Ready,
                HasDefaultProvider: true,
                AgentCapabilityStatus: LlmAgentCapabilityStatus.Supported),
            _ =>
            {
                starts++;
                return Task.CompletedTask;
            },
            CancellationToken.None);

        Assert.True(result.CanStartRecording);
        Assert.Equal(1, starts);
    }
}
