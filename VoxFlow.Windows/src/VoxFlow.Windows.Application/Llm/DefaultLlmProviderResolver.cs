namespace VoxFlow.Windows.Application.Llm;

/// <summary>
/// Resolves the enabled default provider once per operation. Credentials stay
/// in the vault until this boundary and are never returned through settings or
/// diagnostics; an absent or unreadable required credential simply makes the
/// provider unavailable before a transform can open a network connection.
/// </summary>
public sealed class DefaultLlmProviderResolver : IDefaultLlmProviderResolver
{
    private readonly ILlmProviderRepository providers;
    private readonly ILlmProviderCredentialService credentials;

    public DefaultLlmProviderResolver(
        ILlmProviderRepository providers,
        ILlmProviderCredentialService credentials)
    {
        this.providers = providers ?? throw new ArgumentNullException(nameof(providers));
        this.credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
    }

    public async ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var provider = providers.GetDefault();
        if (provider is null
            || !provider.Enabled
            || provider.ProviderType != LlmProviderType.OpenAiCompatible
            || provider.BaseUri is null
            || string.IsNullOrWhiteSpace(provider.DefaultModel))
        {
            return null;
        }

        string? apiKey = null;
        if (!string.IsNullOrWhiteSpace(provider.ApiKeyRef))
        {
            try
            {
                apiKey = await credentials.RevealApiKeyAsync(provider.Id, cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                return null;
            }

            if (string.IsNullOrWhiteSpace(apiKey))
            {
                return null;
            }
        }

        return new LlmProviderClientConfiguration(
            provider.Id,
            provider.BaseUri,
            provider.DefaultModel,
            apiKey,
            provider.Temperature,
            TimeSpan.FromSeconds(provider.TimeoutSeconds));
    }
}
