using VoxFlow.Windows.Application.Credentials;

namespace VoxFlow.Windows.Application.Llm;

public sealed class LlmProviderDraft
{
    public LlmProviderDraft(
        string? providerId,
        string templateId,
        string displayName,
        string baseUrl,
        string model,
        double temperature,
        int timeoutSeconds,
        bool enabled,
        bool isDefault)
    {
        ValidateOptionalSingleLine(providerId, nameof(providerId));
        ValidateSingleLine(templateId, nameof(templateId));
        ValidateSingleLine(displayName, nameof(displayName));
        ValidateSingleLine(baseUrl, nameof(baseUrl));
        ValidateSingleLine(model, nameof(model));
        if (!double.IsFinite(temperature) || temperature is < 0 or > 2)
        {
            throw new ArgumentOutOfRangeException(nameof(temperature));
        }
        if (timeoutSeconds is < 1 or > 600)
        {
            throw new ArgumentOutOfRangeException(nameof(timeoutSeconds));
        }
        if (isDefault && !enabled)
        {
            throw new ArgumentException(
                "A disabled provider cannot be the default.",
                nameof(isDefault));
        }

        ProviderId = providerId?.Trim();
        TemplateId = templateId.Trim();
        DisplayName = displayName.Trim();
        BaseUrl = baseUrl.Trim();
        Model = model.Trim();
        Temperature = temperature;
        TimeoutSeconds = timeoutSeconds;
        Enabled = enabled;
        IsDefault = isDefault;
    }

    public string? ProviderId { get; }

    public string TemplateId { get; }

    public string DisplayName { get; }

    public string BaseUrl { get; }

    public string Model { get; }

    public double Temperature { get; }

    public int TimeoutSeconds { get; }

    public bool Enabled { get; }

    public bool IsDefault { get; }

    public override string ToString() =>
        $"LlmProviderDraft {{ ProviderId = {ProviderId}, TemplateId = {TemplateId}, DisplayName = {DisplayName}, Secret = [REDACTED] }}";

    private static void ValidateOptionalSingleLine(
        string? value,
        string parameterName)
    {
        if (value is not null)
        {
            ValidateSingleLine(value, parameterName);
        }
    }

    private static void ValidateSingleLine(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (value.Contains('\r', StringComparison.Ordinal)
            || value.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "The value must be a single line.",
                parameterName);
        }
    }
}

public interface ILlmProviderManagementService
{
    IReadOnlyList<LlmProviderRecord> List();

    Task<LlmProviderRecord> SaveAsync(
        LlmProviderDraft draft,
        string? apiKey,
        bool retainExistingCredential,
        CancellationToken cancellationToken);

    bool SetDefault(string providerId);

    bool SetEnabled(string providerId, bool enabled);

    Task<bool> DeleteAsync(
        string providerId,
        CancellationToken cancellationToken);

    ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
        string providerId,
        CancellationToken cancellationToken);

    ValueTask<LlmConnectionTestResult> TestConnectionAsync(
        string providerId,
        CancellationToken cancellationToken);

    ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
        string providerId,
        CancellationToken cancellationToken);

    Task<CredentialPresentation> GetCredentialPresentationAsync(
        string providerId,
        CancellationToken cancellationToken);

    Task<string?> RevealApiKeyAsync(
        string providerId,
        CancellationToken cancellationToken);
}

public sealed class LlmProviderManagementService : ILlmProviderManagementService
{
    private readonly ILlmProviderRepository providerRepository;
    private readonly ILlmProviderCredentialService credentialService;
    private readonly ILlmProviderClient providerClient;
    private readonly LlmProviderHealthService healthService;
    private readonly TimeProvider timeProvider;
    private readonly Func<string> idFactory;

    public LlmProviderManagementService(
        ILlmProviderRepository providerRepository,
        ILlmProviderCredentialService credentialService,
        ILlmProviderClient providerClient,
        TimeProvider? timeProvider = null,
        Func<string>? idFactory = null)
    {
        this.providerRepository = providerRepository
            ?? throw new ArgumentNullException(nameof(providerRepository));
        this.credentialService = credentialService
            ?? throw new ArgumentNullException(nameof(credentialService));
        this.providerClient = providerClient
            ?? throw new ArgumentNullException(nameof(providerClient));
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.idFactory = idFactory ?? (() => Guid.NewGuid().ToString("N"));
        healthService = new LlmProviderHealthService(
            providerClient,
            providerClient,
            providerRepository,
            this.timeProvider);
    }

    public IReadOnlyList<LlmProviderRecord> List() => providerRepository.List();

