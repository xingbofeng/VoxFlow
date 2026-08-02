using VoxFlow.Windows.Providers.Cloud.Common;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Common;

public sealed class CloudWebSocketContractsTests
{
    [Fact]
    public void Connect_request_keeps_runtime_values_but_never_renders_query_or_headers()
    {
        const string sentinel = "fixture-bearer-never-render";
        var request = new CloudWebSocketConnectRequest(
            new Uri($"wss://example.invalid/private-id?signature={sentinel}"),
            new Dictionary<string, string>
            {
                ["Authorization"] = $"Bearer {sentinel}",
            });

        Assert.Contains(sentinel, request.Uri.OriginalString, StringComparison.Ordinal);
        Assert.Contains(sentinel, request.Headers["Authorization"], StringComparison.Ordinal);
        Assert.DoesNotContain(sentinel, request.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("Authorization", request.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.Equal("wss://example.invalid/[redacted]", request.SafeDiagnostic);
    }

    [Theory]
    [InlineData("http://example.invalid")]
    [InlineData("https://example.invalid")]
    [InlineData("ws://example.invalid")]
    public void Connect_request_requires_TLS_WebSocket(string endpoint)
    {
        Assert.Throws<ArgumentException>(() =>
            new CloudWebSocketConnectRequest(new Uri(endpoint)));
    }

    [Fact]
    public void Received_text_decodes_strict_UTF8_and_close_has_no_payload()
    {
        var text = CloudWebSocketReceiveMessage.Text("腾讯云 fixture");
        var close = CloudWebSocketReceiveMessage.Closed();

        Assert.Equal(CloudWebSocketMessageType.Text, text.Type);
        Assert.Equal("腾讯云 fixture", text.GetText());
        Assert.Equal(CloudWebSocketMessageType.Close, close.Type);
        Assert.True(close.Payload.IsEmpty);
        Assert.Throws<InvalidOperationException>(() => close.GetText());
    }
}
