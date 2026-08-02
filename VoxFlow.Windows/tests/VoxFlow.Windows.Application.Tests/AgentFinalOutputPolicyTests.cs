using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;
using System.Text.Json;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentFinalOutputPolicyTests
{
    [Fact]
    public void Text_without_successful_side_effect_is_copied() =>
        Assert.Equal(AgentFinalOutputKind.CopyText, AgentFinalOutputPolicy.Decide("reply", []).Kind);

    [Fact]
    public void Successful_write_shows_summary_without_copying() =>
        Assert.Equal(AgentFinalOutputKind.ShowSummary, AgentFinalOutputPolicy.Decide("created", [AgentToolResult.Success("write_file")]).Kind);

    [Fact]
    public void Empty_completion_without_effect_fails() =>
        Assert.Equal("missing_completion", AgentFinalOutputPolicy.Decide(null, []).ErrorCode);

    [Theory]
    [InlineData("read_file", "read", AgentFinalOutputKind.CopyText)]
    [InlineData("web_search", "search", AgentFinalOutputKind.CopyText)]
    [InlineData("http_request", "GET", AgentFinalOutputKind.CopyText)]
    [InlineData("http_request", "POST", AgentFinalOutputKind.ShowSummary)]
    [InlineData("clipboard", "read_text", AgentFinalOutputKind.CopyText)]
    [InlineData("clipboard", "write_text", AgentFinalOutputKind.ShowSummary)]
    [InlineData("text_field", "read_all", AgentFinalOutputKind.CopyText)]
    [InlineData("text_field", "insert", AgentFinalOutputKind.ShowSummary)]
    public void Tool_effect_classification_matches_help_me_say_and_help_me_do(
        string toolName,
        string action,
        AgentFinalOutputKind expected)
    {
        var result = AgentToolResult.Success(toolName, JsonSerializer.SerializeToElement(new { action }));

        Assert.Equal(expected, AgentFinalOutputPolicy.Decide("final", [result]).Kind);
    }

    [Fact]
    public void Empty_completion_after_a_successful_effect_keeps_the_effect_and_shows_no_fake_copy()
    {
        var decision = AgentFinalOutputPolicy.Decide(null, [AgentToolResult.Success("write_file")]);

        Assert.Equal(AgentFinalOutputKind.ShowSummary, decision.Kind);
        Assert.Null(decision.Text);
    }
}
