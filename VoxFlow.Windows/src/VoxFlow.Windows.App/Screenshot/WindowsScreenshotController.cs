using System.Globalization;
using System.Windows.Threading;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

public interface IScreenshotDesktopCapture
{
    Task<FrozenDesktop> FreezeAllDisplaysAsync(CancellationToken cancellationToken);
}

public sealed class Dx11ScreenshotDesktopCapture(Dx11ScreenshotFrameSource frames)
    : IScreenshotDesktopCapture
{
    private readonly Dx11ScreenshotFrameSource frames = frames
        ?? throw new ArgumentNullException(nameof(frames));

    public Task<FrozenDesktop> FreezeAllDisplaysAsync(CancellationToken cancellationToken) =>
        frames.FreezeAllDisplaysAsync(cancellationToken);
}

public interface IScreenshotOverlaySession : IDisposable
{
    bool IsActive { get; }

    void PreserveForegroundWindow()
    {
    }

    Task<ScreenshotOverlayResult?> RunAsync(
        FrozenDesktop desktop,
        Guid runId,
        ScreenshotOverlayResult? resumeState,
        CancellationToken cancellationToken);
}

public sealed class WpfScreenshotOverlaySession : IScreenshotOverlaySession
{
    private readonly ScreenshotOverlayCoordinator coordinator;

    public WpfScreenshotOverlaySession(IScreenshotInlineTranslationService? inlineTranslation) =>
        coordinator = new ScreenshotOverlayCoordinator(inlineTranslation);

    public WpfScreenshotOverlaySession(
        IScreenshotInlineTranslationService? inlineTranslation,
        ScreenshotKeyboardHookRouter keyboardRouter) =>
        coordinator = new ScreenshotOverlayCoordinator(inlineTranslation, keyboardRouter);

    public bool IsActive => coordinator.IsActive;

    public void PreserveForegroundWindow() => coordinator.PreserveForegroundWindow();

    public Task<ScreenshotOverlayResult?> RunAsync(
        FrozenDesktop desktop,
        Guid runId,
        ScreenshotOverlayResult? resumeState,
        CancellationToken cancellationToken) =>
        coordinator.RunAsync(desktop, runId, resumeState, cancellationToken);

    public void Dispose() => coordinator.Dispose();
}

public enum ScreenshotPipelineStatus
{
    Succeeded,
    Cancelled,
    ClipboardFailed,
    ExportFailed,
    CompletionFailed,
}

public sealed record ScreenshotPipelineResult(
    ScreenshotPipelineStatus Status,
    ScreenshotCompletionResult? Completion = null,
    string? SafeMessage = null);

public interface IScreenshotSelectionPipeline
{
    Task<ScreenshotPipelineResult> ProcessAsync(
        ScreenshotOverlayResult result,
        FrozenDesktop desktop,
        CancellationToken cancellationToken);
}

/// <summary>
/// Commits one accepted selection. Download is intentionally isolated from
/// OCR/history, while Complete and OCR both publish the rendered pixels to the
/// clipboard before the transactional asset/OCR/record operation.
/// </summary>
public sealed class ScreenshotSelectionPipeline : IScreenshotSelectionPipeline, IDisposable
{
    private readonly ScreenshotSourceRenderer renderer;
    private readonly ScreenshotThumbnailEncoder thumbnails;
    private readonly ScreenshotClipboardService clipboard;
    private readonly ScreenshotExportService exporter;
    private readonly IScreenshotCompletionService completion;
    private readonly IScreenshotResultPresenter resultPresenter;
    private readonly IScreenshotRenderDispatcher renderDispatcher;
    private readonly bool ownsRenderDispatcher;
    private readonly TimeProvider timeProvider;
    private readonly Action<ScreenshotCompletionResult>? completionPublished;
    private bool disposed;

