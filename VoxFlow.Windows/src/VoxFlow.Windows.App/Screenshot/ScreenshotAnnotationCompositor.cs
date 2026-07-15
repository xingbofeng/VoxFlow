using System.Windows.Media;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using Rect = System.Windows.Rect;

namespace VoxFlow.Windows.App.Screenshot;

internal static class ScreenshotAnnotationCompositor
{
    public static void Draw(
        DrawingContext drawing,
        FrozenScreenshot source,
        IReadOnlyList<ScreenshotAnnotation> annotations,
        Rect canvasBounds)
    {
        ArgumentNullException.ThrowIfNull(drawing);
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(annotations);

        var mosaicPatterns = new ScreenshotMosaicPatternCache();
        foreach (var annotation in annotations)
        {
            if (annotation is not MosaicAnnotation mosaic)
            {
                ScreenshotVectorAnnotationCompositor.Draw(drawing, annotation);
                continue;
            }

            var blockSize = ScreenshotMosaicCompositor.NormalizeBlockSize(source, mosaic.BlockSize);
            var pattern = mosaicPatterns.GetOrCreate(
                source,
                blockSize,
                checked((int)Math.Floor(mosaic.Bounds.Left)),
                checked((int)Math.Floor(mosaic.Bounds.Top)));
            ScreenshotMosaicCompositor.Draw(
                drawing,
                pattern.Bitmap,
                mosaic,
                PatternCanvasBounds(pattern, source, canvasBounds));
        }
    }

    private static Rect PatternCanvasBounds(
        ScreenshotMosaicPattern pattern,
        FrozenScreenshot source,
        Rect canvasBounds) => new(
            canvasBounds.Left + (pattern.CanvasBounds.Left * canvasBounds.Width / source.Width),
            canvasBounds.Top + (pattern.CanvasBounds.Top * canvasBounds.Height / source.Height),
            pattern.CanvasBounds.Width * canvasBounds.Width / source.Width,
            pattern.CanvasBounds.Height * canvasBounds.Height / source.Height);
}
