using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain.Screenshots;

public sealed class ScreenshotDocument
{
    [JsonConstructor]
    public ScreenshotDocument(
        Guid id,
        PixelSize canvasSize,
        IReadOnlyList<ScreenshotAnnotation> annotations,
        int revision)
    {
        if (id == Guid.Empty)
        {
            throw new ArgumentException("A screenshot document identifier is required.", nameof(id));
        }
        ArgumentNullException.ThrowIfNull(annotations);
        ArgumentOutOfRangeException.ThrowIfNegative(revision);
        if (annotations.Any(static annotation => annotation is null))
        {
            throw new ArgumentException("Annotations cannot contain null values.", nameof(annotations));
        }
        if (annotations.Select(static annotation => annotation.Id).Distinct().Count()
            != annotations.Count)
        {
            throw new ArgumentException("Annotation identifiers must be unique.", nameof(annotations));
        }

        Id = id;
        CanvasSize = canvasSize;
        Annotations = Array.AsReadOnly(annotations.ToArray());
        Revision = revision;
    }

    public Guid Id { get; }

    public PixelSize CanvasSize { get; }

    public IReadOnlyList<ScreenshotAnnotation> Annotations { get; }

    public int Revision { get; }

    [JsonIgnore]
    public SourceRect CanvasBounds => new(0, 0, CanvasSize.Width, CanvasSize.Height);

    public ScreenshotDocument WithAnnotations(IReadOnlyList<ScreenshotAnnotation> annotations) => new(
        Id,
        CanvasSize,
        annotations,
        checked(Revision + 1));
}

public sealed class AnnotationSelection
{
    public static AnnotationSelection Empty { get; } = new([]);

    public AnnotationSelection(IReadOnlyList<Guid> ids)
    {
        ArgumentNullException.ThrowIfNull(ids);
        if (ids.Any(static id => id == Guid.Empty))
        {
            throw new ArgumentException("Selection identifiers cannot be empty.", nameof(ids));
        }
        if (ids.Distinct().Count() != ids.Count)
        {
            throw new ArgumentException("Selection identifiers must be unique.", nameof(ids));
        }
        Ids = Array.AsReadOnly(ids.ToArray());
    }

    public IReadOnlyList<Guid> Ids { get; }

    public bool Contains(Guid id) => Ids.Contains(id);
}

public static class ScreenshotAnnotationFactory
{
    public const double MinimumSampleDistance = 2;
    public const double MinimumShapeSize = 2;
    public const double MinimumArrowLength = 5;
    public const double DotMarkerRadius = 6;
    public const double NumberedMarkerRadius = 9;
    public const double MosaicBrushSize = 40;
    public const double MosaicBlockSize = 8;

    public static bool TryCreate(
        ScreenshotTool tool,
        SourcePoint start,
        IReadOnlyList<SourcePoint> points,
        string? text,
        int nextNumber,
        out ScreenshotAnnotation? annotation,
        AnnotationStyle? style = null,
        TextAnnotationStyle? textStyle = null)
    {
        ArgumentNullException.ThrowIfNull(points);
        if (!Enum.IsDefined(tool))
        {
            throw new ArgumentOutOfRangeException(nameof(tool));
        }
        if (nextNumber <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(nextNumber));
        }

        style ??= AnnotationStyle.Default;
        textStyle ??= TextAnnotationStyle.Default;
        var sampled = Sample(start, points);
        var end = points.Count == 0 ? start : points[^1];

        annotation = tool switch
        {
            ScreenshotTool.Pen when sampled.Count >= 2 =>
                new PenAnnotation(Guid.NewGuid(), sampled, style),
            ScreenshotTool.Ellipse when IsValidShape(start, end) =>
                new EllipseAnnotation(Guid.NewGuid(), SourceRect.FromPoints(start, end), style),
            ScreenshotTool.Rectangle when IsValidShape(start, end) =>
                new RectangleAnnotation(Guid.NewGuid(), SourceRect.FromPoints(start, end), style),
            ScreenshotTool.Arrow when start.DistanceTo(end) >= MinimumArrowLength =>
                new ArrowAnnotation(Guid.NewGuid(), start, end, style),
            ScreenshotTool.DotMarker =>
                new DotMarkerAnnotation(Guid.NewGuid(), start, DotMarkerRadius, style),
            ScreenshotTool.NumberedMarker =>
                new NumberedMarkerAnnotation(
                    Guid.NewGuid(),
                    start,
                    nextNumber,
                    NumberedMarkerRadius,
                    style),
            ScreenshotTool.Text when !string.IsNullOrWhiteSpace(text) =>
                new TextAnnotation(Guid.NewGuid(), start, text.Trim(), textStyle),
            ScreenshotTool.Mosaic when sampled.Count >= 2 =>
                new MosaicAnnotation(
                    Guid.NewGuid(),
                    sampled,
                    MosaicBrushSize,
                    MosaicBlockSize),
            _ => null,
        };
        return annotation is not null;
    }

    private static IReadOnlyList<SourcePoint> Sample(
        SourcePoint start,
        IReadOnlyList<SourcePoint> points)
    {
        var sampled = new List<SourcePoint> { start };
        foreach (var point in points)
        {
            if (sampled[^1].DistanceTo(point) >= MinimumSampleDistance)
            {
                sampled.Add(point);
            }
        }
        return sampled;
    }

    private static bool IsValidShape(SourcePoint start, SourcePoint end)
    {
        var rect = SourceRect.FromPoints(start, end);
        return rect.Width >= MinimumShapeSize && rect.Height >= MinimumShapeSize;
    }
}

