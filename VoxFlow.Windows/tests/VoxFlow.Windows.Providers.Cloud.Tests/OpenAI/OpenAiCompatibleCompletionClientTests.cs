using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiCompatibleCompletionClientTests
{
    private const string ApiKey = "~";

    [Theory]
    [InlineData("https://api.example/v1/", "https://api.example/v1", "https://api.example/v1/chat/completions")]
    [InlineData("https://api.example/v1/chat/completions/", "https://api.example/v1", "https://api.example/v1/chat/completions")]
    [InlineData("https://models.github.ai/inference", "https://models.github.ai/inference", "https://models.github.ai/inference/chat/completions")]
    [InlineData("http://localhost:11434/v1/", "http://localhost:11434/v1", "http://localhost:11434/v1/chat/completions")]
    public void Base_and_chat_completion_URLs_are_normalized_once(
        string input,
        string expectedBase,
        string expectedChat)
    {
        var normalized = LlmProviderEndpoint.Normalize(input);

        Assert.Equal(new Uri(expectedBase), normalized);
        Assert.Equal(
            new Uri(expectedChat),
            OpenAiCompatibleClient.BuildChatCompletionsUri(normalized));
    }

    [Fact]
    public async Task Completion_sends_model_temperature_timeout_auth_and_OpenRouter_headers()
    {
        var handler = new CapturingHandler(_ => JsonResponse(
            """
            {
              "model": "server-model",
              "choices": [{"message":{"role":"assistant","content":"完成"}}],
              "usage": {"prompt_tokens": 11, "completion_tokens": 7, "total_tokens": 18}
            }
            """));
        using var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var client = new OpenAiCompatibleClient(http, appVersion: "0.1.10 Windows");
        var configuration = Configuration(
            "openrouter",
            "https://openrouter.ai/api/v1",
            apiKey: ApiKey,
            model: "configured-model",
            temperature: 0.35,
            timeout: TimeSpan.FromSeconds(9));
        var request = new LlmCompletionRequest(
            [
                new LlmChatMessage(LlmMessageRole.System, "只输出结果"),
                new LlmChatMessage(LlmMessageRole.User, "请处理"),
            ],
            maxOutputTokens: 256);

        var response = await client.CompleteAsync(
            configuration,
            request,
            CancellationToken.None);

        Assert.Equal(
            new Uri("https://openrouter.ai/api/v1/chat/completions"),
            handler.RequestUri);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal(ApiKey, handler.AuthorizationParameter);
        Assert.Equal("application/json", handler.Accept);
        Assert.Equal("https://mashangxie.app", handler.Header("HTTP-Referer"));
        Assert.Equal("VoxFlow", handler.Header("X-Title"));
        Assert.Equal("VoxFlow/0.1.10-Windows", handler.UserAgent);
        Assert.Equal("application/json", handler.ContentType);
        using var body = JsonDocument.Parse(handler.RequestBody!);
        Assert.Equal("configured-model", body.RootElement.GetProperty("model").GetString());
        Assert.Equal(0.35, body.RootElement.GetProperty("temperature").GetDouble(), 6);
        Assert.Equal(256, body.RootElement.GetProperty("max_tokens").GetInt32());
        Assert.False(body.RootElement.GetProperty("stream").GetBoolean());
        Assert.Equal("system", body.RootElement.GetProperty("messages")[0]
            .GetProperty("role").GetString());
        Assert.Equal("请处理", body.RootElement.GetProperty("messages")[1]
            .GetProperty("content").GetString());
        Assert.Equal("完成", response.Text);
        Assert.Equal("openrouter", response.ProviderId);
        Assert.Equal("server-model", response.Model);
        Assert.Equal(11, response.TokenUsage?.InputTokens);
        Assert.Equal(7, response.TokenUsage?.OutputTokens);
        Assert.Equal(18, response.TokenUsage?.TotalTokens);
        Assert.DoesNotContain(ApiKey, client.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task GitHub_headers_are_added_while_keyless_loopback_omits_authorization()
    {
        var githubHandler = new CapturingHandler(_ => JsonResponse(Response("github")));
        using var githubHttp = new HttpClient(githubHandler)
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var githubClient = new OpenAiCompatibleClient(githubHttp, "dev");
        await githubClient.CompleteAsync(
            Configuration(
                "github",
                "https://models.github.ai/inference",
                ApiKey),
            Request(),
            CancellationToken.None);

        Assert.Equal("application/vnd.github+json", githubHandler.Accept);
        Assert.Equal("2022-11-28", githubHandler.Header("X-GitHub-Api-Version"));

        var localHandler = new CapturingHandler(_ => JsonResponse(Response("local")));
        using var localHttp = new HttpClient(localHandler)
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var localClient = new OpenAiCompatibleClient(localHttp, "dev");
        await localClient.CompleteAsync(
            Configuration(
                "ollama-local",
                "http://127.0.0.1:11434/v1",
                apiKey: null),
            Request(),
            CancellationToken.None);

        Assert.Null(localHandler.AuthorizationScheme);
        Assert.Null(localHandler.AuthorizationParameter);
        Assert.Null(localHandler.Header("HTTP-Referer"));
        Assert.Null(localHandler.Header("X-GitHub-Api-Version"));
    }

    public static TheoryData<string, string> FlexibleResponses => new()
    {
        {
            """{"choices":[{"message":{"content":"plain"}}]}""",
            "plain"
        },
        {
            """{"choices":[{"message":{"content":[{"type":"text","text":"A"},{"type":"text","text":"B"}]}}]}""",
            "AB"
        },
        {
            """{"choices":[{"message":{"content":null,"reasoning_content":"reasoned"}}]}""",
            "reasoned"
        },
        {
            """{"choices":[{"message":{"reasoning":"fallback"}}]}""",
            "fallback"
        },
    };

    [Theory]
    [MemberData(nameof(FlexibleResponses))]
    public async Task Ordinary_response_parser_accepts_current_mac_content_shapes(
        string json,
        string expected)
    {
        using var http = new HttpClient(new CapturingHandler(_ => JsonResponse(json)))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var response = await client.CompleteAsync(
            Configuration("fixture", "https://example.test/v1", ApiKey),
            Request(),
            CancellationToken.None);

        Assert.Equal(expected, response.Text);
        Assert.Equal("model-a", response.Model);
    }

    [Fact]
    public async Task Configured_request_timeout_cancels_a_blocked_HTTP_send()
    {
        using var http = new HttpClient(new BlockingHandler())
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");
        var stopwatch = Stopwatch.StartNew();

        var error = await Assert.ThrowsAsync<OpenAiCompatibleClientException>(async () =>
            await client.CompleteAsync(
                Configuration(
                    "slow",
                    "https://slow.example/v1",
                    ApiKey,
                    timeout: TimeSpan.FromSeconds(1)),
                Request(),
                CancellationToken.None));

        Assert.Equal(OpenAiCompatibleClientError.Timeout, error.Error);
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(5));
        Assert.DoesNotContain(ApiKey, error.ToString(), StringComparison.Ordinal);
    }

    private static LlmProviderClientConfiguration Configuration(
        string providerId,
        string baseUrl,
        string? apiKey,
        string model = "model-a",
        double temperature = 0.2,
        TimeSpan? timeout = null) => new(
            providerId,
            LlmProviderEndpoint.Normalize(baseUrl),
            model,
            apiKey,
            temperature,
            timeout ?? TimeSpan.FromSeconds(30));

    private static LlmCompletionRequest Request() => new(
        [new LlmChatMessage(LlmMessageRole.User, "hello")]);

    private static string Response(string content) => JsonSerializer.Serialize(new
    {
        choices = new[]
        {
            new { message = new { content } },
        },
    });

    private static HttpResponseMessage JsonResponse(string json) => new(
        HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json"),
    };

    private sealed class CapturingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory)
        : HttpMessageHandler
    {
        private readonly Dictionary<string, string> headers =
            new(StringComparer.OrdinalIgnoreCase);

        public Uri? RequestUri { get; private set; }

        public string? AuthorizationScheme { get; private set; }

        public string? AuthorizationParameter { get; private set; }

        public string? Accept { get; private set; }

        public string? UserAgent { get; private set; }

        public string? ContentType { get; private set; }

        public string? RequestBody { get; private set; }

        public string? Header(string name) =>
            headers.TryGetValue(name, out var value) ? value : null;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            Accept = request.Headers.Accept.SingleOrDefault()?.MediaType;
            UserAgent = request.Headers.UserAgent.ToString();
            ContentType = request.Content?.Headers.ContentType?.MediaType;
            foreach (var header in request.Headers)
            {
                headers[header.Key] = string.Join(",", header.Value);
            }
            RequestBody = request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken);
            return responseFactory(request);
        }
    }

    private sealed class BlockingHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("Unreachable.");
        }
    }
}
