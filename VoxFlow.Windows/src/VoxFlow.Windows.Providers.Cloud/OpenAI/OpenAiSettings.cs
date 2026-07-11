using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Cloud.OpenAI;

public static class OpenAiProductionDefaults
{
    public const string DefaultModel = "gpt-4.1-mini";

    public static Uri BaseUri { get; } = new("https://api.openai.com/v1");
}

public static class OpenAiCredentialKeys
{
    public const string OwnerKind = "llm";
    public const string OwnerId = "openai";

    public static CredentialKey ApiKey { get; } = new(
        OwnerKind,
        OwnerId,
        "api_key");
}

public sealed class OpenAiClientConfiguration
{
    public OpenAiClientConfiguration(Uri baseUri, string model, string apiKey)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        ArgumentException.ThrowIfNullOrWhiteSpace(model);
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        if (!baseUri.IsAbsoluteUri
            || !string.Equals(baseUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("An HTTPS OpenAI base URL is required.", nameof(baseUri));
        }

        BaseUri = new Uri(baseUri.AbsoluteUri.TrimEnd('/'), UriKind.Absolute);
        Model = model.Trim();
        ApiKey = apiKey.Trim();
    }

    public Uri BaseUri { get; }

    public string Model { get; }

    public string ApiKey { get; }

    public override string ToString() =>
        $"OpenAiClientConfiguration {{ Endpoint = {BaseUri.Host}, Model = {Model}, ApiKey = [REDACTED] }}";
}

public sealed record OpenAiSettingsStatus(
    Uri BaseUri,
    string Model,
    bool Enabled,
    CredentialPresentation ApiKey)
{
    public bool IsConfigured =>
        ApiKey.Availability == CredentialAvailability.Available;

    public bool CanTestConnection => IsConfigured;
}

public enum OpenAiConnectionTestError
{
    None,
    NotConfigured,
    CredentialsUnavailable,
    ConnectionFailed,
}

public sealed record OpenAiConnectionTestResult(
    bool Succeeded,
    OpenAiConnectionTestError Error)
{
    public static OpenAiConnectionTestResult Success { get; } = new(
        true,
        OpenAiConnectionTestError.None);

    public override string ToString() =>
        $"OpenAiConnectionTestResult {{ Succeeded = {Succeeded}, Error = {Error} }}";
}

public interface IOpenAiConnectionTester
{
    ValueTask<OpenAiConnectionTestResult> TestAsync(
        OpenAiClientConfiguration configuration,
        CancellationToken cancellationToken);
}

public sealed class OpenAiSettingsService
{
    private readonly ICredentialVault credentialVault;
    private readonly ILlmProviderSettingsStore settingsStore;
    private readonly IOpenAiConnectionTester connectionTester;

    public OpenAiSettingsService(
        ICredentialVault credentialVault,
        ILlmProviderSettingsStore settingsStore,
        IOpenAiConnectionTester connectionTester)
    {
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.settingsStore = settingsStore
            ?? throw new ArgumentNullException(nameof(settingsStore));
        this.connectionTester = connectionTester
            ?? throw new ArgumentNullException(nameof(connectionTester));
    }

    public async Task SaveAsync(
        string apiKey,
        string model,
        bool enabled,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(model);
        var normalizedKey = apiKey.Trim();
        var settings = new LlmProviderSettings(
            LlmProviderId.OpenAI,
            OpenAiProductionDefaults.BaseUri,
            model,
            enabled);

        await credentialVault.SaveAsync(
                OpenAiCredentialKeys.ApiKey,
                normalizedKey,
                cancellationToken)
            .ConfigureAwait(false);
        try
        {
            await settingsStore.SaveAsync(settings, cancellationToken)
                .ConfigureAwait(false);
        }
        catch
        {
            try
            {
                await credentialVault.DeleteAsync(
                        OpenAiCredentialKeys.ApiKey,
                        CancellationToken.None)
                    .ConfigureAwait(false);
            }
            catch
            {
                // Preserve the original metadata failure; the status still reports
                // incomplete until a valid metadata row can be loaded.
            }

            throw;
        }
    }

    public async Task<OpenAiSettingsStatus> GetStatusAsync(
        CancellationToken cancellationToken)
    {
        var stored = await settingsStore.LoadAsync(
                LlmProviderId.OpenAI,
                cancellationToken)
            .ConfigureAwait(false);
        var key = await credentialVault.GetPresentationAsync(
                OpenAiCredentialKeys.ApiKey,
                cancellationToken)
            .ConfigureAwait(false);
        return new OpenAiSettingsStatus(
            OpenAiProductionDefaults.BaseUri,
            stored?.Model ?? OpenAiProductionDefaults.DefaultModel,
            stored?.Enabled ?? false,
            key);
    }

    public Task<string?> RevealApiKeyAsync(CancellationToken cancellationToken) =>
        credentialVault.ReadSecretAsync(
            OpenAiCredentialKeys.ApiKey,
            cancellationToken);

    public async ValueTask<OpenAiConnectionTestResult> TestConnectionAsync(
        CancellationToken cancellationToken)
    {
        string? apiKey;
        try
        {
            apiKey = await credentialVault.ReadSecretAsync(
                    OpenAiCredentialKeys.ApiKey,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (CredentialUnavailableException)
        {
            return new OpenAiConnectionTestResult(
                false,
                OpenAiConnectionTestError.CredentialsUnavailable);
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return new OpenAiConnectionTestResult(
                false,
                OpenAiConnectionTestError.NotConfigured);
        }

        var status = await GetStatusAsync(cancellationToken).ConfigureAwait(false);
        return await connectionTester.TestAsync(
                new OpenAiClientConfiguration(
                    OpenAiProductionDefaults.BaseUri,
                    status.Model,
                    apiKey),
                cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task DeleteAsync(CancellationToken cancellationToken)
    {
        _ = await credentialVault.DeleteOwnerAsync(
                OpenAiCredentialKeys.OwnerKind,
                OpenAiCredentialKeys.OwnerId,
                cancellationToken)
            .ConfigureAwait(false);
        await settingsStore.DeleteAsync(LlmProviderId.OpenAI, cancellationToken)
            .ConfigureAwait(false);
    }
}
