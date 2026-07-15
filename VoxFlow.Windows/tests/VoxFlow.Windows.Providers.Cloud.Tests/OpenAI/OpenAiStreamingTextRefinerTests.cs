using System.Net;
using System.Text;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiStreamingTextRefinerTests
{
    [Fact]
    public async Task Enabled_configured_refiner_streams_through_saved_compatible_endpoint()
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
            new Uri("https://custom-metadata.invalid/v1/chat/completions"),
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

    [Fact]
    public async Task Manual_application_route_selects_style_and_applies_markdown_template()
    {
        using var vault = new FakeCredentialVault("sk-fixture");
        var store = new FakeStore(new LlmProviderSettings(
            LlmProviderId.OpenAI,
            OpenAiProductionDefaults.BaseUri,
            "fixture-model",
            Enabled: true));
        var handler = new CapturingHandler();
        using var http = new HttpClient(handler);
        var styles = WritingStyleDocument.Default with { AiAutoMatch = true };
        var refiner = new OpenAiStreamingTextRefiner(
            vault,
            store,
            new OpenAiChatCompletionsClient(http),
            writingStyleStore: new FakeWritingStyleStore(styles),
            applicationContextProvider: () => new WritingStyleApplicationContext(
                @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
                "Terminal"));

        var values = new List<string>();
        await foreach (var value in refiner.RefineAsync("raw", CancellationToken.None))
        {
            values.Add(value);
        }

        Assert.Equal(["```text\nclean\n```"], values);
        Assert.Equal(1, handler.CallCount);
        Assert.Contains("Treat the input as technical content", handler.RequestBody);
    }

    [Fact]
    public async Task Managed_default_provider_is_the_runtime_used_for_dictation_refinement()
    {
        var configuration = new LlmProviderClientConfiguration(
            "managed-default",
            new Uri("https://managed.invalid/v1"),
            "managed-model",
            "secret",
            0,
            TimeSpan.FromSeconds(30));
        var client = new FakeStreamingClient();
        var refiner = new OpenAiStreamingTextRefiner(
            new FakeDefaultProviderResolver(configuration),
            client);

        Assert.Equal(
            LlmRefinerAvailability.Ready,
            await refiner.GetAvailabilityAsync(CancellationToken.None));
        var values = new List<string>();
        await foreach (var value in refiner.RefineAsync("raw", CancellationToken.None))
        {
            values.Add(value);
        }

        Assert.Equal(["clean"], values);
        Assert.Same(configuration, client.Configuration);
        Assert.Equal("raw", client.Request?.Messages[1].Content);
    }

    private sealed class CapturingHandler : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }
        public string RequestBody { get; private set; } = string.Empty;
        public int CallCount { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            RequestUri = request.RequestUri;
            RequestBody = request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    "data: {\"choices\":[{\"delta\":{\"content\":\"clean\"}}]}\n\n" +
                    "data: [DONE]\n\n",
                    Encoding.UTF8,
                    "text/event-stream"),
            };
        }
    }

    private sealed class FakeWritingStyleStore(WritingStyleDocument document) : IWritingStyleStore
    {
        public ValueTask<WritingStyleDocument> LoadAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult(document);

        public ValueTask SaveAsync(
            WritingStyleDocument document,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class FakeDefaultProviderResolver(
        LlmProviderClientConfiguration? configuration) : IDefaultLlmProviderResolver
    {
        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(configuration);
    }

    private sealed class FakeStreamingClient : ILlmStreamingClient
    {
        public LlmProviderClientConfiguration? Configuration { get; private set; }
        public LlmCompletionRequest? Request { get; private set; }

        public async IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            [System.Runtime.CompilerServices.EnumeratorCancellation]
            CancellationToken cancellationToken)
        {
            Configuration = configuration;
            Request = request;
            await Task.Yield();
            yield return new LlmStreamUpdate("clean", "clean", true, null);
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
