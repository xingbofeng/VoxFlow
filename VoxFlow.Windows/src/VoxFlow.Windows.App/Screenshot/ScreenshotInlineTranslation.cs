using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using Color = System.Windows.Media.Color;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using Point = System.Windows.Point;
using Rect = System.Windows.Rect;

namespace VoxFlow.Windows.App.Screenshot;

public sealed record ScreenshotInlineTranslationLine(
    ScreenshotPixelBounds Bounds,
    string SourceText,
    string TranslatedText);

public enum ScreenshotInlineTranslationStatus
{
    Succeeded,
    PartiallyCompleted,
    OcrUnavailable,
    Empty,
    ProviderUnavailable,
    Failed,
    Cancelled,
    Stale,
}

public sealed record ScreenshotInlineTranslationResult(
    ScreenshotInlineTranslationStatus Status,
    IReadOnlyList<ScreenshotInlineTranslationLine> Lines);

public sealed record ScreenshotInlineTranslationProgress(
    IReadOnlyList<ScreenshotInlineTranslationLine> Lines,
    int Completed,
    int Total);

public interface IScreenshotInlineTranslationService
{
    Task<ScreenshotInlineTranslationResult> TranslateAsync(
        Guid runId,
        string screenshotId,
        FrozenScreenshot source,
        string? currentLanguage,
        IProgress<ScreenshotInlineTranslationProgress>? progress,
        CancellationToken cancellationToken);
}

/// <summary>
/// Performs local line-bbox OCR first, then explicitly invokes the configured
/// LLM provider for each line. Temporary pixels never leave the managed temp
/// directory and are deleted on every terminal path.
/// </summary>
public sealed class ScreenshotInlineTranslationService : IScreenshotInlineTranslationService
{
    private static readonly TimeSpan PublishInterval = TimeSpan.FromMilliseconds(250);
    private const int MaximumParallelLines = 3;

    private readonly IScreenshotOcrEngine ocr;
    private readonly IScreenshotTransformStreamingService? transforms;
    private readonly IScreenshotRunValidity runValidity;
    private readonly ScreenshotSourceRenderer renderer;
    private readonly string temporaryRoot;

    public ScreenshotInlineTranslationService(
        IScreenshotOcrEngine ocr,
        IScreenshotTransformStreamingService? transforms,
        IScreenshotRunValidity runValidity,
        ScreenshotSourceRenderer renderer,
        string temporaryRoot)
    {
        this.ocr = ocr ?? throw new ArgumentNullException(nameof(ocr));
        this.transforms = transforms;
        this.runValidity = runValidity ?? throw new ArgumentNullException(nameof(runValidity));
        this.renderer = renderer ?? throw new ArgumentNullException(nameof(renderer));
        ArgumentException.ThrowIfNullOrWhiteSpace(temporaryRoot);
        this.temporaryRoot = Path.GetFullPath(temporaryRoot);
    }

