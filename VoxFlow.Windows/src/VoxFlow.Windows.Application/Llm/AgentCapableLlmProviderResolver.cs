namespace VoxFlow.Windows.Application.Llm;

/// <summary>
/// Narrows the normal default-provider resolver to a provider that has passed
/// the explicit Agent tool-calling capability test. Text-only consumers keep
/// using <see cref="DefaultLlmProviderResolver"/> directly.
/// </summary>
public sealed class AgentCapableLlmProviderResolver : IDefaultLlmProviderResolver
{
    private readonly ILlmProviderRepository providers;
    private readonly IDefaultLlmProviderResolver inner;

    public AgentCapableLlmProviderResolver(
        ILlmProviderRepository providers,
        IDefaultLlmProviderResolver inner)
    {
        this.providers = providers ?? throw new ArgumentNullException(nameof(providers));
        this.inner = inner ?? throw new ArgumentNullException(nameof(inner));
    }

    public async ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var approved = providers.GetDefault();
        if (!IsAgentCapable(approved))
        {
            return null;
        }

        var configuration = await inner.ResolveDefaultAsync(cancellationToken)
            .ConfigureAwait(false);
        if (configuration is null
            || !string.Equals(configuration.ProviderId, approved!.Id, StringComparison.Ordinal))
        {
            return null;
        }

        // The default or its tested capability can change while a credential
        // is being revealed. Re-read it before returning secret-bearing state.
        var current = providers.GetDefault();
        return IsAgentCapable(current)
               && string.Equals(current!.Id, configuration.ProviderId, StringComparison.Ordinal)
            ? configuration
            : null;
    }

    private static bool IsAgentCapable(LlmProviderRecord? provider) =>
        provider is
        {
            Enabled: true,
            IsDefault: true,
            AgentCapabilityStatus: LlmAgentCapabilityStatus.Supported,
        };
}
