using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentSidecarEventParserTests
{
    [Theory]
    [InlineData("{\"event\":\"turnStarted\",\"step\":1}")]
    [InlineData("{\"event\":\"modelDelta\",\"text\":\"hello\"}")]
    [InlineData("{\"event\":\"turnCompleted\",\"summary\":\"done\"}")]
    [InlineData("{\"event\":\"error\",\"reason\":\"safe\"}")]
    public void Known_events_are_parsed_as_normalized_contracts(string line)
    {
        var result = BuiltinAgentSidecarEventParser.ParseLine(line);

        Assert.Equal(BuiltinAgentSidecarParseStatus.Event, result.Status);
        Assert.NotNull(result.Event);
    }

    [Fact]
    public void Tool_request_requires_a_tool_call_and_unknown_events_are_not_accepted()
    {
        var incompleteTool = BuiltinAgentSidecarEventParser.ParseLine("{\"event\":\"toolRequested\"}");
        var unknown = BuiltinAgentSidecarEventParser.ParseLine("{\"event\":\"futureThing\",\"secret\":\"x\"}");

        Assert.Equal(BuiltinAgentSidecarParseStatus.Invalid, incompleteTool.Status);
        Assert.Equal(BuiltinAgentSidecarParseStatus.UnknownEvent, unknown.Status);
        Assert.Null(unknown.Event);
    }

    [Theory]
    [InlineData("{\"schemaVersion\":0,\"event\":\"modelDelta\",\"text\":\"legacy\"}")]
    [InlineData("{\"schemaVersion\":2,\"event\":\"modelDelta\",\"text\":\"future\"}")]
    public void Non_current_schema_is_rejected_before_an_event_reaches_the_host(string line)
    {
        var result = BuiltinAgentSidecarEventParser.ParseLine(line);

        Assert.Equal(BuiltinAgentSidecarParseStatus.UnsupportedSchema, result.Status);
        Assert.Null(result.Event);
        Assert.Equal("unsupported_schema_version", result.SafeMessage);
    }

    [Fact]
    public void Blank_and_partial_lines_are_classified_without_echoing_payload()
    {
        var blank = BuiltinAgentSidecarEventParser.ParseLine("  ");
        var partial = BuiltinAgentSidecarEventParser.ParseLine("{\"event\":\"modelDelta\"");

        Assert.Equal(BuiltinAgentSidecarParseStatus.Empty, blank.Status);
        Assert.Equal(BuiltinAgentSidecarParseStatus.Incomplete, partial.Status);
        Assert.Null(partial.SafeMessage);
    }
}
