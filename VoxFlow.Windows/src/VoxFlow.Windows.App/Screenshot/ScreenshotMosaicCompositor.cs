using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using Brushes = System.Windows.Media.Brushes;
using MediaPen = System.Windows.Media.Pen;
using Rect = System.Windows.Rect;

namespace VoxFlow.Windows.App.Screenshot;

internal static class ScreenshotMosaicCompositor
{
    public static int NormalizeBlockSize(
        FrozenScreenshot source,
        double requestedBlockSize)
    {
        var maximum = Math.Max(source.Width, source.Height);
        return checked((int)Math.Round(
            Math.Clamp(requestedBlockSize, 1, maximum),
            MidpointRounding.AwayFromZero));
    }

    public static ScreenshotMosaicPattern CreatePattern(
        FrozenScreenshot source,
        int blockSize,
        int anchorX,
        int anchorY)
    {
        ArgumentNullException.ThrowIfNull(source);
        blockSize = NormalizeBlockSize(source, blockSize);
        var startX = NormalizeGridStart(anchorX, source.Width, blockSize);
        var startY = NormalizeGridStart(anchorY, source.Height, blockSize);
        var patternWidth = checked(((source.Width - 1 - startX) / blockSize) + 1);
        var patternHeight = checked(((source.Height - 1 - startY) / blockSize) + 1);
        var stride = checked(patternWidth * 4);
        var output = new byte[checked(stride * patternHeight)];
        var input = source.Bgra.Span;

        for (var patternY = 0; patternY < patternHeight; patternY++)
        {
            var sourceY = checked(startY + (patternY * blockSize));
            for (var patternX = 0; patternX < patternWidth; patternX++)
            {
                var sourceX = checked(startX + (patternX * blockSize));
                var sample = Sample(input, source.Stride, sourceX, sourceY);
                var offset = checked((patternY * stride) + (patternX * 4));
                output[offset] = sample.Blue;
                output[offset + 1] = sample.Green;
                output[offset + 2] = sample.Red;
                output[offset + 3] = sample.Alpha;
            }
        }

        var bitmap = BitmapSource.Create(
            patternWidth,
            patternHeight,
            96,
            96,
            PixelFormats.Bgra32,
            palette: null,
            output,
            stride);
        RenderOptions.SetBitmapScalingMode(bitmap, BitmapScalingMode.NearestNeighbor);
        bitmap.Freeze();
        return new ScreenshotMosaicPattern(
            bitmap,
            new Rect(
                startX,
                startY,
                checked(patternWidth * blockSize),
                checked(patternHeight * blockSize)),
            output.LongLength);
    }

    public static void Draw(
        DrawingContext drawing,
        BitmapSource pixelated,
        MosaicAnnotation annotation,
        Rect canvasBounds)
    {
        var clip = Clip(annotation);
        drawing.PushClip(clip);
        DrawPattern(drawing, pixelated, canvasBounds);
        drawing.Pop();
    }

    public static void DrawPattern(
        DrawingContext drawing,
        BitmapSource pattern,
        Rect canvasBounds)
    {
        var group = new DrawingGroup();
        RenderOptions.SetBitmapScalingMode(group, BitmapScalingMode.NearestNeighbor);
        group.Children.Add(new ImageDrawing(pattern, canvasBounds));
        group.Freeze();
        drawing.DrawDrawing(group);
    }

    private static Bgra Sample(
        ReadOnlySpan<byte> input,
        int stride,
        int left,
        int top)
    {
        var offset = checked((top * stride) + (left * 4));
        return new Bgra(
            input[offset],
            input[offset + 1],
            input[offset + 2],
            input[offset + 3]);
    }

    internal static ScreenshotMosaicPatternKey PatternKey(
        FrozenScreenshot source,
        int blockSize,
        int anchorX,
        int anchorY)
    {
        ArgumentNullException.ThrowIfNull(source);
        var normalizedBlockSize = NormalizeBlockSize(source, blockSize);
        return new ScreenshotMosaicPatternKey(
            normalizedBlockSize,
            NormalizeGridStart(anchorX, source.Width, normalizedBlockSize),
            NormalizeGridStart(anchorY, source.Height, normalizedBlockSize));
    }

