using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentRespondToolHostTests
{
    [Fact]
    public async Task Presents_severity_without_claiming_a_desktop_action_succeeded()
    {
        var presenter = new CapturingPresenter();
        var result = await new BuiltinAgentRespondToolHost(presenter).ExecuteAsync(Call(new { text = "Please save the file yourself.", mode = "warning" }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal(new AgentUserResponse("Please save the file yourself.", AgentUserResponseSeverity.Warning, false), presenter.Response);
        Assert.Equal("responded", result.Result!.Value.GetProperty("kind").GetString());
        Assert.False(result.Result!.Value.GetProperty("copied").GetBoolean());
    }

    [Fact]
    public async Task Copy_is_explicit_and_failure_does_not_report_success()
    {
        var clipboard = new FakeClipboard();
        var copied = await new BuiltinAgentRespondToolHost(new CapturingPresenter(), clipboard)
            .ExecuteAsync(Call(new { text = "copy me", copy = true }), CancellationToken.None);
        var failed = await new BuiltinAgentRespondToolHost(new CapturingPresenter(), new ThrowingClipboard())
            .ExecuteAsync(Call(new { text = "copy me", copy = true }), CancellationToken.None);

        Assert.Equal("copy me", clipboard.Text);
        Assert.True(copied.Result!.Value.GetProperty("copied").GetBoolean());
        Assert.Equal("clipboard_write_failed", failed.Error?.Code);
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    public async Task Empty_text_is_rejected(string text)
    {
        var result = await new BuiltinAgentRespondToolHost(new CapturingPresenter()).ExecuteAsync(Call(new { text }), CancellationToken.None);
        Assert.Equal("missing_text", result.Error?.Code);
    }

    [Fact]
    public async Task Unknown_severity_is_rejected()
    {
        var result = await new BuiltinAgentRespondToolHost(new CapturingPresenter()).ExecuteAsync(Call(new { text = "hello", severity = "success" }), CancellationToken.None);
        Assert.Equal("invalid_severity", result.Error?.Code);
    }

    private static AgentToolCall Call(object arguments) => new("respond-1", "respond", JsonSerializer.SerializeToElement(arguments));
    private sealed class CapturingPresenter : IAgentUserResponsePresenter { public AgentUserResponse? Response { get; private set; } public Task PresentAsync(AgentUserResponse response, CancellationToken cancellationToken) { Response = response; return Task.CompletedTask; } }
    private sealed class FakeClipboard : IAgentClipboardTextGateway { public string? Text { get; private set; } public string? ReadText() => Text; public void WriteText(string text) => Text = text; }
    private sealed class ThrowingClipboard : IAgentClipboardTextGateway { public string? ReadText() => null; public void WriteText(string text) => throw new InvalidOperationException(); }
}
