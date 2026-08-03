using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Application.Tests.Screenshot;

public sealed class ScreenshotOcrOrchestratorTests
{
    [Fact]
    public async Task Success_preserves_original_image_reference_text_and_line_geometry()
    {
        var runId = Guid.NewGuid();
        var line = new ScreenshotOcrLine(
            "recognized",
            97.5,
            new ScreenshotPixelBounds(10, 20, 100, 30));
        var orchestrator = new ScreenshotOcrOrchestrator(
            new FakeEngine(new(
                ScreenshotOcrEngineStatus.Succeeded,
                "recognized",
                [line])),
            new MutableRunValidity(runId));

        var outcome = await orchestrator.RecognizeAsync(Request(runId), CancellationToken.None);

        Assert.Equal(ScreenshotOcrOutcomeStatus.Succeeded, outcome.Status);
        Assert.Equal("Screenshots/record/original.png", outcome.OriginalImagePath);
        Assert.Equal("recognized", outcome.Text);
        Assert.Equal(line, Assert.Single(outcome.Lines));
        Assert.DoesNotContain(@"C:\private", outcome.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("recognized", outcome.ToString(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(ScreenshotOcrEngineStatus.RuntimeUnavailable, ScreenshotOcrOutcomeStatus.RuntimeUnavailable)]
    [InlineData(ScreenshotOcrEngineStatus.InputUnavailable, ScreenshotOcrOutcomeStatus.InputUnavailable)]
    [InlineData(ScreenshotOcrEngineStatus.Empty, ScreenshotOcrOutcomeStatus.Empty)]
    [InlineData(ScreenshotOcrEngineStatus.TimedOut, ScreenshotOcrOutcomeStatus.TimedOut)]
    [InlineData(ScreenshotOcrEngineStatus.Failed, ScreenshotOcrOutcomeStatus.Failed)]
    public async Task Engine_terminal_statuses_preserve_image_without_exposing_partial_text(
        ScreenshotOcrEngineStatus engineStatus,
        ScreenshotOcrOutcomeStatus expected)
    {
        var runId = Guid.NewGuid();
        var orchestrator = new ScreenshotOcrOrchestrator(
            new FakeEngine(new(engineStatus)),
            new MutableRunValidity(runId));

        var outcome = await orchestrator.RecognizeAsync(Request(runId), CancellationToken.None);

        Assert.Equal(expected, outcome.Status);
        Assert.Equal("Screenshots/record/original.png", outcome.OriginalImagePath);
        Assert.Equal(string.Empty, outcome.Text);
        Assert.Empty(outcome.Lines);
    }

    [Fact]
    public async Task Deadline_returns_timeout_and_caller_cancellation_returns_cancelled()
    {
        var runId = Guid.NewGuid();
        var validity = new MutableRunValidity(runId);
        var timeout = await new ScreenshotOcrOrchestrator(
            new WaitingEngine(),
            validity,
            TimeSpan.FromMilliseconds(30)).RecognizeAsync(Request(runId), CancellationToken.None);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var cancelled = await new ScreenshotOcrOrchestrator(
            new WaitingEngine(),
            validity).RecognizeAsync(Request(runId), cancellation.Token);

        Assert.Equal(ScreenshotOcrOutcomeStatus.TimedOut, timeout.Status);
        Assert.Equal(ScreenshotOcrOutcomeStatus.Cancelled, cancelled.Status);
    }

    [Fact]
    public async Task Late_result_after_run_change_is_stale_and_discards_text()
    {
        var runId = Guid.NewGuid();
        var validity = new MutableRunValidity(runId);
        var engine = new ControllableEngine();
        var task = new ScreenshotOcrOrchestrator(engine, validity)
            .RecognizeAsync(Request(runId), CancellationToken.None);
        await engine.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));

        validity.Current = Guid.NewGuid();
        engine.Completion.SetResult(new(
            ScreenshotOcrEngineStatus.Succeeded,
            "late private text",
            [new ScreenshotOcrLine("late private text", 90, new(0, 0, 20, 10))]));
        var outcome = await task;

        Assert.Equal(ScreenshotOcrOutcomeStatus.Stale, outcome.Status);
        Assert.Equal(string.Empty, outcome.Text);
        Assert.Empty(outcome.Lines);
    }

    private static ScreenshotOcrRequest Request(Guid runId) => new(
        runId,
        "record",
        "Screenshots/record/original.png",
        @"C:\private\record.png",
        "zh-Hans");

    private sealed class MutableRunValidity(Guid current) : IScreenshotRunValidity
    {
        public Guid Current { get; set; } = current;

        public bool IsCurrent(Guid runId) => runId == Current;
    }

    private sealed class FakeEngine(ScreenshotOcrEngineResult result) : IScreenshotOcrEngine
    {
        public Task<ScreenshotOcrEngineResult> RecognizeAsync(
            ScreenshotOcrEngineRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(result);
        }
    }

    private sealed class WaitingEngine : IScreenshotOcrEngine
    {
        public async Task<ScreenshotOcrEngineResult> RecognizeAsync(
            ScreenshotOcrEngineRequest request,
            CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("The cancellation-only OCR fake completed.");
        }
    }

    private sealed class ControllableEngine : IScreenshotOcrEngine
    {
        public TaskCompletionSource Started { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<ScreenshotOcrEngineResult> Completion { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task<ScreenshotOcrEngineResult> RecognizeAsync(
            ScreenshotOcrEngineRequest request,
            CancellationToken cancellationToken)
        {
            Started.SetResult();
            return await Completion.Task.WaitAsync(cancellationToken);
        }
    }
}
