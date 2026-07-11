using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Cloud.OpenAI;

public sealed class OpenAiStreamingTextRefiner : IStreamingTextRefiner
{
    private readonly ICredentialVault credentialVault;
    private readonly ILlmProviderSettingsStore settingsStore;
    private readonly OpenAiChatCompletionsClient client;

    public OpenAiStreamingTextRefiner(
        ICredentialVault credentialVault,
        ILlmProviderSettingsStore settingsStore,
        OpenAiChatCompletionsClient client)
    {
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.settingsStore = settingsStore
            ?? throw new ArgumentNullException(nameof(settingsStore));
        this.client = client ?? throw new ArgumentNullException(nameof(client));
    }

    public async ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
        CancellationToken cancellationToken)
    {
        var settings = await settingsStore.LoadAsync(
                LlmProviderId.OpenAI,
                cancellationToken)
            .ConfigureAwait(false);
        if (settings is null)
        {
            return LlmRefinerAvailability.NotConfigured;
        }

        var credential = await credentialVault.GetPresentationAsync(
                OpenAiCredentialKeys.ApiKey,
                cancellationToken)
            .ConfigureAwait(false);
        if (credential.Availability != CredentialAvailability.Available)
        {
            return LlmRefinerAvailability.NotConfigured;
        }

        return settings.Enabled
            ? LlmRefinerAvailability.Ready
            : LlmRefinerAvailability.Disabled;
    }

    public async IAsyncEnumerable<string> RefineAsync(
        string text,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        var settings = await settingsStore.LoadAsync(
                LlmProviderId.OpenAI,
                cancellationToken)
            .ConfigureAwait(false)
            ?? throw new InvalidOperationException("OpenAI is not configured.");
        if (!settings.Enabled)
        {
            throw new InvalidOperationException("OpenAI text refinement is disabled.");
        }

        var apiKey = await credentialVault.ReadSecretAsync(
                OpenAiCredentialKeys.ApiKey,
                cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("OpenAI is not configured.");
        }

        var configuration = new OpenAiClientConfiguration(
            OpenAiProductionDefaults.BaseUri,
            settings.Model,
            apiKey);
        await foreach (var snapshot in client
            .StreamRefinementAsync(configuration, text, cancellationToken)
            .WithCancellation(cancellationToken)
            .ConfigureAwait(false))
        {
            yield return snapshot;
        }
    }
}