public sealed record TextAnnotationDraft
{
    public const double MinimumWidth = 80;
    public const double MaximumWidth = 220;
    public const double Height = 28;

    public TextAnnotationDraft(SourcePoint position, string text, TextAnnotationStyle style)
    {
        ArgumentNullException.ThrowIfNull(text);
        Position = position;
        Text = text;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourcePoint Position { get; }

    public string Text { get; }

    public TextAnnotationStyle Style { get; }

    [JsonIgnore]
    public double Width => Math.Clamp(
        Math.Max(Text.Length, 1) * Style.FontSize * 0.6,
        MinimumWidth,
        MaximumWidth);

    public bool TryCommit(out TextAnnotation? annotation)
    {
        if (string.IsNullOrWhiteSpace(Text))
        {
            annotation = null;
            return false;
        }

        annotation = new TextAnnotation(Guid.NewGuid(), Position, Text.Trim(), Style);
        return true;
    }
}

public static class AnnotationHitTester
{
    public static Guid? HitTest(
        IReadOnlyList<ScreenshotAnnotation> annotations,
        SourcePoint point)
    {
        ArgumentNullException.ThrowIfNull(annotations);
        for (var index = annotations.Count - 1; index >= 0; index--)
        {
            if (Contains(annotations[index], point))
            {
                return annotations[index].Id;
            }
        }
        return null;
    }

    private static bool Contains(ScreenshotAnnotation annotation, SourcePoint point) =>
        annotation switch
        {
            PenAnnotation pen => PolylineContains(
                pen.Points,
                point,
                Math.Max(10, pen.Style.LineWidth * 3)),
            ArrowAnnotation arrow => SegmentContains(
                arrow.Start,
                arrow.End,
                point,
                Math.Max(12, arrow.Style.LineWidth * 3)),
            RectangleAnnotation rectangle => rectangle.Rect.Inflate(10, 10).Contains(point),
            EllipseAnnotation ellipse => ellipse.Rect.Inflate(10, 10).Contains(point),
            DotMarkerAnnotation dot => dot.Bounds.Inflate(8, 8).Contains(point),
            NumberedMarkerAnnotation numbered => numbered.Bounds.Inflate(8, 8).Contains(point),
            TextAnnotation text => text.Bounds.Inflate(12, 12).Contains(point),
            MosaicAnnotation mosaic when mosaic.Points.Count == 1 =>
                mosaic.Points[0].DistanceTo(point) <= Math.Max(10, (mosaic.BrushSize / 2) + 4),
            MosaicAnnotation mosaic => PolylineContains(
                mosaic.Points,
                point,
                Math.Max(10, (mosaic.BrushSize / 2) + 4)),
            _ => false,
        };

    private static bool PolylineContains(
        IReadOnlyList<SourcePoint> points,
        SourcePoint point,
        double tolerance)
    {
        if (points.Count == 1)
        {
            return points[0].DistanceTo(point) <= tolerance;
        }
        for (var index = 1; index < points.Count; index++)
        {
            if (SegmentContains(points[index - 1], points[index], point, tolerance))
            {
                return true;
            }
        }
        return false;
    }

    private static bool SegmentContains(
        SourcePoint start,
        SourcePoint end,
        SourcePoint point,
        double tolerance)
    {
        var deltaX = end.X - start.X;
        var deltaY = end.Y - start.Y;
        var lengthSquared = (deltaX * deltaX) + (deltaY * deltaY);
        if (lengthSquared <= double.Epsilon)
        {
            return start.DistanceTo(point) <= tolerance;
        }
        var projection = Math.Clamp(
            (((point.X - start.X) * deltaX) + ((point.Y - start.Y) * deltaY))
                / lengthSquared,
            0,
            1);
        var nearest = new SourcePoint(
            start.X + (projection * deltaX),
            start.Y + (projection * deltaY));
        return nearest.DistanceTo(point) <= tolerance;
    }
}