    public async Task<ScreenshotInlineTranslationResult> TranslateAsync(
        Guid runId,
        string screenshotId,
        FrozenScreenshot source,
        string? currentLanguage,
        IProgress<ScreenshotInlineTranslationProgress>? progress,
        CancellationToken cancellationToken)
    {
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A screenshot run identifier is required.", nameof(runId));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(screenshotId);
        ArgumentNullException.ThrowIfNull(source);
        if (!runValidity.IsCurrent(runId))
        {
            return Result(ScreenshotInlineTranslationStatus.Stale);
        }
        if (transforms is null)
        {
            return Result(ScreenshotInlineTranslationStatus.ProviderUnavailable);
        }

        Directory.CreateDirectory(temporaryRoot);
        var temporaryPath = Path.Combine(
            temporaryRoot,
            $"inline-{runId:N}-{Guid.NewGuid():N}.png");
        try
        {
            var empty = new ScreenshotDocument(
                Guid.NewGuid(),
                new PixelSize(source.Width, source.Height),
                [],
                revision: 0);
            var png = renderer.RenderPng(source, empty);
            await File.WriteAllBytesAsync(temporaryPath, png, cancellationToken)
                .ConfigureAwait(false);
            var ocrResult = await ocr.RecognizeAsync(
                new ScreenshotOcrEngineRequest(temporaryPath, currentLanguage),
                cancellationToken).ConfigureAwait(false);
            if (!runValidity.IsCurrent(runId))
            {
                return Result(ScreenshotInlineTranslationStatus.Stale);
            }
            if (ocrResult.Status == ScreenshotOcrEngineStatus.Empty)
            {
                return Result(ScreenshotInlineTranslationStatus.Empty);
            }
            if (ocrResult.Status != ScreenshotOcrEngineStatus.Succeeded)
            {
                return Result(ScreenshotInlineTranslationStatus.OcrUnavailable);
            }

            var results = new ScreenshotInlineTranslationLine?[ocrResult.Lines.Count];
            var translatedCount = 0;
            var publishGate = new object();
            var stopwatch = Stopwatch.StartNew();
            var lastPublish = TimeSpan.Zero;
            using var concurrency = new SemaphoreSlim(MaximumParallelLines, MaximumParallelLines);
            var tasks = ocrResult.Lines.Select((line, index) => TranslateLineAsync(
                line,
                index,
                runId,
                screenshotId,
                results,
                concurrency,
                () => Interlocked.Increment(ref translatedCount),
                () => PublishIfDue(force: false),
                cancellationToken)).ToArray();
            await Task.WhenAll(tasks).ConfigureAwait(false);
            PublishIfDue(force: true);
            if (!runValidity.IsCurrent(runId))
            {
                return Result(ScreenshotInlineTranslationStatus.Stale);
            }
            var completed = results.Where(line => line is not null).Cast<ScreenshotInlineTranslationLine>().ToArray();
            if (translatedCount == 0)
            {
                return Result(ScreenshotInlineTranslationStatus.Failed);
            }
            return new ScreenshotInlineTranslationResult(
                translatedCount == ocrResult.Lines.Count
                    ? ScreenshotInlineTranslationStatus.Succeeded
                    : ScreenshotInlineTranslationStatus.PartiallyCompleted,
                completed);

            void PublishIfDue(bool force)
            {
                if (progress is null)
                {
                    return;
                }
                lock (publishGate)
                {
                    if (!force && stopwatch.Elapsed - lastPublish < PublishInterval)
                    {
                        return;
                    }
                    lastPublish = stopwatch.Elapsed;
                    progress.Report(new ScreenshotInlineTranslationProgress(
                        results
                            .Where(line => line is not null)
                            .Cast<ScreenshotInlineTranslationLine>()
                            .ToArray(),
                        translatedCount,
                        results.Length));
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return Result(ScreenshotInlineTranslationStatus.Cancelled);
        }
        catch
        {
            return runValidity.IsCurrent(runId)
                ? Result(ScreenshotInlineTranslationStatus.Failed)
                : Result(ScreenshotInlineTranslationStatus.Stale);
        }
        finally
        {
            TryDelete(temporaryPath);
        }
    }

    private async Task TranslateLineAsync(
        ScreenshotOcrLine line,
        int index,
        Guid runId,
        string screenshotId,
        ScreenshotInlineTranslationLine?[] results,
        SemaphoreSlim concurrency,
        Action translated,
        Action publish,
        CancellationToken cancellationToken)
    {
        await concurrency.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            string? finalText = null;
            var request = new ScreenshotTransformRequest(
                runId,
                screenshotId,
                line.Text,
                ScreenshotTransformOperation.Translation,
                inputRevision: FormattableString.Invariant(
                    $"line:{line.Bounds.X},{line.Bounds.Y},{line.Bounds.Width},{line.Bounds.Height}"));
            await foreach (var update in transforms!.TransformAsync(request, cancellationToken)
                .ConfigureAwait(false))
            {
                if (!runValidity.IsCurrent(runId))
                {
                    return;
                }
                if (update is ScreenshotTransformCompleted completed)
                {
                    finalText = completed.Text;
                }
            }
            if (!string.IsNullOrWhiteSpace(finalText))
            {
                results[index] = new ScreenshotInlineTranslationLine(
                    line.Bounds,
                    line.Text,
                    finalText);
                translated();
                publish();
            }
        }
        finally
        {
            concurrency.Release();
        }
    }

    private static ScreenshotInlineTranslationResult Result(
        ScreenshotInlineTranslationStatus status) => new(status, []);

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Startup temp cleanup removes any file still held by an external OCR process.
        }
    }
}

