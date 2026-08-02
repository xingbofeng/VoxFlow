using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Application.Tests;

public sealed class WritingStyleParityTests
{
    [Fact]
    public void Default_catalog_includes_seven_built_in_styles()
    {
        var document = WritingStyleDocument.Default.Normalize();

        Assert.Equal(7, document.Profiles.Count);
        Assert.All(document.Profiles, profile => Assert.True(profile.IsBuiltIn));
        Assert.Contains(document.Profiles, p => p.Id == WritingStyleDocument.EmailProfileId);
        Assert.Contains(document.Profiles, p => p.Id == WritingStyleDocument.MeetingProfileId);
        Assert.Contains(document.Profiles, p => p.Id == WritingStyleDocument.TranslationProfileId);
    }

    [Fact]
    public void Normalize_reinserts_missing_built_ins_and_keeps_custom_styles()
    {
        var customId = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        var document = new WritingStyleDocument(
            [
                new WritingStyleProfile(
                    customId,
                    "Custom",
                    "Mine",
                    "Do something",
                    string.Empty,
                    ["Notepad"],
                    false,
                    true),
            ],
            customId,
            true).Normalize();

        Assert.Equal(8, document.Profiles.Count);
        Assert.Contains(document.Profiles, p => p.Id == customId && !p.IsBuiltIn);
        Assert.Equal(7, document.Profiles.Count(p => p.IsBuiltIn));
    }

    [Fact]
    public void AiMatchCandidates_respects_per_style_flag()
    {
        var document = WritingStyleDocument.Default with
        {
            AiAutoMatch = true,
            Profiles = WritingStyleDocument.BuiltInCatalog
                .Select(profile => profile with
                {
                    AiAutoMatchEnabled = profile.Id != WritingStyleDocument.CodingProfileId,
                })
                .ToArray(),
        };

        var candidates = document.AiMatchCandidates;
        Assert.Equal(6, candidates.Count);
        Assert.DoesNotContain(candidates, p => p.Id == WritingStyleDocument.CodingProfileId);
    }

    [Fact]
    public void Application_context_matches_process_path_and_window_title_routes()
    {
        var context = new WritingStyleApplicationContext(
            @"C:\Program Files\Microsoft VS Code\Code.exe",
            "README.md - VoxFlow");

        Assert.True(context.Matches("Code"));
        Assert.True(context.Matches("VoxFlow"));
        Assert.False(context.Matches("Outlook"));
    }

    [Fact]
    public void Markdown_preview_renders_structure_not_raw_source()
    {
        var markdown = """
            ## Title

            - first **item**
            - second

            ```text
            {{content}}
            ```
            """;

        var blocks = MarkdownPreviewModel.Parse(markdown, "hello world");
        Assert.Contains(blocks, b => b.Kind == MarkdownPreviewBlockKind.Heading2 && b.Text == "Title");
        Assert.Contains(blocks, b => b.Kind == MarkdownPreviewBlockKind.Bullet && b.Text == "first item");
        Assert.Contains(blocks, b => b.Kind == MarkdownPreviewBlockKind.Code && b.Text.Contains("hello world"));

        var rendered = MarkdownPreviewModel.RenderStructuredText(markdown, "hello world");
        Assert.DoesNotContain("**item**", rendered);
        Assert.Contains("• first item", rendered);
        Assert.Contains("hello world", rendered);
        Assert.True(MarkdownPreviewModel.HasRenderableStructure(markdown));
    }
}
