using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Cloud.OpenAI;

public sealed class OpenAiFileTranscriptionTranslator
    : IFileTranscriptionTranslator
{
    private readonly ICredentialVault credentialVault;
    private readonly ILlmProviderSettingsStore settingsStore;
    private readonly OpenAiChatCompletionsClient client;

    public OpenAiFileTranscriptionTranslator(
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

    public async ValueTask<string> TranslateAsync(
        string text,
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        var target = NormalizeTargetLanguage(targetLanguage);
        var settings = await settingsStore.LoadAsync(
            LlmProviderId.OpenAI,
            cancellationToken).ConfigureAwait(false);
        if (settings is null || !settings.Enabled)
        {
            throw new FileTranscriptionTranslationUnavailableException();
        }

        string? apiKey;
        try
        {
            apiKey = await credentialVault.ReadSecretAsync(
                OpenAiCredentialKeys.ApiKey,
                cancellationToken).ConfigureAwait(false);
        }
        catch (CredentialUnavailableException)
        {
            throw new FileTranscriptionTranslationUnavailableException();
        }
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new FileTranscriptionTranslationUnavailableException();
        }

        var configuration = new OpenAiClientConfiguration(
            settings.BaseUri,
            settings.Model,
            apiKey);
        var instruction =
            $"Translate the user's text into {target}. Preserve meaning, facts, names, " +
            "numbers, code, paragraph structure, and formatting. Do not summarize or add " +
            "commentary. Return only the complete translation.";
        string? final = null;
        await foreach (var snapshot in client.StreamChatAsync(
            configuration,
            instruction,
            text,
            cancellationToken).WithCancellation(cancellationToken).ConfigureAwait(false))
        {
            if (!string.IsNullOrWhiteSpace(snapshot))
            {
                final = snapshot;
            }
        }

        return !string.IsNullOrWhiteSpace(final)
            ? final
            : throw new OpenAiClientException(OpenAiClientError.EmptyResponse);
    }

    private static string NormalizeTargetLanguage(string targetLanguage)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(targetLanguage);
        var target = targetLanguage.Trim();
        if (target.Length is < 2 or > 35
            || target.Any(character =>
                !char.IsAsciiLetterOrDigit(character) && character != '-'))
        {
            throw new ArgumentException(
                "A BCP-47 target language is required.",
                nameof(targetLanguage));
        }
        return target;
    }
}
