using System.Net;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiFileTranscriptionTranslatorTests
{
    [Fact]
    public async Task Uses_official_openai_configuration_and_a_translation_specific_chat_prompt()
    {
        const string sse =
            "data: {\"choices\":[{\"delta\":{\"content\":\"译文\"}}]}\n\n" +
            "data: [DONE]\n\n";
        var handler = new CapturingHandler(sse);
        using var httpClient = new HttpClient(handler);
        var translator = new OpenAiFileTranscriptionTranslator(
            new FakeCredentialVault("sk-private-fixture"),
            new FakeSettingsStore(new LlmProviderSettings(
                LlmProviderId.OpenAI,
                new Uri("https://compatible.invalid/v1"),
                "configured-model",
                Enabled: true)),
            new OpenAiChatCompletionsClient(httpClient));

        var result = await translator.TranslateAsync(
            "original text",
            "zh-Hans",
            CancellationToken.None);

        Assert.Equal("译文", result);
        Assert.Equal(
            new Uri("https://api.openai.com/v1/chat/completions"),
            handler.RequestUri);
        using var body = JsonDocument.Parse(handler.RequestBody!);
        Assert.Equal("configured-model", body.RootElement.GetProperty("model").GetString());
        var messages = body.RootElement.GetProperty("messages");
        Assert.Contains(
            "zh-Hans",
            messages[0].GetProperty("content").GetString(),
            StringComparison.Ordinal);
        Assert.Contains(
            "Translate",
            messages[0].GetProperty("content").GetString(),
            StringComparison.OrdinalIgnoreCase);
        Assert.Equal("original text", messages[1].GetProperty("content").GetString());
        Assert.Equal("sk-private-fixture", handler.AuthorizationParameter);
    }

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public async Task Missing_or_disabled_openai_configuration_is_unavailable(
        bool hasSettings,
        bool hasCredential)
    {
        using var httpClient = new HttpClient(new CapturingHandler(string.Empty));
        var translator = new OpenAiFileTranscriptionTranslator(
            new FakeCredentialVault(hasCredential ? "key" : null),
            new FakeSettingsStore(hasSettings
                ? new LlmProviderSettings(
                    LlmProviderId.OpenAI,
                    OpenAiProductionDefaults.BaseUri,
                    "model",
                    Enabled: false)
                : null),
            new OpenAiChatCompletionsClient(httpClient));

        await Assert.ThrowsAsync<FileTranscriptionTranslationUnavailableException>(async () =>
            await translator.TranslateAsync(
                "text",
                "ja",
                CancellationToken.None));
    }

    private sealed class CapturingHandler(string sse) : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }
        public string? RequestBody { get; private set; }
        public string? AuthorizationParameter { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            RequestBody = await request.Content!.ReadAsStringAsync(cancellationToken);
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(sse, Encoding.UTF8, "text/event-stream"),
            };
        }
    }

    private sealed class FakeSettingsStore(LlmProviderSettings? settings)
        : ILlmProviderSettingsStore
    {
        public ValueTask<LlmProviderSettings?> LoadAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) => ValueTask.FromResult(settings);
        public ValueTask SaveAsync(
            LlmProviderSettings settings,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public ValueTask DeleteAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class FakeCredentialVault(string? secret) : ICredentialVault
    {
        public Task SaveAsync(CredentialKey key, string value, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
        public Task<string?> ReadSecretAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
            Task.FromResult(secret);
        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public void Dispose() { }
    }
}
