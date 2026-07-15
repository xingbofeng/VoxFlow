using System.Net;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiCompatibleHealthTests
{
    [Fact]
    public async Task Connection_test_requires_nonempty_completion_without_sending_tools()
    {
        var handler = new CapturingHandler(_ => JsonResponse(
            """{"choices":[{"message":{"content":"OK"}}]}"""));
        using var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.TestConnectionAsync(
            Configuration(),
            CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.NotNull(result.LatencyMs);
        Assert.True(result.LatencyMs >= 0);
        using var body = JsonDocument.Parse(handler.RequestBody!);
        Assert.False(body.RootElement.TryGetProperty("tools", out _));
        Assert.False(body.RootElement.GetProperty("stream").GetBoolean());
        Assert.Equal(0, body.RootElement.GetProperty("temperature").GetDouble());
        Assert.Equal(32, body.RootElement.GetProperty("max_tokens").GetInt32());
    }

    [Fact]
    public async Task Content_only_completion_is_text_capable_but_Agent_unsupported()
    {
        var handler = new CapturingHandler(_ => JsonResponse(
            """{"choices":[{"message":{"content":"I can answer text."}}]}"""));
        using var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.TestAgentCapabilityAsync(
            Configuration(),
            CancellationToken.None);

        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, result.Status);
        Assert.Equal("tool_calls_missing", result.SafeMessage);
        using var body = JsonDocument.Parse(handler.RequestBody!);
        var tool = body.RootElement.GetProperty("tools")[0];
        Assert.Equal("function", tool.GetProperty("type").GetString());
        var function = tool.GetProperty("function");
        Assert.Equal("voxflow_capability_probe", function.GetProperty("name").GetString());
        Assert.Equal(
            "object",
            function.GetProperty("parameters").GetProperty("type").GetString());
        Assert.False(body.RootElement.GetProperty("stream").GetBoolean());
    }

    public static TheoryData<string> ValidToolCalls => new()
    {
        """
        {"choices":[{"message":{"tool_calls":[
          {"id":"call-1","type":"function","function":{"name":"voxflow_capability_probe","arguments":"{\"value\":\"ok\"}"}}
        ]}}]}
        """,
        """
        {"choices":[{"message":{"tool_calls":[
          {"id":"call-1","type":"function","function":{"name":"voxflow_capability_probe","arguments":"{\"value\":\"one\"}"}},
          {"id":"call-2","type":"function","function":{"name":"voxflow_capability_probe","arguments":"{\"value\":\"two\"}"}}
        ]}}]}
        """,
    };

    [Theory]
    [MemberData(nameof(ValidToolCalls))]
    public async Task Valid_single_or_parallel_tool_calls_are_supported(string json)
    {
        using var http = new HttpClient(new CapturingHandler(_ => JsonResponse(json)))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.TestAgentCapabilityAsync(
            Configuration(),
            CancellationToken.None);

        Assert.Equal(LlmAgentCapabilityStatus.Supported, result.Status);
        Assert.True(result.IsSupported);
        Assert.Null(result.SafeMessage);
    }

    [Fact]
    public async Task Malformed_tool_arguments_are_Agent_error_not_supported()
    {
        using var http = new HttpClient(new CapturingHandler(_ => JsonResponse(
            """
            {"choices":[{"message":{"tool_calls":[
              {"id":"call-1","type":"function","function":{"name":"voxflow_capability_probe","arguments":"not-json"}}
            ]}}]}
            """)))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var result = await client.TestAgentCapabilityAsync(
            Configuration(),
            CancellationToken.None);

        Assert.Equal(LlmAgentCapabilityStatus.Error, result.Status);
        Assert.Equal("tool_calls_invalid", result.SafeMessage);
    }

    [Fact]
    public async Task HTTP_failures_produce_separate_safe_connection_and_Agent_results()
    {
        using var http = new HttpClient(new CapturingHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new ThrowIfReadContent(),
            }))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var connection = await client.TestConnectionAsync(
            Configuration(),
            CancellationToken.None);
        var agent = await client.TestAgentCapabilityAsync(
            Configuration(),
            CancellationToken.None);

        Assert.Equal(LlmConnectionTestStatus.Failed, connection.Status);
        Assert.Equal("connection_http_400", connection.SafeMessage);
        Assert.Equal(LlmAgentCapabilityStatus.Error, agent.Status);
        Assert.Equal("agent_http_400", agent.SafeMessage);
    }

    private static LlmProviderClientConfiguration Configuration() => new(
        "fixture",
        new Uri("https://example.test/v1"),
        "model-a",
        "fixture-key",
        0.7,
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
        public string? RequestBody { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestBody = request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken);
            return responseFactory(request);
        }
    }

    private sealed class ThrowIfReadContent : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            throw new InvalidOperationException("Health error response body must not be read.");

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }
}
