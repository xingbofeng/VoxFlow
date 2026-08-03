using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Cloud.OpenAI;

public sealed class OpenAiStreamingTextRefiner : IStreamingTextRefiner
{
    private readonly ICredentialVault? credentialVault;
    private readonly ILlmProviderSettingsStore? settingsStore;
    private readonly OpenAiChatCompletionsClient? client;
    private readonly IDefaultLlmProviderResolver? providerResolver;
    private readonly ILlmStreamingClient? streamingClient;
    private readonly IGlossaryStore? glossaryStore;
    private readonly IWritingStyleStore? writingStyleStore;
    private readonly Func<WritingStyleApplicationContext?> applicationContextProvider;

    public OpenAiStreamingTextRefiner(
        ICredentialVault credentialVault,
        ILlmProviderSettingsStore settingsStore,
        OpenAiChatCompletionsClient client,
        IGlossaryStore? glossaryStore = null,
        IWritingStyleStore? writingStyleStore = null,
        Func<WritingStyleApplicationContext?>? applicationContextProvider = null)
    {
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.settingsStore = settingsStore
            ?? throw new ArgumentNullException(nameof(settingsStore));
        this.client = client ?? throw new ArgumentNullException(nameof(client));
        this.glossaryStore = glossaryStore;
        this.writingStyleStore = writingStyleStore;
        this.applicationContextProvider = applicationContextProvider ?? (() => null);
    }

    public OpenAiStreamingTextRefiner(
        IDefaultLlmProviderResolver providerResolver,
        ILlmStreamingClient streamingClient,
        IGlossaryStore? glossaryStore = null,
        IWritingStyleStore? writingStyleStore = null,
        Func<WritingStyleApplicationContext?>? applicationContextProvider = null)
    {
        this.providerResolver = providerResolver
            ?? throw new ArgumentNullException(nameof(providerResolver));
        this.streamingClient = streamingClient
            ?? throw new ArgumentNullException(nameof(streamingClient));
        this.glossaryStore = glossaryStore;
        this.writingStyleStore = writingStyleStore;
        this.applicationContextProvider = applicationContextProvider ?? (() => null);
    }

