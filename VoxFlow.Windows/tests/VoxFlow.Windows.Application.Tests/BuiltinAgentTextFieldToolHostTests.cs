using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentTextFieldToolHostTests
{
    [Fact]
    public async Task Reads_only_the_frozen_untrusted_text_context()
    {
        var host = Host();

        var selected = await host.ExecuteAsync(Call(new { action = "read_selection" }), CancellationToken.None);
        var all = await host.ExecuteAsync(Call(new { action = "read_all" }), CancellationToken.None);

        Assert.True(selected.Ok);
        Assert.Equal("selected text", selected.Result!.Value.GetProperty("text").GetString());
        Assert.True(selected.Result!.Value.GetProperty("untrusted").GetBoolean());
        Assert.True(all.Ok);
        Assert.Equal("focused input", all.Result!.Value.GetProperty("text").GetString());
    }

    [Fact]
    public async Task Insert_and_replace_delegate_to_the_revalidated_gateway_without_submit()
    {
        var gateway = new FakeGateway();
        var host = Host(gateway);

        var insert = await host.ExecuteAsync(Call(new { action = "insert", text = "draft" }), CancellationToken.None);
        var replace = await host.ExecuteAsync(Call(new { action = "replace_selection", text = "edited" }), CancellationToken.None);

        Assert.True(insert.Ok);
        Assert.True(replace.Ok);
        Assert.Equal("draft", gateway.Inserted);
        Assert.Equal("edited", gateway.Replaced);
    }

    [Theory]
    [InlineData(AgentTextFieldWriteStatus.ReadOnly, "readonly_text_field")]
    [InlineData(AgentTextFieldWriteStatus.TargetChanged, "target_changed")]
    [InlineData(AgentTextFieldWriteStatus.Secure, "secure_text_field")]
    [InlineData(AgentTextFieldWriteStatus.UipiBlocked, "uipi_blocked")]
    public async Task Write_failures_are_structured_and_never_claim_success(
        AgentTextFieldWriteStatus status,
        string code)
    {
        var result = await Host(new FakeGateway(status)).ExecuteAsync(
            Call(new { action = "replace_selection", text = "draft" }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal(code, result.Error?.Code);
    }

    [Fact]
    public async Task Missing_frozen_selection_cannot_fall_back_to_the_current_cursor()
    {
        var context = new AgentContextSnapshot(
            Target(), null, Array.Empty<string>(), FocusedInputText: "input");
        var result = await new BuiltinAgentTextFieldToolHost(context, new FakeGateway())
            .ExecuteAsync(Call(new { action = "insert", text = "draft" }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("missing_selection", result.Error?.Code);
    }

    private static BuiltinAgentTextFieldToolHost Host(FakeGateway? gateway = null) => new(
        new AgentContextSnapshot(
            Target(),
            "selected text",
            Array.Empty<string>(),
            FocusedInputText: "focused input",
            Selection: Selection()),
        gateway ?? new FakeGateway());

    private static AgentToolCall Call<T>(T value) => new(
        "call-1", "text_field", JsonSerializer.SerializeToElement(value));

    private static ForegroundTargetSnapshot Target() => new(
        1, 2, "notepad.exe", "Draft", new WindowBounds(0, 0, 100, 100),
        ProcessIntegrityLevel.Medium, [1], 1);

    private static SelectionSnapshot Selection() => new(
        "selected text", SelectionAcquisitionSource.UiAutomation, Target(), [1],
        [new SelectionRangeSnapshot(0, "selected text", [new WindowBounds(1, 1, 10, 10)], null, null)],
        SelectionEditability.Editable, true, 1);

    private sealed class FakeGateway(
        AgentTextFieldWriteStatus status = AgentTextFieldWriteStatus.Succeeded)
        : IAgentTextFieldGateway
    {
        public string? Inserted { get; private set; }
        public string? Replaced { get; private set; }

        public Task<AgentTextFieldWriteStatus> InsertAsync(string text, CancellationToken cancellationToken)
        {
            Inserted = text;
            return Task.FromResult(status);
        }

        public Task<AgentTextFieldWriteStatus> ReplaceSelectionAsync(string text, CancellationToken cancellationToken)
        {
            Replaced = text;
            return Task.FromResult(status);
        }
    }
}