    public async Task<LlmProviderRecord> SaveAsync(
        LlmProviderDraft draft,
        string? apiKey,
        bool retainExistingCredential,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(draft);
        cancellationToken.ThrowIfCancellationRequested();
        var template = LlmProviderTemplateCatalog.Find(draft.TemplateId)
            ?? throw new ArgumentException(
                "The selected provider template does not exist.",
                nameof(draft));
        var endpoint = LlmProviderEndpoint.Normalize(draft.BaseUrl);
        var existing = draft.ProviderId is null
            ? null
            : providerRepository.Get(draft.ProviderId)
                ?? throw new InvalidOperationException(
                    "The provider being edited no longer exists.");
        var providerId = existing?.Id ?? CreateProviderId();
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        var sameRuntime = existing is not null
            && existing.BaseUri == endpoint
            && string.Equals(
                existing.DefaultModel,
                draft.Model,
                StringComparison.Ordinal);
        var requiresApiKey = template.IsCustom
            ? !endpoint.IsLoopback
            : template.RequiresApiKey;
        var provider = new LlmProviderRecord(
            providerId,
            draft.DisplayName,
            LlmProviderType.OpenAiCompatible,
            endpoint,
            draft.Model,
            requiresApiKey
                ? LlmProviderCredentialKeys.Reference(providerId)
                : null,
            draft.Temperature,
            draft.TimeoutSeconds,
            draft.Enabled,
            draft.IsDefault,
            sameRuntime
                ? existing!.HealthStatus
                : LlmProviderHealthStatus.Unknown,
            sameRuntime ? existing!.HealthMessage : null,
            sameRuntime ? existing!.HealthLatencyMs : null,
            sameRuntime ? existing!.HealthCheckedAtUnixMs : null,
            sameRuntime
                ? existing!.AgentCapabilityStatus
                : LlmAgentCapabilityStatus.Unknown,
            sameRuntime ? existing!.AgentCapabilityMessage : null,
            sameRuntime ? existing!.AgentCapabilityCheckedAtUnixMs : null,
            existing?.CreatedAtUnixMs ?? now,
            now);
        await credentialService.SaveProviderAsync(
                provider,
                apiKey,
                requiresApiKey,
                retainExistingCredential,
                cancellationToken)
            .ConfigureAwait(false);
        return providerRepository.Get(providerId)
            ?? throw new InvalidOperationException(
                "The saved provider could not be reloaded.");
    }

    public bool SetDefault(string providerId) => providerRepository.SetDefault(
        providerId,
        Now());

    public bool SetEnabled(string providerId, bool enabled) =>
        providerRepository.SetEnabled(providerId, enabled, Now());

    public Task<bool> DeleteAsync(
        string providerId,
        CancellationToken cancellationToken) =>
        credentialService.DeleteAsync(providerId, cancellationToken);

    public async ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
        string providerId,
        CancellationToken cancellationToken) =>
        await providerClient.DiscoverModelsAsync(
                await ConfigurationAsync(providerId, cancellationToken)
                    .ConfigureAwait(false),
                cancellationToken)
            .ConfigureAwait(false);

    public async ValueTask<LlmConnectionTestResult> TestConnectionAsync(
        string providerId,
        CancellationToken cancellationToken) =>
        await healthService.TestConnectionAsync(
                await ConfigurationAsync(providerId, cancellationToken)
                    .ConfigureAwait(false),
                cancellationToken)
            .ConfigureAwait(false);

    public async ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
        string providerId,
        CancellationToken cancellationToken) =>
        await healthService.TestAgentCapabilityAsync(
                await ConfigurationAsync(providerId, cancellationToken)
                    .ConfigureAwait(false),
                cancellationToken)
            .ConfigureAwait(false);

    public Task<CredentialPresentation> GetCredentialPresentationAsync(
        string providerId,
        CancellationToken cancellationToken) =>
        credentialService.GetPresentationAsync(providerId, cancellationToken);

    public Task<string?> RevealApiKeyAsync(
        string providerId,
        CancellationToken cancellationToken) =>
        credentialService.RevealApiKeyAsync(providerId, cancellationToken);

    private async ValueTask<LlmProviderClientConfiguration> ConfigurationAsync(
        string providerId,
        CancellationToken cancellationToken)
    {
        var provider = providerRepository.Get(providerId)
            ?? throw new InvalidOperationException("The provider no longer exists.");
        if (provider.BaseUri is null
            || string.IsNullOrWhiteSpace(provider.DefaultModel))
        {
            throw new InvalidOperationException(
                "The provider endpoint or model is not configured.");
        }
        var apiKey = await credentialService.RevealApiKeyAsync(
                providerId,
                cancellationToken)
            .ConfigureAwait(false);
        if (!provider.BaseUri.IsLoopback && string.IsNullOrWhiteSpace(apiKey))
        {
            throw new CredentialUnavailableException();
        }
        return new LlmProviderClientConfiguration(
            provider.Id,
            provider.BaseUri,
            provider.DefaultModel,
            apiKey,
            provider.Temperature,
            TimeSpan.FromSeconds(provider.TimeoutSeconds));
    }

    private string CreateProviderId()
    {
        var id = idFactory();
        _ = LlmProviderCredentialKeys.Reference(id);
        if (providerRepository.Get(id) is not null)
        {
            throw new InvalidOperationException(
                "The generated provider id already exists.");
        }
        return id;
    }

    private long Now() => timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
}