    public async ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
        CancellationToken cancellationToken)
    {
        if (providerResolver is not null)
        {
            return await providerResolver.ResolveDefaultAsync(cancellationToken)
                    .ConfigureAwait(false) is null
                ? LlmRefinerAvailability.NotConfigured
                : LlmRefinerAvailability.Ready;
        }

        var settings = await settingsStore!.LoadAsync(
                LlmProviderId.OpenAI,
                cancellationToken)
            .ConfigureAwait(false);
        if (settings is null)
        {
            return LlmRefinerAvailability.NotConfigured;
        }

        var credential = await credentialVault!.GetPresentationAsync(
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
        Func<string, string, IAsyncEnumerable<string>> streamChat;
        if (providerResolver is not null)
        {
            var configuration = await providerResolver
                .ResolveDefaultAsync(cancellationToken)
                .ConfigureAwait(false)
                ?? throw new InvalidOperationException("The default LLM provider is not configured.");
            streamChat = (system, input) => StreamManagedAsync(
                configuration,
                system,
                input,
                cancellationToken);
        }
        else
        {
            var settings = await settingsStore!.LoadAsync(
                    LlmProviderId.OpenAI,
                    cancellationToken)
                .ConfigureAwait(false)
                ?? throw new InvalidOperationException("OpenAI is not configured.");
            if (!settings.Enabled)
            {
                throw new InvalidOperationException("OpenAI text refinement is disabled.");
            }

            var apiKey = await credentialVault!.ReadSecretAsync(
                    OpenAiCredentialKeys.ApiKey,
                    cancellationToken)
                .ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                throw new InvalidOperationException("OpenAI is not configured.");
            }

            var configuration = new OpenAiClientConfiguration(
                settings.BaseUri,
                settings.Model,
                apiKey);
            streamChat = (system, input) => client!.StreamChatAsync(
                configuration,
                system,
                input,
                cancellationToken);
        }
        var styleDocument = writingStyleStore is null
            ? null
            : await writingStyleStore.LoadAsync(cancellationToken).ConfigureAwait(false);
        var style = styleDocument is null
            ? null
            : await ResolveStyleAsync(
                    styleDocument,
                    streamChat,
                    text,
                    cancellationToken)
                .ConfigureAwait(false);
        var instruction = await BuildInstructionAsync(style, cancellationToken)
            .ConfigureAwait(false);
        await foreach (var snapshot in streamChat(instruction, text)
            .WithCancellation(cancellationToken)
            .ConfigureAwait(false))
        {
            yield return ApplyTemplate(snapshot, style?.MarkdownTemplate);
        }
    }

    private async ValueTask<string> BuildInstructionAsync(
        WritingStyleProfile? style,
        CancellationToken cancellationToken)
    {
        const string conservative =
            "Conservatively clean up the dictated text. Preserve meaning, facts, language, " +
            "names, numbers, code, and formatting. Correct only obvious speech-recognition, " +
            "punctuation, spacing, and disfluency issues. Return only the corrected text.";
        List<string> sections = [conservative];
        if (!string.IsNullOrWhiteSpace(style?.Instruction))
        {
            sections.Add("Active writing style: " + Limit(style.Instruction, 2_000));
        }
        if (!string.IsNullOrWhiteSpace(style?.MarkdownTemplate))
        {
            sections.Add(
                "Output format template: " + Limit(style.MarkdownTemplate, 2_000) +
                "\nReturn content suitable for the {{content}} placeholder. Do not repeat the surrounding template.");
        }

        if (glossaryStore is not null)
        {
            var terms = (await glossaryStore.LoadAsync(cancellationToken)
                .ConfigureAwait(false)).Hotwords
                .Select(item => item.Term)
                .Where(term => !string.IsNullOrWhiteSpace(term))
                .Take(100)
                .ToArray();
            if (terms.Length > 0)
            {
                sections.Add(
                    "Preferred vocabulary (preserve these spellings when context supports them): " +
                    string.Join(", ", terms.Select(term => Limit(term, 80))));
            }
        }

        return string.Join("\n\n", sections);
    }

    private async ValueTask<WritingStyleProfile?> ResolveStyleAsync(
        WritingStyleDocument document,
        Func<string, string, IAsyncEnumerable<string>> streamChat,
        string transcript,
        CancellationToken cancellationToken)
    {
        var context = applicationContextProvider();
        if (context is not null)
        {
            var manual = document.Profiles.FirstOrDefault(profile =>
                profile.ApplicationRoutes.Any(context.Matches));
            if (manual is not null)
            {
                return manual;
            }
        }

        var matchCandidates = document.AiMatchCandidates;
        if (!document.AiAutoMatch || matchCandidates.Count == 0)
        {
            return document.SelectedProfile;
        }

        var candidates = string.Join(
            "\n",
            matchCandidates.Select(profile =>
                $"{profile.Id:D}\t{Limit(profile.Name, 80)}\t{Limit(profile.Description, 240)}"));
        var app = context is null
            ? "unknown"
            : $"{context.ProcessName} | {Limit(context.WindowTitle, 200)}";
        var system =
            "Select the single best writing style for the transcript and foreground application. " +
            "Return only the exact profile UUID from the candidate list. If uncertain, return DEFAULT.";
        var input = $"Application: {app}\nTranscript: {Limit(transcript, 2_000)}\nCandidates:\n{candidates}";
        try
        {
            var response = string.Empty;
            await foreach (var snapshot in streamChat(system, input)
                .WithCancellation(cancellationToken)
                .ConfigureAwait(false))
            {
                response = snapshot.Trim();
            }

            if (Guid.TryParse(response, out var selectedId))
            {
                return matchCandidates.FirstOrDefault(profile => profile.Id == selectedId)
                    ?? document.SelectedProfile;
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Routing failure is conservative: retain the explicitly selected style.
        }

        return document.SelectedProfile;
    }

    private static string ApplyTemplate(string content, string? template)
    {
        if (string.IsNullOrWhiteSpace(template))
        {
            return content;
        }

        var normalized = template.Trim();
        return normalized.Contains("{{content}}", StringComparison.Ordinal)
            ? normalized.Replace("{{content}}", content, StringComparison.Ordinal)
            : string.Concat(normalized, Environment.NewLine, content);
    }

    private static string Limit(string value, int maximumLength) =>
        value.Length <= maximumLength ? value : value[..maximumLength];

    private async IAsyncEnumerable<string> StreamManagedAsync(
        LlmProviderClientConfiguration configuration,
        string system,
        string input,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var request = new LlmCompletionRequest(
        [
            new LlmChatMessage(LlmMessageRole.System, system),
            new LlmChatMessage(LlmMessageRole.User, input),
        ]);
        await foreach (var update in streamingClient!.StreamAsync(
                configuration,
                request,
                cancellationToken)
            .WithCancellation(cancellationToken)
            .ConfigureAwait(false))
        {
            if (update.AccumulatedText.Length > 0)
            {
                yield return update.AccumulatedText;
            }
        }
    }
}
