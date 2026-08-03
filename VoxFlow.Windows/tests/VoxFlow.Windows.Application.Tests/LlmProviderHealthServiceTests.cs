using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class LlmProviderHealthServiceTests
{
    [Fact]
    public async Task Connection_and_Agent_tests_persist_independent_fields_and_timestamps()
    {
        var repository = new CapturingRepository(Provider());
        var client = new FakeHealthClient(
            new LlmConnectionTestResult(
                LlmConnectionTestStatus.Succeeded,
                latencyMs: 42,
                safeMessage: "completion_ok"),
            new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Unsupported,
                safeMessage: "tool_calls_missing"));
        var clock = new ControlledTimeProvider(
            DateTimeOffset.FromUnixTimeMilliseconds(1_000));
        var service = new LlmProviderHealthService(
            client,
            client,
            repository,
            clock);

        var connection = await service.TestConnectionAsync(
            Configuration(),
            CancellationToken.None);

        Assert.True(connection.Succeeded);
        Assert.Equal(LlmProviderHealthStatus.Ok, repository.Health?.Status);
        Assert.Equal(42, repository.Health?.LatencyMs);
        Assert.Equal(1_000, repository.Health?.CheckedAtUnixMs);
        Assert.Null(repository.Agent);

        clock.Advance(TimeSpan.FromMilliseconds(500));
        var agent = await service.TestAgentCapabilityAsync(
            Configuration(),
            CancellationToken.None);

        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, agent.Status);
        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, repository.Agent?.Status);
        Assert.Equal(1_500, repository.Agent?.CheckedAtUnixMs);
        Assert.Equal(LlmProviderHealthStatus.Ok, repository.Health?.Status);
        Assert.Equal(1, client.ConnectionCalls);
        Assert.Equal(1, client.AgentCalls);
    }

    private static LlmProviderClientConfiguration Configuration() => new(
        "provider",
        new Uri("https://example.test/v1"),
        "model-a",
        "key",
        0.2,
        TimeSpan.FromSeconds(30));

    private static LlmProviderRecord Provider() => new(
        "provider",
        "Provider",
        LlmProviderType.OpenAiCompatible,
        new Uri("https://example.test/v1"),
        "model-a",
        "llm-provider/provider/api_key",
        0.2,
        30,
        enabled: true,
        isDefault: true,
        LlmProviderHealthStatus.Unknown,
        null,
        null,
        null,
        LlmAgentCapabilityStatus.Unknown,
        null,
        null,
        100,
        100);

    private sealed class FakeHealthClient(
        LlmConnectionTestResult connection,
        LlmAgentCapabilityTestResult agent)
        : ILlmConnectionTester, ILlmAgentCapabilityTester
    {
        public int ConnectionCalls { get; private set; }

        public int AgentCalls { get; private set; }

        public ValueTask<LlmConnectionTestResult> TestConnectionAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            ConnectionCalls++;
            return ValueTask.FromResult(connection);
        }

        public ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            AgentCalls++;
            return ValueTask.FromResult(agent);
        }
    }

    private sealed class CapturingRepository(LlmProviderRecord provider)
        : ILlmProviderRepository
    {
        public LlmProviderHealthUpdate? Health { get; private set; }

        public LlmAgentCapabilityUpdate? Agent { get; private set; }

        public IReadOnlyList<LlmProviderRecord> List() => [provider];

        public LlmProviderRecord? Get(string providerId) =>
            provider.Id == providerId ? provider : null;

        public LlmProviderRecord? GetDefault() => provider;

        public void Upsert(LlmProviderRecord value) => provider = value;

        public bool Delete(string providerId) => false;

        public bool SetEnabled(string providerId, bool enabled, long updatedAtUnixMs) =>
            false;

        public bool SetDefault(string providerId, long updatedAtUnixMs) => false;

        public bool UpdateHealth(
            string providerId,
            LlmProviderHealthUpdate update)
        {
            Health = update;
            return provider.Id == providerId;
        }

        public bool UpdateAgentCapability(
            string providerId,
            LlmAgentCapabilityUpdate update)
        {
            Agent = update;
            return provider.Id == providerId;
        }
    }
}
