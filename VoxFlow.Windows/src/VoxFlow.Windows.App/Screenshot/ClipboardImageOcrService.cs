using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Screenshot;

public enum ClipboardImageOcrStatus
{
    Succeeded,
    Disabled,
    NoImage,
    NoText,
    Busy,
    Failed,
    Cancelled,
}

public sealed record ClipboardImageOcrResult(
    ClipboardImageOcrStatus Status,
    ScreenshotCompletionResult? Completion = null,
    string? SafeErrorCode = null);

/// <summary>
/// Reads a bitmap from the system clipboard, persists it through the same
/// asset/OCR/record path as screenshot completion, and opens the result panel.
/// </summary>
/// <summary>
/// Optional seam for tests: returns PNG bytes and dimensions from the clipboard
/// without touching the real system clipboard.
/// </summary>
public delegate bool ClipboardImagePngReader(
    out byte[] pngBytes,
    out int width,
    out int height);

public sealed class ClipboardImageOcrService : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly IScreenshotCompletionService completion;
    private readonly IScreenshotResultPresenter resultPresenter;
    private readonly ScreenshotRunRegistry runs;
    private readonly InteractiveWorkflowCoordinator workflows;
    private readonly ScreenshotThumbnailEncoder thumbnails;
    private readonly Func<bool> isEnabled;
    private readonly Func<bool> isVoiceWorkflowActive;
    private readonly Action<ScreenshotCompletionResult>? completionPublished;
    private readonly Action<string, Exception?> reportFailure;
    private readonly ClipboardImagePngReader readClipboardPng;
    private readonly Func<uint> readClipboardSequence;
    private readonly object processGate = new();
    private CancellationTokenSource lifetime = new();
    private uint lastProcessedSequence;
    private bool isProcessing;
    private bool disposed;

    public ClipboardImageOcrService(
        Dispatcher dispatcher,
        IScreenshotCompletionService completion,
        IScreenshotResultPresenter resultPresenter,
        ScreenshotRunRegistry runs,
        InteractiveWorkflowCoordinator workflows,
        Func<bool> isEnabled,
        Func<bool>? isVoiceWorkflowActive = null,
        Action<ScreenshotCompletionResult>? completionPublished = null,
        Action<string, Exception?>? reportFailure = null,
        ScreenshotThumbnailEncoder? thumbnails = null,
        ClipboardImagePngReader? readClipboardPng = null,
        Func<uint>? readClipboardSequence = null)
    {
        this.dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        this.completion = completion ?? throw new ArgumentNullException(nameof(completion));
        this.resultPresenter = resultPresenter
            ?? throw new ArgumentNullException(nameof(resultPresenter));
        this.runs = runs ?? throw new ArgumentNullException(nameof(runs));
        this.workflows = workflows ?? throw new ArgumentNullException(nameof(workflows));
        this.isEnabled = isEnabled ?? throw new ArgumentNullException(nameof(isEnabled));
        this.isVoiceWorkflowActive = isVoiceWorkflowActive ?? (() => false);
        this.completionPublished = completionPublished;
        this.reportFailure = reportFailure ?? ((_, _) => { });
        this.thumbnails = thumbnails ?? new ScreenshotThumbnailEncoder();
        this.readClipboardPng = readClipboardPng ?? TryReadClipboardPng;
        this.readClipboardSequence = readClipboardSequence
            ?? (() => NativeMethods.GetClipboardSequenceNumber());
    }

    public Task<ClipboardImageOcrResult> RunFromHotkeyAsync(
        CancellationToken cancellationToken = default) =>
        ProcessAsync(requireEnabled: false, userInitiated: true, cancellationToken);

    public Task<ClipboardImageOcrResult> RunFromClipboardChangeAsync(
        CancellationToken cancellationToken = default) =>
        ProcessAsync(requireEnabled: true, userInitiated: false, cancellationToken);

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        lifetime.Cancel();
        lifetime.Dispose();
        lifetime = null!;
    }

    private async Task<ClipboardImageOcrResult> ProcessAsync(
        bool requireEnabled,
        bool userInitiated,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!dispatcher.CheckAccess())
        {
            return await dispatcher.InvokeAsync(
                    () => ProcessAsync(requireEnabled, userInitiated, cancellationToken),
                    DispatcherPriority.Input)
                .Task
                .Unwrap();
        }

        if (requireEnabled && !isEnabled())
        {
            return new(ClipboardImageOcrStatus.Disabled);
        }

        if (isVoiceWorkflowActive())
        {
            if (userInitiated)
            {
                reportFailure("screenshot.capture.busy", null);
            }
            return new(ClipboardImageOcrStatus.Busy);
        }

        lock (processGate)
        {
            if (isProcessing)
            {
                if (userInitiated)
                {
                    reportFailure("screenshot.capture.busy", null);
                }
                return new(ClipboardImageOcrStatus.Busy);
            }
            isProcessing = true;
        }

        var lease = workflows.TryAcquire(InteractiveWorkflowKind.Screenshot);
        if (lease is null)
        {
            lock (processGate)
            {
                isProcessing = false;
            }
            if (userInitiated)
            {
                reportFailure("screenshot.capture.busy", null);
            }
            return new(ClipboardImageOcrStatus.Busy);
        }

        var runId = runs.Begin();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            lifetime.Token,
            lease.CancellationToken);
        try
        {
            var sequence = readClipboardSequence();
            if (!userInitiated
                && sequence != 0
                && sequence == lastProcessedSequence)
            {
                _ = workflows.Complete(lease);
                runs.Invalidate(runId);
                return new(ClipboardImageOcrStatus.NoImage);
            }

            if (!readClipboardPng(out var pngBytes, out var width, out var height)
                || pngBytes.Length == 0
                || width <= 0
                || height <= 0)
            {
                _ = workflows.Complete(lease);
                runs.Invalidate(runId);
                if (userInitiated)
                {
                    reportFailure("clipboard.ocr.no_image", null);
                }
                return new(ClipboardImageOcrStatus.NoImage);
            }

            if (sequence != 0)
            {
                lastProcessedSequence = sequence;
            }

            linked.Token.ThrowIfCancellationRequested();
            var thumbnailPng = EncodeThumbnail(pngBytes);
            var screenshotId = Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture);
            var completed = await completion.CompleteAsync(
                new ScreenshotCompletionRequest(
                    runId,
                    screenshotId,
                    new ScreenshotAssetWriteRequest(
                        screenshotId,
                        pngBytes,
                        pngBytes,
                        thumbnailPng),
                    width,
                    height,
                    DateTimeOffset.UtcNow,
                    CultureInfo.CurrentUICulture.Name,
                    sourceDisplayId: null,
                    sourceWindowTitle: "Clipboard"),
                linked.Token);

            if (!runs.IsCurrent(runId) || !workflows.IsCurrent(lease))
            {
                runs.Invalidate(runId);
                _ = workflows.Cancel(lease);
                return new(ClipboardImageOcrStatus.Cancelled);
            }

            if (completed.Status != ScreenshotCompletionStatus.Succeeded)
            {
                runs.Invalidate(runId);
                _ = workflows.Complete(lease);
                if (userInitiated)
                {
                    reportFailure(
                        completed.SafeErrorCode ?? "screenshot.capture.failed",
                        null);
                }
                return new(
                    ClipboardImageOcrStatus.Failed,
                    completed,
                    completed.SafeErrorCode);
            }

            var hasText = completed.OcrOutcome is
                { Status: ScreenshotOcrOutcomeStatus.Succeeded, Text: { Length: > 0 } };
            if (!hasText
                && string.IsNullOrWhiteSpace(completed.Record?.OcrText))
            {
                _ = runs.PublishResult(completed.RunId);
                _ = resultPresenter.Present(
                    ScreenshotCompletionKind.TextRecognition,
                    completed);
                completionPublished?.Invoke(completed);
                _ = workflows.Complete(lease);
                if (userInitiated)
                {
                    reportFailure("clipboard.ocr.no_text", null);
                }
                return new(ClipboardImageOcrStatus.NoText, completed);
            }

            _ = runs.PublishResult(completed.RunId);
            _ = resultPresenter.Present(
                ScreenshotCompletionKind.TextRecognition,
                completed);
            completionPublished?.Invoke(completed);
            _ = workflows.Complete(lease);
            return new(ClipboardImageOcrStatus.Succeeded, completed);
        }
        catch (OperationCanceledException) when (linked.IsCancellationRequested)
        {
            runs.Invalidate(runId);
            _ = workflows.Cancel(lease);
            return new(ClipboardImageOcrStatus.Cancelled);
        }
        catch (Exception exception)
        {
            runs.Invalidate(runId);
            _ = workflows.Cancel(lease);
            if (userInitiated)
            {
                reportFailure("screenshot.capture.failed", exception);
            }
            return new(
                ClipboardImageOcrStatus.Failed,
                SafeErrorCode: "screenshot.capture.failed");
        }
        finally
        {
            lock (processGate)
            {
                isProcessing = false;
            }
        }
    }

    private byte[] EncodeThumbnail(ReadOnlyMemory<byte> pngBytes)
    {
        using var stream = new MemoryStream(pngBytes.ToArray(), writable: false);
        var decoder = BitmapDecoder.Create(
            stream,
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad);
        var frame = decoder.Frames[0];
        frame.Freeze();
        return thumbnails.Encode(frame);
    }

    private static bool TryReadClipboardPng(
        out byte[] pngBytes,
        out int width,
        out int height)
    {
        pngBytes = [];
        width = 0;
        height = 0;
        try
        {
            if (System.Windows.Clipboard.ContainsData("PNG"))
            {
                if (System.Windows.Clipboard.GetData("PNG") is Stream pngStream)
                {
                    using var copy = new MemoryStream();
                    pngStream.CopyTo(copy);
                    if (copy.Length > 0
                        && TryDecodePng(copy.ToArray(), out width, out height))
                    {
                        pngBytes = copy.ToArray();
                        return true;
                    }
                }
            }

            if (!System.Windows.Clipboard.ContainsImage())
            {
                return false;
            }

            var image = System.Windows.Clipboard.GetImage();
            if (image is null || image.PixelWidth <= 0 || image.PixelHeight <= 0)
            {
                return false;
            }

            width = image.PixelWidth;
            height = image.PixelHeight;
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var output = new MemoryStream();
            encoder.Save(output);
            pngBytes = output.ToArray();
            return pngBytes.Length > 0;
        }
        catch
        {
            pngBytes = [];
            width = 0;
            height = 0;
            return false;
        }
    }

    private static bool TryDecodePng(byte[] bytes, out int width, out int height)
    {
        width = 0;
        height = 0;
        try
        {
            using var stream = new MemoryStream(bytes, writable: false);
            var decoder = BitmapDecoder.Create(
                stream,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad);
            var frame = decoder.Frames[0];
            width = frame.PixelWidth;
            height = frame.PixelHeight;
            return width > 0 && height > 0;
        }
        catch
        {
            return false;
        }
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern uint GetClipboardSequenceNumber();
    }
}