    private static int NormalizeGridStart(int anchor, int length, int blockSize) =>
        // The annotation clip hides cells before its bounds. Anchors with the same phase
        // therefore sample the same source grid and can safely share one compact pattern.
        Math.Clamp(anchor, 0, length - 1) % blockSize;

    private static Geometry Clip(MosaicAnnotation annotation)
    {
        if (annotation.Points.Count == 1)
        {
            var circle = new EllipseGeometry(
                ScreenshotDrawingPrimitives.Point(annotation.Points[0]),
                annotation.BrushSize / 2,
                annotation.BrushSize / 2);
            circle.Freeze();
            return circle;
        }

        var path = ScreenshotDrawingPrimitives.Polyline(annotation.Points);
        var pen = new MediaPen(Brushes.Black, annotation.BrushSize)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        var widened = path.GetWidenedPathGeometry(
            pen,
            tolerance: 0.25,
            ToleranceType.Absolute);
        widened.Freeze();
        return widened;
    }

    private readonly record struct Bgra(byte Blue, byte Green, byte Red, byte Alpha);
}

internal readonly record struct ScreenshotMosaicPatternKey(
    int BlockSize,
    int StartX,
    int StartY);

internal sealed class ScreenshotMosaicPattern
{
    public ScreenshotMosaicPattern(BitmapSource bitmap, Rect canvasBounds, long byteCount)
    {
        Bitmap = bitmap ?? throw new ArgumentNullException(nameof(bitmap));
        CanvasBounds = canvasBounds;
        ByteCount = byteCount;
    }

    public BitmapSource Bitmap { get; }

    public Rect CanvasBounds { get; }

    public long ByteCount { get; }
}

/// <summary>
/// Keeps only compact, one-pixel-per-block mosaic patterns for the current source frame.
/// The byte budget is one uncompressed BGRA source frame, so dragging an annotation through
/// different grid phases cannot retain a full-resolution bitmap for every pointer position.
/// </summary>
internal sealed class ScreenshotMosaicPatternCache
{
    private readonly Dictionary<
        ScreenshotMosaicPatternKey,
        LinkedListNode<CacheEntry>> entries = [];
    private readonly LinkedList<CacheEntry> recency = [];
    private FrozenScreenshot? source;

    public int Count => entries.Count;

    public long CachedByteCount { get; private set; }

    public long ByteCapacity { get; private set; }

    public ScreenshotMosaicPattern GetOrCreate(
        FrozenScreenshot source,
        int blockSize,
        int anchorX,
        int anchorY)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (!ReferenceEquals(this.source, source))
        {
            Reset(source);
        }

        var key = ScreenshotMosaicCompositor.PatternKey(
            source,
            blockSize,
            anchorX,
            anchorY);
        if (entries.TryGetValue(key, out var cached))
        {
            recency.Remove(cached);
            recency.AddFirst(cached);
            return cached.Value.Pattern;
        }

        var pattern = ScreenshotMosaicCompositor.CreatePattern(
            source,
            key.BlockSize,
            key.StartX,
            key.StartY);
        while (recency.Last is { } oldest
               && CachedByteCount + pattern.ByteCount > ByteCapacity)
        {
            recency.RemoveLast();
            entries.Remove(oldest.Value.Key);
            CachedByteCount -= oldest.Value.Pattern.ByteCount;
        }

        var entry = new CacheEntry(key, pattern);
        var node = recency.AddFirst(entry);
        entries.Add(key, node);
        CachedByteCount += pattern.ByteCount;
        return pattern;
    }

    public void Clear()
    {
        source = null;
        entries.Clear();
        recency.Clear();
        CachedByteCount = 0;
        ByteCapacity = 0;
    }

    private void Reset(FrozenScreenshot newSource)
    {
        entries.Clear();
        recency.Clear();
        CachedByteCount = 0;
        source = newSource;
        ByteCapacity = checked((long)newSource.Width * newSource.Height * 4);
    }

    private sealed record CacheEntry(
        ScreenshotMosaicPatternKey Key,
        ScreenshotMosaicPattern Pattern);
}
