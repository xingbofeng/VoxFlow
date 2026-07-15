using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Application.Tests;

public sealed class GlossaryTextProcessorTests
{
    [Fact]
    public void Applies_enabled_rules_longest_first_and_preserves_disabled_rules()
    {
        var document = new GlossaryDocument(
            [],
            [
                new(Guid.NewGuid(), "voice", "speech"),
                new(Guid.NewGuid(), "voice input", "dictation"),
                new(Guid.NewGuid(), "leave me", "changed", Enabled: false),
            ],
            []);

        var result = GlossaryTextProcessor.Apply(
            "voice input and voice; leave me",
            document);

        Assert.Equal("dictation and speech; leave me", result);
    }

    [Fact]
    public void Whole_word_rule_does_not_replace_inside_identifiers()
    {
        var document = new GlossaryDocument(
            [],
            [new(Guid.NewGuid(), "flow", "stream", MatchWholeWord: true)],
            []);

        var result = GlossaryTextProcessor.Apply("flow workflow flow_id", document);

        Assert.Equal("stream workflow flow_id", result);
    }
}
