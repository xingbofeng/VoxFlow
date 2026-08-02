using System.Windows.Threading;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class WindowsScreenshotControllerTests
{
    [Fact]
    public async Task Freeze_finishes_before_overlay_and_accepted_result_reaches_pipeline()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            List<string> order = [];
            var desktop = Desktop();
            var capture = new FakeCapture(() =>
            {
                Assert.Equal(["preserve"], order);
                order.Add("capture");
                return desktop;
            });
            var overlay = new FakeOverlay((frozen, runId, _, _) =>
            {
                Assert.Same(desktop, frozen);
                Assert.Equal(["preserve", "capture"], order);
                order.Add("overlay");
                return Task.FromResult<ScreenshotOverlayResult?>(Accepted(runId));
            });
            overlay.OnPreserve = () => order.Add("preserve");
            var pipeline = new FakePipeline((result, frozen, _) =>
            {
                Assert.Same(desktop, frozen);
                Assert.Equal(["preserve", "capture", "overlay"], order);
                order.Add("pipeline");
                return Task.FromResult(new ScreenshotPipelineResult(
                    ScreenshotPipelineStatus.Succeeded));
            });
            var runs = new ScreenshotRunRegistry();
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                capture,
                overlay,
                pipeline,
                runs,
                new InteractiveWorkflowCoordinator());

            await controller.StartAsync();

            Assert.Equal(["preserve", "capture", "overlay", "pipeline"], order);
            Assert.Single(overlay.RunIds);
            Assert.True(runs.IsCurrent(overlay.RunIds[0]));
        });
    }

    [Fact]
    public async Task Cancelling_overlay_invalidates_run_and_skips_pipeline()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var capture = new FakeCapture(Desktop);
            var overlay = new FakeOverlay((_, _, _, _) =>
                Task.FromResult<ScreenshotOverlayResult?>(null));
            var pipeline = new FakePipeline();
            var runs = new ScreenshotRunRegistry();
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                capture,
                overlay,
                pipeline,
                runs,
                new InteractiveWorkflowCoordinator());

            await controller.StartAsync();

            Assert.Empty(pipeline.Results);
            Assert.Single(overlay.RunIds);
            Assert.False(runs.IsCurrent(overlay.RunIds[0]));
        });
    }

    [Fact]
    public async Task Active_voice_workflow_rejects_capture_with_safe_feedback()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var capture = new FakeCapture(Desktop);
            List<string> failures = [];
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                capture,
                new FakeOverlay(),
                new FakePipeline(),
                new ScreenshotRunRegistry(),
                new InteractiveWorkflowCoordinator(),
                isVoiceWorkflowActive: () => true,
                reportFailure: (message, _) => failures.Add(message));

            await controller.StartAsync();

            Assert.Equal(0, capture.CallCount);
            Assert.Equal(["screenshot.capture.busy"], failures);
        });
    }

    [Fact]
    public async Task Reentrant_start_is_rejected_while_first_overlay_owns_lease()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var overlayResult = new TaskCompletionSource<ScreenshotOverlayResult?>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var capture = new FakeCapture(Desktop);
            var overlay = new FakeOverlay((_, _, _, _) => overlayResult.Task);
            List<string> failures = [];
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                capture,
                overlay,
                new FakePipeline(),
                new ScreenshotRunRegistry(),
                new InteractiveWorkflowCoordinator(),
                reportFailure: (message, _) => failures.Add(message));

            var first = controller.StartAsync();
            await Task.Yield();
            await controller.StartAsync();

            Assert.Equal(1, capture.CallCount);
            Assert.Equal(["screenshot.capture.busy"], failures);
            overlayResult.SetResult(null);
            await first;
        });
    }

    [Fact]
    public async Task Invalidated_run_cannot_publish_or_complete_after_async_pipeline_returns()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var pipelineStarted = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var releasePipeline = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var overlay = new FakeOverlay((_, runId, _, _) =>
                Task.FromResult<ScreenshotOverlayResult?>(Accepted(runId)));
            var pipeline = new FakePipeline(async (accepted, _, _) =>
            {
                pipelineStarted.TrySetResult();
                await releasePipeline.Task;
                return new ScreenshotPipelineResult(
                    ScreenshotPipelineStatus.Succeeded,
                    new ScreenshotCompletionResult(
                        accepted.RunId,
                        "stale-record",
                        ScreenshotCompletionStatus.Succeeded,
                        Record("stale-record")));
            });
            var runs = new ScreenshotRunRegistry();
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                new FakeCapture(Desktop),
                overlay,
                pipeline,
                runs,
                new InteractiveWorkflowCoordinator());

            var pending = controller.StartAsync();
            await pipelineStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
            var acceptedRun = Assert.Single(overlay.RunIds);
            var replacementRun = runs.Begin();
            releasePipeline.TrySetResult();
            await pending.WaitAsync(TimeSpan.FromSeconds(2));

            Assert.False(runs.IsResultCurrent(acceptedRun));
            Assert.True(runs.IsCurrent(replacementRun));
        });
    }

    [Fact]
    public async Task Retryable_commit_failure_reopens_the_same_frozen_document_until_success()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            ScreenshotOverlayResult? firstAccepted = null;
            var overlay = new FakeOverlay((_, runId, resumeState, _) =>
            {
                firstAccepted ??= Accepted(runId);
                return Task.FromResult<ScreenshotOverlayResult?>(resumeState ?? firstAccepted);
            });
            var attempt = 0;
            var pipeline = new FakePipeline((_, _, _) => Task.FromResult(
                ++attempt == 1
                    ? new ScreenshotPipelineResult(
                        ScreenshotPipelineStatus.ClipboardFailed,
                        SafeMessage: "retry clipboard")
                    : new ScreenshotPipelineResult(ScreenshotPipelineStatus.Succeeded)));
            List<string> failures = [];
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                new FakeCapture(Desktop),
                overlay,
                pipeline,
                new ScreenshotRunRegistry(),
                new InteractiveWorkflowCoordinator(),
                reportFailure: (message, _) => failures.Add(message));

            await controller.StartAsync();

            Assert.Equal(2, overlay.RunIds.Count);
            Assert.Null(overlay.ResumeStates[0]);
            Assert.Same(firstAccepted, overlay.ResumeStates[1]);
            Assert.Equal(2, pipeline.Results.Count);
            Assert.Equal(["retry clipboard"], failures);
        });
    }

    [Fact]
    public async Task Completed_result_panel_transform_persists_after_next_capture_begins_and_cancels()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            const string screenshotId = "record-a";
            var overlayAttempt = 0;
            var overlay = new FakeOverlay((_, runId, _, _) => Task.FromResult(
                ++overlayAttempt == 1
                    ? Accepted(runId)
                    : null));
            var pipeline = new FakePipeline((accepted, _, _) => Task.FromResult(
                new ScreenshotPipelineResult(
                    ScreenshotPipelineStatus.Succeeded,
                    new ScreenshotCompletionResult(
                        accepted.RunId,
                        screenshotId,
                        ScreenshotCompletionStatus.Succeeded,
                        Record(screenshotId)))));
            var runs = new ScreenshotRunRegistry();
            using var controller = new WindowsScreenshotController(
                Dispatcher.CurrentDispatcher,
                new FakeCapture(Desktop),
                overlay,
                pipeline,
                runs,
                new InteractiveWorkflowCoordinator());

            await controller.StartAsync();

            var runA = overlay.RunIds[0];
            Assert.True(runs.IsResultCurrent(runA));

            await controller.StartAsync();

            var runB = overlay.RunIds[1];
            Assert.NotEqual(runA, runB);
            Assert.False(runs.IsCurrent(runB));
            Assert.True(runs.IsResultCurrent(runA));

            var repository = new MemoryScreenshotRepository([Record(screenshotId)]);
            var persistence = new ScreenshotTransformPersistenceCoordinator(
                repository,
                new FixedTimeProvider(),
                runs);
            var completed = new ScreenshotTransformCompleted(
                runA,
                screenshotId,
                ScreenshotTransformOperation.Summary,
                "A remains persistable",
                fromCache: false);

            Assert.True(persistence.Persist(completed));
            Assert.Equal("A remains persistable", repository.Get(screenshotId)!.SummaryText);
        });
    }

    private static ScreenshotOverlayResult Accepted(Guid runId)
    {
        var image = new FrozenScreenshot(
            4,
            3,
            16,
            Enumerable.Repeat(byte.MaxValue, 48).ToArray());
        return new ScreenshotOverlayResult(
            runId,
            ScreenshotCompletionKind.Complete,
            new PixelRect(0, 0, 4, 3),
            image,
            new ScreenshotDocument(
                Guid.NewGuid(),
                new PixelSize(4, 3),
                [],
                revision: 0),
            []);
    }

    private static ScreenshotRecord Record(string id) => new(
        id,
        $"Screenshots/{id}/original.png",
        $"Screenshots/{id}/rendered.png",
        $"Screenshots/{id}/thumbnail.png",
        widthPixels: 4,
        heightPixels: 3,
        fileSizeBytes: 48,
        ocrText: "source OCR",
        createdAtUtc: new DateTimeOffset(2026, 7, 14, 8, 0, 0, TimeSpan.Zero));

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            new(2026, 7, 14, 9, 0, 0, TimeSpan.Zero);
    }

    private static FrozenDesktop Desktop() => new(
    [
        new FrozenDisplayFrame(
            "DISPLAY1",
            "adapter",
            new CapturePixelRect(0, 0, 4, 3),
            rotationDegrees: 0,
            stride: 16,
            Enumerable.Repeat(byte.MaxValue, 48).ToArray()),
    ]);

    private sealed class FakeCapture(Func<FrozenDesktop> create) : IScreenshotDesktopCapture
    {
        public int CallCount { get; private set; }

        public Task<FrozenDesktop> FreezeAllDisplaysAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            return Task.FromResult(create());
        }
    }

    private sealed class FakeOverlay : IScreenshotOverlaySession
    {
        private readonly Func<FrozenDesktop, Guid, ScreenshotOverlayResult?, CancellationToken,
            Task<ScreenshotOverlayResult?>> run;

        public FakeOverlay(
            Func<FrozenDesktop, Guid, ScreenshotOverlayResult?, CancellationToken,
                Task<ScreenshotOverlayResult?>>? run = null) =>
            this.run = run ?? ((_, _, _, _) => Task.FromResult<ScreenshotOverlayResult?>(null));

        public List<Guid> RunIds { get; } = [];

        public List<ScreenshotOverlayResult?> ResumeStates { get; } = [];

        public Action? OnPreserve { get; set; }

        public int PreserveCalls { get; private set; }

        public bool IsActive { get; private set; }

        public void PreserveForegroundWindow()
        {
            PreserveCalls++;
            OnPreserve?.Invoke();
        }

        public async Task<ScreenshotOverlayResult?> RunAsync(
            FrozenDesktop desktop,
            Guid runId,
            ScreenshotOverlayResult? resumeState,
            CancellationToken cancellationToken)
        {
            RunIds.Add(runId);
            ResumeStates.Add(resumeState);
            IsActive = true;
            try
            {
                return await run(desktop, runId, resumeState, cancellationToken);
            }
            finally
            {
                IsActive = false;
            }
        }

        public void Dispose() => IsActive = false;
    }

    private sealed class FakePipeline : IScreenshotSelectionPipeline
    {
        private readonly Func<ScreenshotOverlayResult, FrozenDesktop, CancellationToken,
            Task<ScreenshotPipelineResult>> process;

        public FakePipeline(
            Func<ScreenshotOverlayResult, FrozenDesktop, CancellationToken,
                Task<ScreenshotPipelineResult>>? process = null) =>
            this.process = process ?? ((_, _, _) => Task.FromResult(
                new ScreenshotPipelineResult(ScreenshotPipelineStatus.Succeeded)));

        public List<ScreenshotOverlayResult> Results { get; } = [];

        public Task<ScreenshotPipelineResult> ProcessAsync(
            ScreenshotOverlayResult result,
            FrozenDesktop desktop,
            CancellationToken cancellationToken)
        {
            Results.Add(result);
            return process(result, desktop, cancellationToken);
        }
    }
}
