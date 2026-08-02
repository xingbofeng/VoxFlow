using VoxFlow.Windows.Application.Credentials;

namespace VoxFlow.Windows.Application.Llm;

public static class LlmProviderCredentialKeys
{
    public const string OwnerKind = "llm-provider";
    public const string ApiKeyFieldId = "api_key";

    public static CredentialKey ApiKey(string providerId) => new(
        OwnerKind,
        NormalizeProviderId(providerId),
        ApiKeyFieldId);

    public static string Reference(string providerId) => string.Concat(
        OwnerKind,
        "/",
        NormalizeProviderId(providerId),
        "/",
        ApiKeyFieldId);

    private static string NormalizeProviderId(string providerId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);
        var normalized = providerId.Trim();
        if (normalized.Contains('/', StringComparison.Ordinal)
            || normalized.Contains('\\', StringComparison.Ordinal)
            || normalized.Contains('\r', StringComparison.Ordinal)
            || normalized.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "A provider id must be a single path-safe segment.",
                nameof(providerId));
        }
        return normalized;
    }
}

public sealed class LlmProviderCredentialPersistenceException : Exception
{
    public LlmProviderCredentialPersistenceException(
        string safeMessage,
        Exception? innerException = null)
        : base(safeMessage, innerException)
    {
    }
}

public interface ILlmProviderCredentialService
{
    Task<CredentialPresentation> GetPresentationAsync(
        string providerId,
        CancellationToken cancellationToken = default);

    Task<string?> RevealApiKeyAsync(
        string providerId,
        CancellationToken cancellationToken = default);

    Task SaveAsync(
        LlmProviderRecord provider,
        string apiKey,
        CancellationToken cancellationToken = default);

    Task SaveProviderAsync(
        LlmProviderRecord provider,
        string? apiKey,
        bool requiresApiKey,
        bool retainExistingCredential,
        CancellationToken cancellationToken = default);

    Task<bool> DeleteAsync(
        string providerId,
        CancellationToken cancellationToken = default);
}

public sealed class LlmProviderCredentialService : ILlmProviderCredentialService
{
    private readonly ICredentialVault credentialVault;
    private readonly ILlmProviderRepository providerRepository;

    public LlmProviderCredentialService(
        ICredentialVault credentialVault,
        ILlmProviderRepository providerRepository)
    {
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.providerRepository = providerRepository
            ?? throw new ArgumentNullException(nameof(providerRepository));
    }

    public Task<CredentialPresentation> GetPresentationAsync(
        string providerId,
        CancellationToken cancellationToken = default) =>
        credentialVault.GetPresentationAsync(
            LlmProviderCredentialKeys.ApiKey(providerId),
            cancellationToken);

    public Task<string?> RevealApiKeyAsync(
        string providerId,
        CancellationToken cancellationToken = default) =>
        credentialVault.ReadSecretAsync(
            LlmProviderCredentialKeys.ApiKey(providerId),
            cancellationToken);

