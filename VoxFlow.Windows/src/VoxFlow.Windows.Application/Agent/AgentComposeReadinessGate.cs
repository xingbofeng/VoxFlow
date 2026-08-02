using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.Agent;

public enum AgentComposeReadinessStatus
{
    Ready,
    SidecarUnavailable,
    AsrUnavailable,
    DefaultProviderUnavailable,
    AgentCapabilityUnavailable,
}

public sealed record AgentComposeReadinessInput(
    bool SidecarAvailable,
    AsrProviderAvailability AsrAvailability,
    bool HasDefaultProvider,
    LlmAgentCapabilityStatus AgentCapabilityStatus);

public sealed record AgentComposeReadinessResult(AgentComposeReadinessStatus Status)
{
    public bool CanStartRecording => Status == AgentComposeReadinessStatus.Ready;
}

/// <summary>
/// Evaluates every Agent-only dependency before any microphone operation is
/// started. Text transforms can still use a normal completion-only provider;
/// Agent Compose requires an explicitly supported tool-calling provider.
/// </summary>
public sealed class AgentComposeReadinessGate
{
    public AgentComposeReadinessResult Evaluate(AgentComposeReadinessInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        if (!input.SidecarAvailable)
        {
            return new(AgentComposeReadinessStatus.SidecarUnavailable);
        }
        if (input.AsrAvailability != AsrProviderAvailability.Ready)
        {
            return new(AgentComposeReadinessStatus.AsrUnavailable);
        }
        if (!input.HasDefaultProvider)
        {
            return new(AgentComposeReadinessStatus.DefaultProviderUnavailable);
        }
        if (input.AgentCapabilityStatus != LlmAgentCapabilityStatus.Supported)
        {
            return new(AgentComposeReadinessStatus.AgentCapabilityUnavailable);
        }
        return new(AgentComposeReadinessStatus.Ready);
    }

    public async Task<AgentComposeReadinessResult> StartIfReadyAsync(
        AgentComposeReadinessInput input,
        Func<CancellationToken, Task> startRecording,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(startRecording);
        var result = Evaluate(input);
        if (!result.CanStartRecording)
        {
            return result;
        }

        await startRecording(cancellationToken).ConfigureAwait(false);
        return result;
    }
}
