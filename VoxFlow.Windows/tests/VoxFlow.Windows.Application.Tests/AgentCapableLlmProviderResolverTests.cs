using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentCapableLlmProviderResolverTests
{
    [Theory]
    [InlineData(LlmAgentCapabilityStatus.Unknown)]
    [InlineData(LlmAgentCapabilityStatus.Unsupported)]
    [InlineData(LlmAgentCapabilityStatus.Error)]
    public async Task Text_capable_provider_is_not_resolved_for_Agent_until_tool_calling_is_supported(
        LlmAgentCapabilityStatus capability)
    {
        var inner = new CapturingResolver(Configuration());
        var resolver = new AgentCapableLlmProviderResolver(
            new Repository(Provider(capability)),
            inner);

        var result = await resolver.ResolveDefaultAsync(CancellationToken.None);

        Assert.Null(result);
        Assert.Equal(0, inner.ResolveCalls);
    }

    [Fact]
    public async Task Supported_default_provider_is_resolved_once_for_Agent()
    {
        var configuration = Configuration();
        var inner = new CapturingResolver(configuration);
        var resolver = new AgentCapableLlmProviderResolver(
            new Repository(Provider(LlmAgentCapabilityStatus.Supported)),
            inner);

        var result = await resolver.ResolveDefaultAsync(CancellationToken.None);

        Assert.Same(configuration, result);
        Assert.Equal(1, inner.ResolveCalls);
    }

    [Fact]
    public async Task Capability_change_during_credential_resolution_rejects_the_provider()
    {
        var repository = new Repository(Provider(LlmAgentCapabilityStatus.Supported));
        var inner = new CapturingResolver(Configuration(), () =>
            repository.Provider = Provider(LlmAgentCapabilityStatus.Unsupported));
        var resolver = new AgentCapableLlmProviderResolver(repository, inner);

        var result = await resolver.ResolveDefaultAsync(CancellationToken.None);

        Assert.Null(result);
        Assert.Equal(1, inner.ResolveCalls);
    }

    private static LlmProviderClientConfiguration Configuration() => new(
        "provider",
        new Uri("https://example.test/v1"),
        "model",
        "secret",
        0.2,
        TimeSpan.FromSeconds(30));

    private static LlmProviderRecord Provider(LlmAgentCapabilityStatus capability) => new(
        "provider",
        "Provider",
        LlmProviderType.OpenAiCompatible,
        new Uri("https://example.test/v1"),
        "model",
        "llm-provider/provider/api_key",
        0.2,
        30,
        enabled: true,
        isDefault: true,
        LlmProviderHealthStatus.Ok,
        null,
        1,
        100,
        capability,
        null,
        100,
        100,
        100);

    private sealed class CapturingResolver(
        LlmProviderClientConfiguration configuration,
        Action? beforeReturn = null) : IDefaultLlmProviderResolver
    {
        public int ResolveCalls { get; private set; }

        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ResolveCalls++;
            beforeReturn?.Invoke();
            return ValueTask.FromResult<LlmProviderClientConfiguration?>(configuration);
        }
    }

    private sealed class Repository(LlmProviderRecord? provider) : ILlmProviderRepository
    {
        public LlmProviderRecord? Provider { get; set; } = provider;

        public IReadOnlyList<LlmProviderRecord> List() => Provider is null ? [] : [Provider];

        public LlmProviderRecord? Get(string providerId) =>
            string.Equals(Provider?.Id, providerId, StringComparison.Ordinal) ? Provider : null;

        public LlmProviderRecord? GetDefault() => Provider;

        public void Upsert(LlmProviderRecord providerRecord) => Provider = providerRecord;

        public bool Delete(string providerId) => false;

        public bool SetEnabled(string providerId, bool enabled, long updatedAtUnixMs) => false;

        public bool SetDefault(string providerId, long updatedAtUnixMs) => false;

        public bool UpdateHealth(string providerId, LlmProviderHealthUpdate update) => false;

        public bool UpdateAgentCapability(string providerId, LlmAgentCapabilityUpdate update) => false;
    }
}
