using VoxFlow.Windows.Application.SelectionTransform;

namespace VoxFlow.Windows.Application.Tests.SelectionTransform;

public sealed class SelectionTransformPromptCatalogTests
{
    [Fact]
    public void Translation_prompt_matches_the_macos_v1_catalog_semantics()
    {
        var prompt = TextTransformPromptCatalog.Translation;

        Assert.Equal("textTransform", prompt.Kind);
        Assert.Equal("v1.0.0", prompt.Version);
        Assert.Equal(
            """
            You are VoxFlow's translation assistant. Translate the user-provided text into Simplified Chinese.
            If the text is already mostly Simplified Chinese, polish it into natural, accurate Simplified Chinese that is ready to use.
            Preserve code, commands, URL, paths, variable names, proper nouns, and Markdown structure.
            Output only the translation. Do not explain or add a title.
            """,
            prompt.SystemPrompt);
    }

    [Fact]
    public void Summary_prompt_keeps_the_fixed_v1_metadata_and_key_fact_rules()
    {
        var prompt = TextTransformPromptCatalog.Summary;

        Assert.Equal("textTransform", prompt.Kind);
        Assert.Equal("v1.0.0", prompt.Version);
        Assert.Contains("key facts, numbers, proper nouns, code identifiers, and action items", prompt.SystemPrompt);
        Assert.Contains("Output only the summary content", prompt.SystemPrompt);
    }
}