public static class ScreenshotInlineTranslationRenderer
{
    private const double MinimumFontSize = 8;

    public static FrozenScreenshot Apply(
        FrozenScreenshot source,
        IReadOnlyList<ScreenshotInlineTranslationLine> lines)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(lines);
        if (lines.Count == 0)
        {
            return source;
        }

        var bitmap = BitmapSource.Create(
            source.Width,
            source.Height,
            96,
            96,
            PixelFormats.Bgra32,
            palette: null,
            source.Bgra.ToArray(),
            source.Stride);
        bitmap.Freeze();
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawImage(bitmap, new Rect(0, 0, source.Width, source.Height));
            Draw(drawing, lines, static bounds => new Rect(
                bounds.X,
                bounds.Y,
                bounds.Width,
                bounds.Height),
                pixelsPerDip: 1);
        }
        var rendered = new RenderTargetBitmap(
            source.Width,
            source.Height,
            96,
            96,
            PixelFormats.Pbgra32);
        rendered.Render(visual);
        rendered.Freeze();
        var stride = checked(source.Width * 4);
        var pixels = new byte[checked(stride * source.Height)];
        rendered.CopyPixels(pixels, stride, 0);
        return new FrozenScreenshot(source.Width, source.Height, stride, pixels);
    }

    internal static void Draw(
        DrawingContext drawing,
        IReadOnlyList<ScreenshotInlineTranslationLine> lines,
        Func<ScreenshotPixelBounds, Rect> map,
        double pixelsPerDip)
    {
        ArgumentNullException.ThrowIfNull(drawing);
        ArgumentNullException.ThrowIfNull(lines);
        ArgumentNullException.ThrowIfNull(map);
        foreach (var line in lines)
        {
            var target = map(line.Bounds);
            if (target.Width <= 0 || target.Height <= 0)
            {
                continue;
            }
            drawing.DrawRectangle(
                System.Windows.Media.Brushes.White,
                null,
                target);
            var formatted = FitText(line.TranslatedText, target, pixelsPerDip);
            drawing.PushClip(new RectangleGeometry(target));
            drawing.DrawText(
                formatted,
                new Point(
                    target.Left + 2,
                    target.Top + Math.Max(0, (target.Height - formatted.Height) / 2)));
            drawing.Pop();
        }
    }

    private static FormattedText FitText(string text, Rect target, double pixelsPerDip)
    {
        var maximum = Math.Max(MinimumFontSize, Math.Min(target.Height * 0.82, 32));
        for (var size = maximum; size > MinimumFontSize; size -= 1)
        {
            var candidate = CreateText(text, size, target, pixelsPerDip);
            if (candidate.Height <= target.Height - 2)
            {
                return candidate;
            }
        }
        return CreateText(text, MinimumFontSize, target, pixelsPerDip);
    }

    private static FormattedText CreateText(
        string text,
        double size,
        Rect target,
        double pixelsPerDip)
    {
        var formatted = new FormattedText(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal),
            size,
            System.Windows.Media.Brushes.Black,
            pixelsPerDip)
        {
            MaxTextWidth = Math.Max(1, target.Width - 4),
            MaxTextHeight = Math.Max(1, target.Height - 2),
            Trimming = TextTrimming.CharacterEllipsis,
            TextAlignment = TextAlignment.Center,
        };
        return formatted;
    }
}
