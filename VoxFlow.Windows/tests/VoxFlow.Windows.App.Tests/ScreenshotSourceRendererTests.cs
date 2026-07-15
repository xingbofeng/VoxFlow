using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotSourceRendererTests
{
    [Fact]
    public async Task Render_returns_source_resolution_frozen_bitmap_and_valid_png()
    {
        ScreenshotRenderResult? result = null;
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(7, 5, static (x, y) =>
                new Pixel((byte)(x * 9), (byte)(y * 11), (byte)(40 + x + y), 255));
            var document = Document(source);

            result = new ScreenshotSourceRenderer().Render(source, document);

            Assert.Equal(7, result.Bitmap.PixelWidth);
            Assert.Equal(5, result.Bitmap.PixelHeight);
            Assert.True(result.Bitmap.IsFrozen);
            Assert.Equal(
                new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 },
                result.PngBytes.Span[..8].ToArray());
            return Task.CompletedTask;
        });

        Assert.NotNull(result);
        var pixels = Pixels(result.Bitmap);
        Assert.Equal(new Pixel(54, 44, 50, 255), PixelAt(pixels, 7, 6, 4));

        using var stream = new MemoryStream(result.PngBytes.ToArray(), writable: false);
        var decoded = new PngBitmapDecoder(
            stream,
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad).Frames[0];
        Assert.Equal(7, decoded.PixelWidth);
        Assert.Equal(5, decoded.PixelHeight);
    }

    [Fact]
    public async Task Render_rejects_a_document_whose_source_canvas_does_not_match()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(8, 6, static (_, _) => new Pixel(0, 0, 0, 255));
            var document = new ScreenshotDocument(
                Guid.NewGuid(),
                new PixelSize(7, 6),
                [],
                revision: 0);

            Assert.Throws<ArgumentException>(() =>
                new ScreenshotSourceRenderer().Render(source, document));
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task One_renderer_can_render_concurrently_on_independent_wpf_threads()
    {
        var renderer = new ScreenshotSourceRenderer();
        var first = RenderOnSta(renderer, new Pixel(10, 20, 30, 255));
        var second = RenderOnSta(renderer, new Pixel(40, 50, 60, 255));

        var results = await Task.WhenAll(first, second);

        Assert.All(results, bitmap => Assert.True(bitmap.IsFrozen));
        Assert.Equal(new Pixel(10, 20, 30, 255), PixelAt(Pixels(results[0]), 12, 4, 4));
        Assert.Equal(new Pixel(40, 50, 60, 255), PixelAt(Pixels(results[1]), 12, 4, 4));
    }

    [Fact]
    public async Task Mosaic_respects_a_padded_dx11_source_stride()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            const int width = 4;
            const int height = 2;
            const int stride = 20;
            var bgra = Enumerable.Repeat(byte.MaxValue, stride * height).ToArray();
            var redValues = new byte[] { 10, 20, 30, 40, 50, 60, 70, 80 };
            for (var index = 0; index < redValues.Length; index++)
            {
                var x = index % width;
                var y = index / width;
                var offset = (y * stride) + (x * 4);
                bgra[offset] = 0;
                bgra[offset + 1] = 0;
                bgra[offset + 2] = redValues[index];
                bgra[offset + 3] = byte.MaxValue;
            }
            var source = new FrozenScreenshot(width, height, stride, bgra);
            var mosaic = new MosaicAnnotation(
                Guid.NewGuid(),
                [new SourcePoint(2, 1)],
                brushSize: 100,
                blockSize: 2);

            var bitmap = new ScreenshotSourceRenderer().RenderBitmap(
                source,
                Document(source, mosaic));
            var pixels = Pixels(bitmap);

            Assert.Equal(new Pixel(0, 0, 10, 255), PixelAt(pixels, width, 0, 0));
            Assert.Equal(new Pixel(0, 0, 10, 255), PixelAt(pixels, width, 1, 1));
            Assert.Equal(new Pixel(0, 0, 30, 255), PixelAt(pixels, width, 2, 0));
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Mosaic_pixelates_only_the_original_pixels_under_its_brush_path()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(32, 16, static (x, y) =>
                new Pixel(
                    (byte)((x * 17 + y * 3) % 256),
                    (byte)((x * 7 + y * 19) % 256),
                    (byte)((x * 29 + y * 5) % 256),
                    255));
            var mosaic = new MosaicAnnotation(
                Guid.NewGuid(),
                [new SourcePoint(8, 8), new SourcePoint(16, 8)],
                brushSize: 6,
                blockSize: 4);
            var rendered = new ScreenshotSourceRenderer().Render(
                source,
                Document(source, mosaic)).Bitmap;
            var actual = Pixels(rendered);
            var original = source.Bgra.ToArray();

            Assert.NotEqual(PixelAt(original, 32, 10, 8), PixelAt(actual, 32, 10, 8));
            Assert.Equal(PixelAt(actual, 32, 10, 8), PixelAt(actual, 32, 11, 8));
            Assert.Equal(PixelAt(original, 32, 24, 8), PixelAt(actual, 32, 24, 8));
            Assert.Equal(PixelAt(original, 32, 2, 1), PixelAt(actual, 32, 2, 1));
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Moving_mosaic_preserves_bounds_anchored_true_pixel_sampling()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(32, 24, static (x, y) =>
                new Pixel((byte)(x * 3), (byte)(y * 5), (byte)(x + y), 255));
            var mosaic = new MosaicAnnotation(
                Guid.NewGuid(),
                [new SourcePoint(10, 10)],
                brushSize: 6,
                blockSize: 4);
            var moved = Assert.IsType<MosaicAnnotation>(
                mosaic.MoveBy(new SourceVector(1, 1)));

            var originalPixels = Pixels(new ScreenshotSourceRenderer().RenderBitmap(
                source,
                Document(source, mosaic)));
            var movedPixels = Pixels(new ScreenshotSourceRenderer().RenderBitmap(
                source,
                Document(source, moved)));

            Assert.Equal(new Pixel(21, 35, 14, 255), PixelAt(originalPixels, 32, 10, 10));
            Assert.Equal(new Pixel(24, 40, 16, 255), PixelAt(movedPixels, 32, 11, 11));
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Mosaic_uses_macOS_document_order_against_vector_annotations()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(36, 18, static (x, y) =>
                ((x / 2) + (y / 2)) % 2 == 0
                    ? new Pixel(0, 0, 230, 255)
                    : new Pixel(0, 230, 0, 255));
            var blue = new AnnotationColor(0, 0, 1);
            var pen = new PenAnnotation(
                Guid.NewGuid(),
                [new SourcePoint(4, 9), new SourcePoint(30, 9)],
                new AnnotationStyle(blue, lineWidth: 5, fillColor: null));
            var mosaic = new MosaicAnnotation(
                Guid.NewGuid(),
                [new SourcePoint(4, 9), new SourcePoint(30, 9)],
                brushSize: 12,
                blockSize: 6);
            var mosaicAbovePen = new ScreenshotSourceRenderer().Render(
                source,
                Document(source, pen, mosaic)).Bitmap;
            var penAboveMosaic = new ScreenshotSourceRenderer().Render(
                source,
                Document(source, mosaic, pen)).Bitmap;

            var mosaicTop = PixelAt(Pixels(mosaicAbovePen), 36, 17, 9);
            var penTop = PixelAt(Pixels(penAboveMosaic), 36, 17, 9);
            Assert.False(
                mosaicTop.Blue > 220 && mosaicTop.Green < 35 && mosaicTop.Red < 35,
                $"Mosaic drawn after the pen must replace it, got {mosaicTop}.");
            Assert.True(penTop.Blue > 220, $"Pen drawn after mosaic must remain visible, got {penTop}.");
            Assert.True(penTop.Green < 35 && penTop.Red < 35, $"Unexpected mosaic bleed at {penTop}.");
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Transparent_source_and_annotation_alpha_are_preserved_with_antialiased_edges()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(24, 24, static (_, _) => new Pixel(0, 0, 0, 0));
            var translucentRed = new AnnotationColor(1, 0, 0, 0.5);
            var translucentFill = new AnnotationColor(1, 0, 0, 0.35);
            var ellipse = new EllipseAnnotation(
                Guid.NewGuid(),
                new SourceRect(3.5, 3.5, 17, 17),
                new AnnotationStyle(translucentRed, 2, translucentFill));
            var bitmap = new ScreenshotSourceRenderer().RenderBitmap(
                source,
                Document(source, ellipse));
            var pixels = Pixels(bitmap);

            Assert.Equal(byte.MinValue, PixelAt(pixels, 24, 0, 0).Alpha);
            var center = PixelAt(pixels, 24, 12, 12);
            Assert.InRange(center.Alpha, (byte)85, (byte)95);
            Assert.True(center.Red > 245 && center.Green < 5 && center.Blue < 5);

            var alphaValues = Enumerable
                .Range(0, 24 * 24)
                .Select(index => pixels[(index * 4) + 3])
                .Distinct()
                .ToArray();
            Assert.Contains(alphaValues, alpha => alpha is > 0 and < 85);
            Assert.Contains(alphaValues, alpha => alpha is >= 120 and <= 135);
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Renderer_draws_all_eight_annotation_kinds()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(128, 64, static (x, y) =>
                new Pixel(
                    (byte)(18 + (x % 13)),
                    (byte)(20 + (y % 11)),
                    (byte)(22 + ((x + y) % 17)),
                    255));
            var red = new AnnotationColor(1, 0.05, 0.05);
            var fill = new AnnotationColor(1, 0.05, 0.05, 0.35);
            var style = new AnnotationStyle(red, lineWidth: 4, fillColor: fill);
            ScreenshotAnnotation[] annotations =
            [
                new PenAnnotation(
                    Guid.NewGuid(),
                    [new SourcePoint(4, 9), new SourcePoint(26, 9)],
                    style),
                new EllipseAnnotation(Guid.NewGuid(), new SourceRect(32, 3, 22, 16), style),
                new RectangleAnnotation(Guid.NewGuid(), new SourceRect(60, 3, 20, 16), style),
                new ArrowAnnotation(
                    Guid.NewGuid(),
                    new SourcePoint(86, 11),
                    new SourcePoint(116, 11),
                    style),
                new DotMarkerAnnotation(Guid.NewGuid(), new SourcePoint(12, 40), 6, style),
                new NumberedMarkerAnnotation(Guid.NewGuid(), new SourcePoint(36, 40), 7, 9, style),
                new TextAnnotation(
                    Guid.NewGuid(),
                    new SourcePoint(54, 30),
                    "Aa",
                    new TextAnnotationStyle(red, fontSize: 16, fontName: "Segoe UI")),
                new MosaicAnnotation(
                    Guid.NewGuid(),
                    [new SourcePoint(92, 38), new SourcePoint(116, 46)],
                    brushSize: 14,
                    blockSize: 5),
            ];

            var bitmap = new ScreenshotSourceRenderer().Render(
                source,
                Document(source, annotations)).Bitmap;
            var actual = Pixels(bitmap);
            var original = source.Bgra.ToArray();

            AssertRegionChanged(original, actual, 128, new IntRect(2, 3, 28, 14), "pen");
            AssertRegionChanged(original, actual, 128, new IntRect(30, 1, 26, 20), "ellipse");
            AssertRegionChanged(original, actual, 128, new IntRect(58, 1, 24, 20), "rectangle");
            AssertRegionChanged(original, actual, 128, new IntRect(84, 2, 36, 18), "arrow");
            AssertRegionChanged(original, actual, 128, new IntRect(5, 33, 14, 14), "dot marker");
            AssertRegionChanged(original, actual, 128, new IntRect(26, 30, 20, 20), "numbered marker");
            AssertRegionChanged(original, actual, 128, new IntRect(52, 28, 34, 24), "text");
            AssertRegionChanged(original, actual, 128, new IntRect(84, 30, 40, 26), "mosaic");
            return Task.CompletedTask;
        });
    }

    private static FrozenScreenshot Source(
        int width,
        int height,
        Func<int, int, Pixel> pixel)
    {
        var stride = checked(width * 4);
        var bgra = new byte[checked(stride * height)];
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var value = pixel(x, y);
                var offset = (y * stride) + (x * 4);
                bgra[offset] = value.Blue;
                bgra[offset + 1] = value.Green;
                bgra[offset + 2] = value.Red;
                bgra[offset + 3] = value.Alpha;
            }
        }
        return new FrozenScreenshot(width, height, stride, bgra);
    }

    private static async Task<BitmapSource> RenderOnSta(
        ScreenshotSourceRenderer renderer,
        Pixel pixel)
    {
        BitmapSource? bitmap = null;
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(12, 9, (_, _) => pixel);
            bitmap = renderer.RenderBitmap(source, Document(source));
            return Task.CompletedTask;
        });
        return bitmap ?? throw new InvalidOperationException("The STA render did not produce a bitmap.");
    }

    private static ScreenshotDocument Document(
        FrozenScreenshot source,
        params ScreenshotAnnotation[] annotations) => new(
            Guid.NewGuid(),
            new PixelSize(source.Width, source.Height),
            annotations,
            revision: 0);

    private static byte[] Pixels(BitmapSource bitmap)
    {
        var converted = new FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0);
        converted.Freeze();
        var stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);
        return pixels;
    }

    private static Pixel PixelAt(byte[] pixels, int width, int x, int y)
    {
        var offset = ((y * width) + x) * 4;
        return new Pixel(
            pixels[offset],
            pixels[offset + 1],
            pixels[offset + 2],
            pixels[offset + 3]);
    }

    private static void AssertRegionChanged(
        byte[] original,
        byte[] actual,
        int width,
        IntRect region,
        string annotation)
    {
        var changed = 0;
        for (var y = region.Top; y < region.Bottom; y++)
        {
            for (var x = region.Left; x < region.Right; x++)
            {
                if (PixelAt(original, width, x, y) != PixelAt(actual, width, x, y))
                {
                    changed++;
                }
            }
        }
        Assert.True(changed >= 4, $"The {annotation} annotation did not render enough visible pixels ({changed}).");
    }

    private readonly record struct Pixel(byte Blue, byte Green, byte Red, byte Alpha);

    private readonly record struct IntRect(int Left, int Top, int Width, int Height)
    {
        public int Right => Left + Width;
        public int Bottom => Top + Height;
    }
}
