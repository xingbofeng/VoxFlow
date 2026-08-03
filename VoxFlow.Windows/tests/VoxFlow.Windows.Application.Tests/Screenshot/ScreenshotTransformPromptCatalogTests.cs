using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Application.Tests.Screenshot;

public sealed class ScreenshotTransformPromptCatalogTests
{
    [Fact]
    public void Refinement_is_conservative_and_forbids_new_facts()
    {
        var prompt = ScreenshotTransformPromptCatalog.For(ScreenshotTransformOperation.Refinement);

        Assert.Equal("screenshotTextRefinement", prompt.Kind);
        Assert.Equal("v1.0.0", prompt.Version);
        Assert.Contains("obvious OCR", prompt.SystemPrompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Do not add", prompt.SystemPrompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("code", prompt.SystemPrompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Output only", prompt.SystemPrompt, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Translation_targets_simplified_chinese_and_summary_is_capped_at_three_points()
    {
        var translation = ScreenshotTransformPromptCatalog.For(
            ScreenshotTransformOperation.Translation);
        var summary = ScreenshotTransformPromptCatalog.For(
            ScreenshotTransformOperation.Summary);

        Assert.Contains("Simplified Chinese", translation.SystemPrompt, StringComparison.Ordinal);
        Assert.Contains("Do not explain", translation.SystemPrompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("at most three", summary.SystemPrompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("not present", summary.SystemPrompt, StringComparison.OrdinalIgnoreCase);
    }
}