    public async Task SaveAsync(
        LlmProviderRecord provider,
        string apiKey,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        cancellationToken.ThrowIfCancellationRequested();

        var key = LlmProviderCredentialKeys.ApiKey(provider.Id);
        var previous = await credentialVault.ReadSecretAsync(key, cancellationToken)
            .ConfigureAwait(false);
        await credentialVault.SaveAsync(key, apiKey.Trim(), cancellationToken)
            .ConfigureAwait(false);

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            providerRepository.Upsert(WithCredentialReference(
                provider,
                LlmProviderCredentialKeys.Reference(provider.Id)));
        }
        catch (Exception metadataFailure)
        {
            Exception? rollbackFailure = null;
            try
            {
                if (previous is null)
                {
                    await credentialVault.DeleteAsync(key, CancellationToken.None)
                        .ConfigureAwait(false);
                }
                else
                {
                    await credentialVault.SaveAsync(
                            key,
                            previous,
                            CancellationToken.None)
                        .ConfigureAwait(false);
                }
            }
            catch (Exception exception)
            {
                rollbackFailure = exception;
            }

            if (metadataFailure is OperationCanceledException
                && rollbackFailure is null)
            {
                throw;
            }

            var failure = rollbackFailure is null
                ? metadataFailure
                : new AggregateException(metadataFailure, rollbackFailure);
            throw new LlmProviderCredentialPersistenceException(
                rollbackFailure is null
                    ? "Provider metadata was not saved; credential [REDACTED] was restored."
                    : "Provider metadata was not saved and credential [REDACTED] rollback failed.",
                failure);
        }
    }

    public async Task SaveProviderAsync(
        LlmProviderRecord provider,
        string? apiKey,
        bool requiresApiKey,
        bool retainExistingCredential,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(provider);
        cancellationToken.ThrowIfCancellationRequested();
        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            await SaveAsync(provider, apiKey, cancellationToken)
                .ConfigureAwait(false);
            return;
        }

        var key = LlmProviderCredentialKeys.ApiKey(provider.Id);
        if (requiresApiKey)
        {
            if (!retainExistingCredential)
            {
                throw new ArgumentException(
                    "An API key is required for this provider.",
                    nameof(apiKey));
            }
            var presentation = await credentialVault.GetPresentationAsync(
                    key,
                    cancellationToken)
                .ConfigureAwait(false);
            if (presentation.Availability != CredentialAvailability.Available)
            {
                throw new CredentialUnavailableException();
            }
            providerRepository.Upsert(WithCredentialReference(
                provider,
                LlmProviderCredentialKeys.Reference(provider.Id)));
            return;
        }

        var previous = providerRepository.Get(provider.Id);
        providerRepository.Upsert(WithCredentialReference(
            provider,
            credentialReference: null));
        try
        {
            _ = await credentialVault.DeleteOwnerAsync(
                    key.OwnerKind,
                    key.OwnerId,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception credentialFailure)
        {
            Exception? rollbackFailure = null;
            try
            {
                if (previous is null)
                {
                    _ = providerRepository.Delete(provider.Id);
                }
                else
                {
                    providerRepository.Upsert(previous);
                }
            }
            catch (Exception exception)
            {
                rollbackFailure = exception;
            }

            throw new LlmProviderCredentialPersistenceException(
                "Keyless provider save failed while clearing credential [REDACTED].",
                rollbackFailure is null
                    ? credentialFailure
                    : new AggregateException(credentialFailure, rollbackFailure));
        }
    }

    public async Task<bool> DeleteAsync(
        string providerId,
        CancellationToken cancellationToken = default)
    {
        var key = LlmProviderCredentialKeys.ApiKey(providerId);
        cancellationToken.ThrowIfCancellationRequested();
        var existing = providerRepository.Get(providerId);
        var metadataDeleted = providerRepository.Delete(providerId);

        try
        {
            var credentialCount = await credentialVault.DeleteOwnerAsync(
                    key.OwnerKind,
                    key.OwnerId,
                    cancellationToken)
                .ConfigureAwait(false);
            return metadataDeleted || credentialCount > 0;
        }
        catch (Exception credentialFailure)
        {
            Exception? rollbackFailure = null;
            if (metadataDeleted && existing is not null)
            {
                try
                {
                    providerRepository.Upsert(existing);
                }
                catch (Exception exception)
                {
                    rollbackFailure = exception;
                }
            }

            var failure = rollbackFailure is null
                ? credentialFailure
                : new AggregateException(credentialFailure, rollbackFailure);
            throw new LlmProviderCredentialPersistenceException(
                rollbackFailure is null
                    ? "Provider deletion failed; credential [REDACTED] and metadata were retained."
                    : "Provider deletion failed and metadata rollback for credential [REDACTED] failed.",
                failure);
        }
    }

    private static LlmProviderRecord WithCredentialReference(
        LlmProviderRecord provider,
        string? credentialReference) => new(
        provider.Id,
        provider.DisplayName,
        provider.ProviderType,
        provider.BaseUri,
        provider.DefaultModel,
        credentialReference,
        provider.Temperature,
        provider.TimeoutSeconds,
        provider.Enabled,
        provider.IsDefault,
        provider.HealthStatus,
        provider.HealthMessage,
        provider.HealthLatencyMs,
        provider.HealthCheckedAtUnixMs,
        provider.AgentCapabilityStatus,
        provider.AgentCapabilityMessage,
        provider.AgentCapabilityCheckedAtUnixMs,
        provider.CreatedAtUnixMs,
        provider.UpdatedAtUnixMs);
}
