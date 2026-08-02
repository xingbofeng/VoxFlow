using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentKeyboardToolHostTests
{
    [Fact]
    public async Task Type_forwards_text_only_after_host_validation()
    {
        var keyboard = new FakeKeyboard();
        var result = await new BuiltinAgentKeyboardToolHost(keyboard).ExecuteAsync(
            Call(new { action = "type", text = "你好" }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal("你好", keyboard.Typed);
        Assert.Equal("type", result.Result!.Value.GetProperty("action").GetString());
    }

    [Theory]
    [InlineData("Enter")]
    [InlineData("Return")]
    public async Task Submit_keys_are_rejected_before_the_gateway_runs(string key)
    {
        var keyboard = new FakeKeyboard();
        var result = await new BuiltinAgentKeyboardToolHost(keyboard).ExecuteAsync(
            Call(new { action = "press", key }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("submit_key_not_allowed", result.Error?.Code);
        Assert.Empty(keyboard.Pressed);
    }

    [Fact]
    public async Task Newlines_and_modifier_chords_are_not_keyboard_input()
    {
        var keyboard = new FakeKeyboard();
        var host = new BuiltinAgentKeyboardToolHost(keyboard);

        var newline = await host.ExecuteAsync(
            Call(new { action = "type", text = "first\nsecond" }), CancellationToken.None);
        var chord = await host.ExecuteAsync(
            Call(new { action = "press", key = "Ctrl+S" }), CancellationToken.None);

        Assert.Equal("submit_key_not_allowed", newline.Error?.Code);
        Assert.Equal("unsafe_keyboard_key", chord.Error?.Code);
        Assert.Null(keyboard.Typed);
        Assert.Empty(keyboard.Pressed);
    }

    [Theory]
    [InlineData(AgentKeyboardWriteStatus.TargetChanged, "target_changed")]
    [InlineData(AgentKeyboardWriteStatus.UipiBlocked, "uipi_blocked")]
    [InlineData(AgentKeyboardWriteStatus.InputFailed, "keyboard_failed")]
    public async Task Gateway_failures_stay_structured_and_do_not_become_success(
        AgentKeyboardWriteStatus status,
        string expectedCode)
    {
        var result = await new BuiltinAgentKeyboardToolHost(new FakeKeyboard(status))
            .ExecuteAsync(Call(new { action = "press", key = "Escape" }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal(expectedCode, result.Error?.Code);
    }

    private static AgentToolCall Call<T>(T arguments) => new(
        "call-1", "keyboard", JsonSerializer.SerializeToElement(arguments));

    private sealed class FakeKeyboard(
        AgentKeyboardWriteStatus status = AgentKeyboardWriteStatus.Succeeded)
        : IAgentKeyboardGateway
    {
        public string? Typed { get; private set; }
        public List<string> Pressed { get; } = [];

        public Task<AgentKeyboardWriteStatus> TypeAsync(
            string text,
            CancellationToken cancellationToken)
        {
            Typed = text;
            return Task.FromResult(status);
        }

        public Task<AgentKeyboardWriteStatus> PressAsync(
            IReadOnlyList<string> keys,
            CancellationToken cancellationToken)
        {
            Pressed.AddRange(keys);
            return Task.FromResult(status);
        }
    }
}
