using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentClipboardToolHostTests
{
    [Fact]
    public async Task Reads_unicode_text_as_untrusted_turn_context_without_persisting_a_payload()
    {
        var clipboard = new FakeClipboard("你好, VoxFlow");
        var result = await new BuiltinAgentClipboardToolHost(clipboard).ExecuteAsync(
            Call(new { action = "read_text" }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal("你好, VoxFlow", result.Result!.Value.GetProperty("text").GetString());
        Assert.True(result.Result!.Value.GetProperty("untrusted").GetBoolean());
        Assert.Equal(1, clipboard.ReadCalls);
    }

    [Fact]
    public async Task Writes_unicode_text_with_a_side_effect_action_marker()
    {
        var clipboard = new FakeClipboard();
        var result = await new BuiltinAgentClipboardToolHost(clipboard).ExecuteAsync(
            Call(new { action = "write_text", text = "草稿" }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal("草稿", clipboard.WrittenText);
        Assert.Equal("write_text", result.Result!.Value.GetProperty("action").GetString());
    }

    [Theory]
    [InlineData("image")]
    [InlineData("path")]
    public async Task Rejects_non_text_clipboard_payloads(string field)
    {
        var arguments = field == "image"
            ? JsonSerializer.SerializeToElement(new { action = "read_text", image = "image-data" })
            : JsonSerializer.SerializeToElement(new { action = "write_text", path = "C:\\x.txt" });
        var result = await new BuiltinAgentClipboardToolHost(new FakeClipboard()).ExecuteAsync(
            new AgentToolCall("call-1", "clipboard", arguments), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("unsupported_clipboard_payload", result.Error?.Code);
    }

    [Fact]
    public async Task Clipboard_failures_are_safe_codes_not_exception_payloads()
    {
        var result = await new BuiltinAgentClipboardToolHost(new FakeClipboard(throwOnWrite: true))
            .ExecuteAsync(Call(new { action = "write_text", text = "draft" }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("clipboard_failure", result.Error?.Code);
    }

    private static AgentToolCall Call<T>(T arguments) => new(
        "call-1", "clipboard", JsonSerializer.SerializeToElement(arguments));

    private sealed class FakeClipboard(string? text = null, bool throwOnWrite = false)
        : IAgentClipboardTextGateway
    {
        public int ReadCalls { get; private set; }
        public string? WrittenText { get; private set; }

        public string? ReadText()
        {
            ReadCalls++;
            return text;
        }

        public void WriteText(string value)
        {
            if (throwOnWrite)
            {
                throw new InvalidOperationException("clipboard unavailable");
            }
            WrittenText = value;
        }
    }
}