    public ScreenshotSelectionPipeline(
        ScreenshotSourceRenderer renderer,
        ScreenshotThumbnailEncoder thumbnails,
        ScreenshotClipboardService clipboard,
        ScreenshotExportService exporter,
        IScreenshotCompletionService completion,
        IScreenshotResultPresenter resultPresenter,
        TimeProvider? timeProvider = null,
        Action<ScreenshotCompletionResult>? completionPublished = null,
        IScreenshotRenderDispatcher? renderDispatcher = null)
    {
        this.renderer = renderer ?? throw new ArgumentNullException(nameof(renderer));
        this.thumbnails = thumbnails ?? throw new ArgumentNullException(nameof(thumbnails));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.exporter = exporter ?? throw new ArgumentNullException(nameof(exporter));
        this.completion = completion ?? throw new ArgumentNullException(nameof(completion));
        this.resultPresenter = resultPresenter
            ?? throw new ArgumentNullException(nameof(resultPresenter));
        this.renderDispatcher = renderDispatcher ?? new ScreenshotStaRenderDispatcher();
        ownsRenderDispatcher = renderDispatcher is null;
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.completionPublished = completionPublished;
    }

    public async Task<ScreenshotPipelineResult> ProcessAsync(
        ScreenshotOverlayResult result,
        FrozenDesktop desktop,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(result);
        ArgumentNullException.ThrowIfNull(desktop);
        cancellationToken.ThrowIfCancellationRequested();

        if (result.CompletionKind == ScreenshotCompletionKind.Download)
        {
            // Intentionally capture the caller's dispatcher context after this
            // await: only rendering runs on the STA worker; SaveFileDialog and
            // result-window ownership remain on the application UI thread.
            var finalRender = await renderDispatcher.InvokeAsync(
                () => RenderFinal(result),
                cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            var exported = await exporter.DownloadAsync(
                finalRender,
                CultureInfo.CurrentUICulture,
                cancellationToken);
            return exported.Status switch
            {
                ScreenshotExportStatus.Saved => new(ScreenshotPipelineStatus.Succeeded),
                ScreenshotExportStatus.Cancelled => new(ScreenshotPipelineStatus.Cancelled),
                ScreenshotExportStatus.Failed => new(
                    ScreenshotPipelineStatus.ExportFailed,
                    SafeMessage: exported.ErrorMessage),
                _ => throw new ArgumentOutOfRangeException(),
            };
        }

        var prepared = await renderDispatcher.InvokeAsync(
            () => PrepareCompletion(result),
            cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();

        var copied = await clipboard.CopyAsync(
            prepared.Final,
            CultureInfo.CurrentUICulture,
            cancellationToken);
        if (copied.Status != ScreenshotClipboardWriteStatus.Copied)
        {
            return new ScreenshotPipelineResult(
                ScreenshotPipelineStatus.ClipboardFailed,
                SafeMessage: copied.ErrorMessage);
        }
        var screenshotId = Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture);
        var translatedPng = result.InlineTranslationLines.Count == 0
            ? ReadOnlyMemory<byte>.Empty
            : prepared.Final.PngBytes;
        var completed = await completion.CompleteAsync(
            new ScreenshotCompletionRequest(
                result.RunId,
                screenshotId,
                new ScreenshotAssetWriteRequest(
                    screenshotId,
                    prepared.OriginalPng,
                    prepared.AnnotatedPng,
                    prepared.ThumbnailPng,
                    translatedPng),
                result.Image.Width,
                result.Image.Height,
                timeProvider.GetUtcNow(),
                CultureInfo.CurrentUICulture.Name,
                SourceDisplayId(desktop, result.Selection),
                result.SourceWindowTitle,
                result.InlineTranslationLines.Count == 0
                    ? null
                    : string.Join(
                        Environment.NewLine,
                        result.InlineTranslationLines.Select(line => line.TranslatedText))),
            cancellationToken);

        if (completed.Status != ScreenshotCompletionStatus.Succeeded)
        {
            return new ScreenshotPipelineResult(
                ScreenshotPipelineStatus.CompletionFailed,
                completed,
                completed.SafeErrorCode);
        }

        cancellationToken.ThrowIfCancellationRequested();
        _ = resultPresenter.Present(result.CompletionKind, completed);
        completionPublished?.Invoke(completed);
        return new ScreenshotPipelineResult(ScreenshotPipelineStatus.Succeeded, completed);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        clipboard.Dispose();
        resultPresenter.Dispose();
        if (ownsRenderDispatcher)
        {
            renderDispatcher.Dispose();
        }
    }

    private PreparedScreenshotCompletion PrepareCompletion(ScreenshotOverlayResult result)
    {
        var originalDocument = new ScreenshotDocument(
            Guid.NewGuid(),
            result.Document.CanvasSize,
            [],
            revision: 0);
        var originalPng = renderer.RenderPng(result.Image, originalDocument);
        ScreenshotRenderResult final;
        ReadOnlyMemory<byte> annotatedPng;
        if (result.InlineTranslationLines.Count == 0)
        {
            final = renderer.Render(result.Image, result.Document);
            annotatedPng = final.PngBytes;
        }
        else
        {
            annotatedPng = renderer.RenderPng(result.Image, result.Document);
            final = renderer.Render(
                ScreenshotInlineTranslationRenderer.Apply(
                    result.Image,
                    result.InlineTranslationLines),
                result.Document);
        }
        return new PreparedScreenshotCompletion(
            originalPng,
            annotatedPng,
            final,
            thumbnails.Encode(final.Bitmap));
    }

    private ScreenshotRenderResult RenderFinal(ScreenshotOverlayResult result) =>
        result.InlineTranslationLines.Count == 0
            ? renderer.Render(result.Image, result.Document)
            : renderer.Render(
                ScreenshotInlineTranslationRenderer.Apply(
                    result.Image,
                    result.InlineTranslationLines),
                result.Document);

    private static string? SourceDisplayId(FrozenDesktop desktop, PixelRect selection)
    {
        var selected = new CapturePixelRect(
            selection.Left,
            selection.Top,
            selection.Width,
            selection.Height);
        return desktop.Frames
            .Select(frame => new
            {
                frame.DeviceName,
                Area = frame.Bounds.Intersect(selected) is { } intersection
                    ? (long)intersection.Width * intersection.Height
                    : 0,
            })
            .Where(candidate => candidate.Area > 0)
            .OrderByDescending(candidate => candidate.Area)
            .Select(candidate => candidate.DeviceName)
            .FirstOrDefault();
    }

    private sealed record PreparedScreenshotCompletion(
        ReadOnlyMemory<byte> OriginalPng,
        ReadOnlyMemory<byte> AnnotatedPng,
        ScreenshotRenderResult Final,
        byte[] ThumbnailPng);
}

/// <summary>
/// UI-thread owner for the global screenshot workflow. It freezes every display
/// before creating any overlay and uses the foreground workflow lease to reject
/// re-entrant hotkey, tray, and media-page starts.
/// </summary>
public sealed class WindowsScreenshotController : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly IScreenshotDesktopCapture capture;
    private readonly IScreenshotOverlaySession overlay;
    private readonly IScreenshotSelectionPipeline pipeline;
    private readonly ScreenshotRunRegistry runs;
    private readonly InteractiveWorkflowCoordinator workflows;
    private readonly Func<bool> isVoiceWorkflowActive;
    private readonly Action<string, Exception?> reportFailure;
    private CancellationTokenSource lifetime = new();
    private bool disposed;

