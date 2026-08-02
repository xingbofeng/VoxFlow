using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Application.Tests.Screenshot;

public sealed class ScreenshotResultStateTests
{
    [Fact]
    public void Translation_failure_preserves_original_ocr_and_previous_successful_summary()
    {
        var runId = Guid.NewGuid();
        var state = new ScreenshotResultState(
            runId,
            "record",
            "Screenshots/record/original.png",
            "original OCR",
            []);
        state.Apply(new ScreenshotTransformStarted(
            runId,
            "record",
            ScreenshotTransformOperation.Summary));
        state.Apply(new ScreenshotTransformCompleted(
            runId,
            "record",
            ScreenshotTransformOperation.Summary,
            "successful summary",
            fromCache: false));
        state.Apply(new ScreenshotTransformStarted(
            runId,
            "record",
            ScreenshotTransformOperation.Translation));
        state.Apply(new ScreenshotTransformPartial(
            runId,
            "record",
            ScreenshotTransformOperation.Translation,
            "partial translation"));
        state.Apply(new ScreenshotTransformFailed(
            runId,
            "record",
            ScreenshotTransformOperation.Translation,
            "The provider failed.",
            "partial translation"));

        Assert.Equal("original OCR", state.OriginalOcrText);
        Assert.Equal("successful summary", state.SummaryText);
        Assert.Null(state.TranslatedText);
        Assert.Equal("partial translation", state.GetPartial(ScreenshotTransformOperation.Translation));
        Assert.Equal(
            ScreenshotTransformStatus.Failed,
            state.GetStatus(ScreenshotTransformOperation.Translation));
    }

    [Fact]
    public void Late_other_run_or_screenshot_events_are_ignored()
    {
        var runId = Guid.NewGuid();
        var state = new ScreenshotResultState(
            runId,
            "current",
            "Screenshots/current/original.png",
            "original",
            []);

        Assert.False(state.Apply(new ScreenshotTransformCompleted(
            Guid.NewGuid(),
            "current",
            ScreenshotTransformOperation.Translation,
            "late run",
            false)));
        Assert.False(state.Apply(new ScreenshotTransformCompleted(
            runId,
            "other",
            ScreenshotTransformOperation.Translation,
            "wrong screenshot",
            false)));

        Assert.Null(state.TranslatedText);
        Assert.Equal("original", state.OriginalOcrText);
    }

    [Fact]
    public void Each_completed_operation_updates_only_its_own_content_partition()
    {
        var runId = Guid.NewGuid();
        var state = new ScreenshotResultState(
            runId,
            "record",
            "Screenshots/record/original.png",
            "ocr",
            []);

        Complete(state, ScreenshotTransformOperation.Refinement, "refined");
        Complete(state, ScreenshotTransformOperation.Translation, "translated");
        Complete(state, ScreenshotTransformOperation.Summary, "summary");

        Assert.Equal("ocr", state.OriginalOcrText);
        Assert.Equal("refined", state.RefinedText);
        Assert.Equal("translated", state.TranslatedText);
        Assert.Equal("summary", state.SummaryText);
    }

    private static void Complete(
        ScreenshotResultState state,
        ScreenshotTransformOperation operation,
        string text)
    {
        state.Apply(new ScreenshotTransformStarted(
            state.RunId,
            state.ScreenshotId,
            operation));
        state.Apply(new ScreenshotTransformCompleted(
            state.RunId,
            state.ScreenshotId,
            operation,
            text,
            false));
    }
}
