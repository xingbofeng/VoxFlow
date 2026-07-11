using System.Net;
using System.Text;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiStreamingTextRefinerTests
{
    [Fact]
    public async Task Enabled_configured_refiner_streams_through_fixed_official_endpoint()
    {
        using var vault = new FakeCredentialVault("sk-fixture");
        var store = new FakeStore(new LlmProviderSettings(
            LlmProviderId.OpenAI,
            new Uri("https://custom-metadata.invalid/v1"),
            "fixture-model",
            Enabled: true));
        var handler = new CapturingHandler();
        using var http = new HttpClient(handler);
        var refiner = new OpenAiStreamingTextRefiner(
            vault,
            store,
            new OpenAiChatCompletionsClient(http));

        Assert.Equal(
            LlmRefinerAvailability.Ready,
            await refiner.GetAvailabilityAsync(CancellationToken.None));
        var values = new List<string>();
        await foreach (var value in refiner.RefineAsync(
            "raw",
            CancellationToken.None))
        {
            values.Add(value);
        }

        Assert.Equal(["clean"], values);
        Assert.Equal(
            new Uri("https://api.openai.com/v1/chat/completions"),
            handler.RequestUri);
    }

    [Theory]
    [InlineData(false, true, LlmRefinerAvailability.Disabled)]
    [InlineData(true, false, LlmRefinerAvailability.NotConfigured)]
    public async Task Disabled_or_missing_secret_never_reports_ready(
        bool enabled,
        bool hasSecret,
        LlmRefinerAvailability expected)
    {
        using var vault = new FakeCredentialVault(hasSecret ? "sk-fixture" : null);
        var store = new FakeStore(new LlmProviderSettings(
            LlmProviderId.OpenAI,
            OpenAiProductionDefaults.BaseUri,
            "fixture-model",
            enabled));
        using var http = new HttpClient(new CapturingHandler());
        var refiner = new OpenAiStreamingTextRefiner(
            vault,
            store,
            new OpenAiChatCompletionsClient(http));

        Assert.Equal(
            expected,
            await refiner.GetAvailabilityAsync(CancellationToken.None));
    }

    private sealed class CapturingHandler : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    "data: {\"choices\":[{\"delta\":{\"content\":\"clean\"}}]}\n\n" +
                    "data: [DONE]\n\n",
                    Encoding.UTF8,
                    "text/event-stream"),
            });
        }
    }

    private sealed class FakeStore(LlmProviderSettings? value) : ILlmProviderSettingsStore
    {
        public ValueTask<LlmProviderSettings?> LoadAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) => ValueTask.FromResult(value);

        public ValueTask SaveAsync(
            LlmProviderSettings settings,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public ValueTask DeleteAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class FakeCredentialVault(string? secret) : ICredentialVault
    {
        public Task SaveAsync(
            CredentialKey key,
            string value,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(secret);

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(secret is null
                ? new CredentialPresentation(CredentialAvailability.Missing, string.Empty)
                : new CredentialPresentation(CredentialAvailability.Available, "••••••••"));

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public void Dispose()
        {
        }
    }
}
