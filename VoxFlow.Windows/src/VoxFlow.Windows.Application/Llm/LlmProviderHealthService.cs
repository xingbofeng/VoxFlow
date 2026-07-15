namespace VoxFlow.Windows.Application.Llm;

public sealed class LlmProviderHealthService
{
    private readonly ILlmConnectionTester connectionTester;
    private readonly ILlmAgentCapabilityTester agentCapabilityTester;
    private readonly ILlmProviderRepository providerRepository;
    private readonly TimeProvider timeProvider;

    public LlmProviderHealthService(
        ILlmConnectionTester connectionTester,
        ILlmAgentCapabilityTester agentCapabilityTester,
        ILlmProviderRepository providerRepository,
        TimeProvider? timeProvider = null)
    {
        this.connectionTester = connectionTester
            ?? throw new ArgumentNullException(nameof(connectionTester));
        this.agentCapabilityTester = agentCapabilityTester
            ?? throw new ArgumentNullException(nameof(agentCapabilityTester));
        this.providerRepository = providerRepository
            ?? throw new ArgumentNullException(nameof(providerRepository));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async ValueTask<LlmConnectionTestResult> TestConnectionAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var result = await connectionTester.TestConnectionAsync(
                configuration,
                cancellationToken)
            .ConfigureAwait(false);
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        if (!providerRepository.UpdateHealth(
            configuration.ProviderId,
            new LlmProviderHealthUpdate(
                result.Succeeded
                    ? LlmProviderHealthStatus.Ok
                    : LlmProviderHealthStatus.Error,
                result.SafeMessage,
                result.LatencyMs,
                now,
                now)))
        {
            throw new InvalidOperationException(
                "The provider changed before connection health could be saved.");
        }
        return result;
    }

    public async ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var result = await agentCapabilityTester.TestAgentCapabilityAsync(
                configuration,
                cancellationToken)
            .ConfigureAwait(false);
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        if (!providerRepository.UpdateAgentCapability(
            configuration.ProviderId,
            new LlmAgentCapabilityUpdate(
                result.Status,
                result.SafeMessage,
                now,
                now)))
        {
            throw new InvalidOperationException(
                "The provider changed before Agent capability could be saved.");
        }
        return result;
    }
}
