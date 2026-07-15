using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using Rect = System.Windows.Rect;

namespace VoxFlow.Windows.App.Screenshot;

/// <summary>
/// A source-resolution screenshot render that is safe to pass across WPF dispatcher threads.
/// </summary>
public sealed class ScreenshotRenderResult
{
    private readonly byte[] pngBytes;

    internal ScreenshotRenderResult(BitmapSource bitmap, byte[] pngBytes)
    {
        Bitmap = bitmap ?? throw new ArgumentNullException(nameof(bitmap));
        if (!bitmap.IsFrozen)
        {
            throw new ArgumentException("The rendered bitmap must be frozen.", nameof(bitmap));
        }
        this.pngBytes = pngBytes?.ToArray() ?? throw new ArgumentNullException(nameof(pngBytes));
    }

    public BitmapSource Bitmap { get; }

    public ReadOnlyMemory<byte> PngBytes => pngBytes;

    public byte[] CopyPngBytes() => pngBytes.ToArray();
}

/// <summary>
/// Composites a frozen DX11 crop and its annotation document without applying display DPI scaling.
/// </summary>
public sealed class ScreenshotSourceRenderer
{
    private const double SourceDpi = 96;

    public ScreenshotRenderResult Render(
        FrozenScreenshot source,
        ScreenshotDocument document)
    {
        var bitmap = Composite(source, document);
        return new ScreenshotRenderResult(bitmap, EncodePng(bitmap));
    }

    public BitmapSource RenderBitmap(
        FrozenScreenshot source,
        ScreenshotDocument document) => Composite(source, document);

    public byte[] RenderPng(
        FrozenScreenshot source,
        ScreenshotDocument document) => EncodePng(Composite(source, document));

    private static BitmapSource Composite(
        FrozenScreenshot source,
        ScreenshotDocument document)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(document);
        if (document.CanvasSize.Width != source.Width
            || document.CanvasSize.Height != source.Height)
        {
            throw new ArgumentException(
                "The annotation canvas must match the source screenshot dimensions.",
                nameof(document));
        }

        var sourceBitmap = BitmapSource.Create(
            source.Width,
            source.Height,
            SourceDpi,
            SourceDpi,
            PixelFormats.Bgra32,
            palette: null,
            source.Bgra.ToArray(),
            source.Stride);
        RenderOptions.SetBitmapScalingMode(sourceBitmap, BitmapScalingMode.NearestNeighbor);
        sourceBitmap.Freeze();

        var bounds = new Rect(0, 0, source.Width, source.Height);
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.NearestNeighbor);
        using (var drawing = visual.RenderOpen())
        {
            drawing.PushClip(new RectangleGeometry(bounds));
            drawing.DrawImage(sourceBitmap, bounds);
            ScreenshotAnnotationCompositor.Draw(drawing, source, document.Annotations, bounds);
            drawing.Pop();
        }

        var bitmap = new RenderTargetBitmap(
            source.Width,
            source.Height,
            SourceDpi,
            SourceDpi,
            PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    private static byte[] EncodePng(BitmapSource bitmap)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }
}