    public WindowsScreenshotController(
        Dispatcher dispatcher,
        IScreenshotDesktopCapture capture,
        IScreenshotOverlaySession overlay,
        IScreenshotSelectionPipeline pipeline,
        ScreenshotRunRegistry runs,
        InteractiveWorkflowCoordinator workflows,
        Func<bool>? isVoiceWorkflowActive = null,
        Action<string, Exception?>? reportFailure = null)
    {
        this.dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        this.capture = capture ?? throw new ArgumentNullException(nameof(capture));
        this.overlay = overlay ?? throw new ArgumentNullException(nameof(overlay));
        this.pipeline = pipeline ?? throw new ArgumentNullException(nameof(pipeline));
        this.runs = runs ?? throw new ArgumentNullException(nameof(runs));
        this.workflows = workflows ?? throw new ArgumentNullException(nameof(workflows));
        this.isVoiceWorkflowActive = isVoiceWorkflowActive ?? (() => false);
        this.reportFailure = reportFailure ?? ((_, _) => { });
    }

    public bool IsActive => overlay.IsActive;

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!dispatcher.CheckAccess())
        {
            return dispatcher.InvokeAsync(
                    () => StartAsync(cancellationToken),
                    DispatcherPriority.Input)
                .Task
                .Unwrap();
        }
        return StartOnUiThreadAsync(cancellationToken);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        lifetime.Cancel();
        overlay.Dispose();
        if (pipeline is IDisposable disposablePipeline)
        {
            disposablePipeline.Dispose();
        }
        lifetime.Dispose();
        lifetime = null!;
    }

    private async Task StartOnUiThreadAsync(CancellationToken cancellationToken)
    {
        if (isVoiceWorkflowActive())
        {
            reportFailure("screenshot.capture.busy", null);
            return;
        }
        var lease = workflows.TryAcquire(InteractiveWorkflowKind.Screenshot);
        if (lease is null)
        {
            reportFailure("screenshot.capture.busy", null);
            return;
        }

        var runId = runs.Begin();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            lifetime.Token,
            lease.CancellationToken);
        try
        {
            // Capture the user's foreground window before the first asynchronous
            // freeze step can yield back to WPF or native capture work.
            overlay.PreserveForegroundWindow();
            // This await must finish before the first overlay window is shown.
            var desktop = await capture.FreezeAllDisplaysAsync(linked.Token);
            if (!runs.IsCurrent(runId) || !workflows.IsCurrent(lease))
            {
                return;
            }
            ScreenshotOverlayResult? resumeState = null;
            while (true)
            {
                var accepted = await overlay.RunAsync(
                    desktop,
                    runId,
                    resumeState,
                    linked.Token);
                if (accepted is null)
                {
                    runs.Invalidate(runId);
                    _ = workflows.Cancel(lease);
                    return;
                }
                if (accepted.RunId != runId
                    || !runs.IsCurrent(runId)
                    || !workflows.IsCurrent(lease))
                {
                    runs.Invalidate(runId);
                    _ = workflows.Cancel(lease);
                    return;
                }

                var outcome = await pipeline.ProcessAsync(accepted, desktop, linked.Token);
                linked.Token.ThrowIfCancellationRequested();
                if (!runs.IsCurrent(runId) || !workflows.IsCurrent(lease))
                {
                    runs.Invalidate(runId);
                    _ = workflows.Cancel(lease);
                    return;
                }
                if (outcome.Status == ScreenshotPipelineStatus.Succeeded)
                {
                    if (outcome.Completion is { Status: ScreenshotCompletionStatus.Succeeded }
                        completion)
                    {
                        _ = runs.PublishResult(completion.RunId);
                    }
                    _ = workflows.Complete(lease);
                    return;
                }

                if (outcome.Status is ScreenshotPipelineStatus.ExportFailed
                    or ScreenshotPipelineStatus.CompletionFailed
                    or ScreenshotPipelineStatus.ClipboardFailed)
                {
                    reportFailure(outcome.SafeMessage ?? "screenshot.capture.failed", null);
                }

                // Save-dialog cancellation and retryable clipboard/export/OCR persistence
                // failures return to the same frozen selection and annotation document.
                resumeState = accepted;
            }
        }
        catch (OperationCanceledException) when (linked.IsCancellationRequested)
        {
            runs.Invalidate(runId);
            _ = workflows.Cancel(lease);
        }
        catch (Exception exception)
        {
            runs.Invalidate(runId);
            _ = workflows.Cancel(lease);
            reportFailure("screenshot.capture.failed", exception);
        }
    }
}
