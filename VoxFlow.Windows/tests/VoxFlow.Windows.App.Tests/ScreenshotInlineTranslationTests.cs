using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotInlineTranslationTests
{
    [Fact]
    public async Task Service_translates_each_ocr_line_reports_progress_and_deletes_temporary_png()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var runId = Guid.NewGuid();
            var validity = new MutableRunValidity(runId);
            var ocr = new FakeOcrEngine(new ScreenshotOcrEngineResult(
                ScreenshotOcrEngineStatus.Succeeded,
                "hello\nworld",
                [
                    new ScreenshotOcrLine(
                        "hello",
                        98,
                        new ScreenshotPixelBounds(1, 1, 12, 7)),
                    new ScreenshotOcrLine(
                        "world",
                        96,
                        new ScreenshotPixelBounds(1, 10, 12, 7)),
                ]));
            var progress = new CapturingProgress();
            ScreenshotInlineTranslationResult? result = null;

            await StaWpfTestHost.RunAsync(async _ =>
            {
                var service = new ScreenshotInlineTranslationService(
                    ocr,
                    new FakeTransforms(),
                    validity,
                    new ScreenshotSourceRenderer(),
                    root);
                result = await service.TranslateAsync(
                    runId,
                    "shot-1",
                    Source(24, 20),
                    "en-US",
                    progress,
                    CancellationToken.None);
            });

            Assert.NotNull(result);
            Assert.Equal(ScreenshotInlineTranslationStatus.Succeeded, result.Status);
            Assert.Equal(["zh:hello", "zh:world"], result.Lines.Select(line => line.TranslatedText));
            Assert.Equal(2, progress.Values[^1].Completed);
            Assert.Equal(2, progress.Values[^1].Total);
            Assert.Equal(2, progress.Values[^1].Lines.Count);
            Assert.True(ocr.ImageExistedDuringRecognition);
            Assert.Empty(Directory.GetFiles(root));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task Service_returns_partial_stale_and_cancelled_without_leaking_temporary_pixels()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var runId = Guid.NewGuid();
            var validity = new MutableRunValidity(runId);
            var ocrResult = new ScreenshotOcrEngineResult(
                ScreenshotOcrEngineStatus.Succeeded,
                "first\nsecond",
                [
                    new ScreenshotOcrLine("first", 90, new ScreenshotPixelBounds(0, 0, 8, 6)),
                    new ScreenshotOcrLine("second", 90, new ScreenshotPixelBounds(0, 7, 8, 6)),
                ]);
            ScreenshotInlineTranslationResult? partial = null;
            await StaWpfTestHost.RunAsync(async _ =>
            {
                var service = new ScreenshotInlineTranslationService(
                    new FakeOcrEngine(ocrResult),
                    new FakeTransforms(failedSource: "second"),
                    validity,
                    new ScreenshotSourceRenderer(),
                    root);
                partial = await service.TranslateAsync(
                    runId,
                    "shot-partial",
                    Source(16, 14),
                    null,
                    progress: null,
                    CancellationToken.None);
            });
            Assert.Equal(ScreenshotInlineTranslationStatus.PartiallyCompleted, partial!.Status);
            Assert.Single(partial.Lines);

            validity.CurrentRunId = Guid.NewGuid();
            var staleService = new ScreenshotInlineTranslationService(
                new FakeOcrEngine(ocrResult),
                new FakeTransforms(),
                validity,
                new ScreenshotSourceRenderer(),
                root);
            var stale = await staleService.TranslateAsync(
                runId,
                "shot-stale",
                Source(16, 14),
                null,
                progress: null,
                CancellationToken.None);
            Assert.Equal(ScreenshotInlineTranslationStatus.Stale, stale.Status);

            validity.CurrentRunId = runId;
            using var cancellation = new CancellationTokenSource();
            cancellation.Cancel();
            ScreenshotInlineTranslationResult? cancelled = null;
            await StaWpfTestHost.RunAsync(async _ =>
            {
                var service = new ScreenshotInlineTranslationService(
                    new FakeOcrEngine(ocrResult),
                    new FakeTransforms(),
                    validity,
                    new ScreenshotSourceRenderer(),
                    root);
                cancelled = await service.TranslateAsync(
                    runId,
                    "shot-cancelled",
                    Source(16, 14),
                    null,
                    progress: null,
                    cancellation.Token);
            });
            Assert.Equal(ScreenshotInlineTranslationStatus.Cancelled, cancelled!.Status);
            Assert.Empty(Directory.GetFiles(root));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task Renderer_uses_opaque_white_line_boxes_and_thumbnail_is_exact_png_size()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(40, 24, blue: 180, green: 30, red: 20);
            var translated = ScreenshotInlineTranslationRenderer.Apply(
                source,
                [
                    new ScreenshotInlineTranslationLine(
                        new ScreenshotPixelBounds(6, 5, 24, 12),
                        "source",
                        "译文"),
                ]);

            Assert.Equal(new Pixel(180, 30, 20, 255), PixelAt(translated, 1, 1));
            Assert.Equal(new Pixel(255, 255, 255, 255), PixelAt(translated, 6, 5));

            var bitmap = BitmapSource.Create(
                translated.Width,
                translated.Height,
                96,
                96,
                PixelFormats.Bgra32,
                palette: null,
                translated.Bgra.ToArray(),
                translated.Stride);
            bitmap.Freeze();
            var png = new ScreenshotThumbnailEncoder().Encode(bitmap);
            using var stream = new MemoryStream(png, writable: false);
            var frame = new PngBitmapDecoder(
                stream,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad).Frames[0];
            Assert.Equal(ScreenshotThumbnailEncoder.Width, frame.PixelWidth);
            Assert.Equal(ScreenshotThumbnailEncoder.Height, frame.PixelHeight);
            return Task.CompletedTask;
        });
    }

    private static FrozenScreenshot Source(
        int width,
        int height,
        byte blue = 80,
        byte green = 90,
        byte red = 100)
    {
        var stride = checked(width * 4);
        var pixels = new byte[checked(stride * height)];
        for (var index = 0; index < pixels.Length; index += 4)
        {
            pixels[index] = blue;
            pixels[index + 1] = green;
            pixels[index + 2] = red;
            pixels[index + 3] = byte.MaxValue;
        }
        return new FrozenScreenshot(width, height, stride, pixels);
    }

    private static Pixel PixelAt(FrozenScreenshot source, int x, int y)
    {
        var offset = checked((y * source.Stride) + (x * 4));
        var pixels = source.Bgra.Span;
        return new Pixel(
            pixels[offset],
            pixels[offset + 1],
            pixels[offset + 2],
            pixels[offset + 3]);
    }

    private static string CreateTemporaryDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"voxflow-inline-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private sealed class FakeOcrEngine(ScreenshotOcrEngineResult result) : IScreenshotOcrEngine
    {
        public bool ImageExistedDuringRecognition { get; private set; }

        public Task<ScreenshotOcrEngineResult> RecognizeAsync(
            ScreenshotOcrEngineRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ImageExistedDuringRecognition = File.Exists(request.ImagePath);
            return Task.FromResult(result);
        }
    }

    private sealed class FakeTransforms(string? failedSource = null)
        : IScreenshotTransformStreamingService
    {
        public async IAsyncEnumerable<ScreenshotTransformEvent> TransformAsync(
            ScreenshotTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Yield();
            if (request.SourceText == failedSource)
            {
                yield break;
            }
            yield return new ScreenshotTransformCompleted(
                request.RunId,
                request.ScreenshotId,
                request.Operation,
                $"zh:{request.SourceText}",
                fromCache: false);
        }
    }

    private sealed class MutableRunValidity(Guid runId) : IScreenshotRunValidity
    {
        public Guid CurrentRunId { get; set; } = runId;

        public bool IsCurrent(Guid candidate) => candidate == CurrentRunId;
    }

    private sealed class CapturingProgress : IProgress<ScreenshotInlineTranslationProgress>
    {
        public List<ScreenshotInlineTranslationProgress> Values { get; } = [];

        public void Report(ScreenshotInlineTranslationProgress value) => Values.Add(value);
    }

    private readonly record struct Pixel(byte Blue, byte Green, byte Red, byte Alpha);
}
