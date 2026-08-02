using System.Net;
using System.Text;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiCompatibleModelDiscoveryTests
{
    [Theory]
    [InlineData("https://api.deepseek.com", "https://api.deepseek.com/v1/models")]
    [InlineData("https://api.groq.com/openai/v1", "https://api.groq.com/openai/v1/models")]
    [InlineData("https://models.github.ai/inference", "https://models.github.ai/inference/v1/models")]
    [InlineData("http://localhost:11434/v1", "http://localhost:11434/v1/models")]
    public void Models_URL_matches_the_current_mac_path_rule(
        string baseUrl,
        string expected)
    {
        Assert.Equal(
            new Uri(expected),
            OpenAiCompatibleClient.BuildModelsUri(
                LlmProviderEndpoint.Normalize(baseUrl)));
    }

    [Fact]
    public async Task Standard_data_shape_normalizes_models_prefix_and_deduplicates_manual_model()
    {
        var handler = new CapturingHandler(_ => JsonResponse(
            """
            {
              "data": [
                {"id":"models/manual-model","owned_by":"owner-a"},
                {"id":"remote-model","owned_by":"owner-b"},
                {"id":"remote-model","owned_by":"duplicate"}
              ]
            }
            """));
        using var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.DiscoverModelsAsync(
            Configuration(
                "google",
                "https://generativelanguage.googleapis.com/v1beta/openai",
                "manual-model",
                "fixture-key"),
            CancellationToken.None);

        Assert.Equal(LlmModelDiscoverySource.Remote, result.Source);
        Assert.Equal(
            ["manual-model", "remote-model"],
            result.Models.Select(model => model.Id));
        Assert.Equal("owner-a", result.Models[0].OwnedBy);
        Assert.Equal("owner-b", result.Models[1].OwnedBy);
        Assert.Equal(
            new Uri("https://generativelanguage.googleapis.com/v1beta/openai/v1/models"),
            handler.RequestUri);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal("fixture-key", handler.AuthorizationParameter);
    }

    public static TheoryData<string, string[]> AlternativeShapes => new()
    {
        {
            """{"models":[{"name":"model-a"},{"model":"model-b"},{"id":"model-c"}]}""",
            ["manual", "model-a", "model-b", "model-c"]
        },
        {
            """["model-a",{"id":"model-b"},{"name":"model-c"}]""",
            ["manual", "model-a", "model-b", "model-c"]
        },
    };

    [Theory]
    [MemberData(nameof(AlternativeShapes))]
    public async Task Alternative_model_shapes_are_supported(
        string json,
        string[] expected)
    {
        using var http = new HttpClient(new CapturingHandler(_ => JsonResponse(json)))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.DiscoverModelsAsync(
            Configuration("custom", "https://custom.example/v1", "manual", "key"),
            CancellationToken.None);

        Assert.Equal(LlmModelDiscoverySource.Remote, result.Source);
        Assert.Equal(expected, result.Models.Select(model => model.Id));
    }

    [Fact]
    public async Task Unsupported_models_endpoint_uses_matching_catalog_fallback_and_manual_dedupe()
    {
        using var http = new HttpClient(new CapturingHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.NotFound)
            {
                Content = new ThrowIfReadContent(),
            }))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.DiscoverModelsAsync(
            Configuration(
                "deepseek",
                "https://api.deepseek.com",
                "deepseek-chat",
                "key"),
            CancellationToken.None);

        Assert.Equal(LlmModelDiscoverySource.CatalogFallback, result.Source);
        Assert.Equal(
            ["deepseek-chat", "deepseek-reasoner"],
            result.Models.Select(model => model.Id));
        Assert.Equal("models_endpoint_unavailable", result.SafeMessage);
    }

    [Fact]
    public async Task Invalid_custom_response_keeps_manual_model_without_mutating_configuration()
    {
        using var http = new HttpClient(new CapturingHandler(_ => JsonResponse(
            """{"unexpected":true}""")))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");
        var configuration = Configuration(
            "custom",
            "https://custom.example/v1",
            "saved-manual-model",
            "key");

        var result = await client.DiscoverModelsAsync(
            configuration,
            CancellationToken.None);

        Assert.Equal(LlmModelDiscoverySource.ManualOnly, result.Source);
        Assert.Equal("saved-manual-model", Assert.Single(result.Models).Id);
        Assert.Equal("saved-manual-model", configuration.Model);
        Assert.Equal("models_response_unsupported", result.SafeMessage);
    }

    [Fact]
    public async Task Loopback_discovery_omits_auth_and_deduplicates_ollama_shape()
    {
        var handler = new CapturingHandler(_ => JsonResponse(
            """{"models":[{"name":"qwen-local"},{"model":"qwen-local"}]}"""));
        using var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.DiscoverModelsAsync(
            Configuration(
                "ollama-local",
                "http://127.0.0.1:11434/v1",
                "qwen-local",
                apiKey: null),
            CancellationToken.None);

        Assert.Equal(LlmModelDiscoverySource.Remote, result.Source);
        Assert.Equal("qwen-local", Assert.Single(result.Models).Id);
        Assert.Null(handler.AuthorizationScheme);
        Assert.Null(handler.AuthorizationParameter);
    }

    private static LlmProviderClientConfiguration Configuration(
        string providerId,
        string baseUrl,
        string model,
        string? apiKey) => new(
            providerId,
            LlmProviderEndpoint.Normalize(baseUrl),
            model,
            apiKey,
            0.2,
            TimeSpan.FromSeconds(30));

    private static HttpResponseMessage JsonResponse(string json) => new(
        HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json"),
    };

    private sealed class CapturingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory)
        : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        public string? AuthorizationScheme { get; private set; }

        public string? AuthorizationParameter { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            return Task.FromResult(responseFactory(request));
        }
    }

    private sealed class ThrowIfReadContent : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            throw new InvalidOperationException("Unsupported response body must not be read.");

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }
}
