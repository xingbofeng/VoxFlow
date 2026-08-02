using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain.Screenshots;

public readonly record struct SourcePoint
{
    [JsonConstructor]
    public SourcePoint(double x, double y)
    {
        EnsureFinite(x, nameof(x));
        EnsureFinite(y, nameof(y));
        X = x;
        Y = y;
    }

    public double X { get; }

    public double Y { get; }

    public SourcePoint Translate(SourceVector offset) => new(
        X + offset.X,
        Y + offset.Y);

    public double DistanceTo(SourcePoint other)
    {
        var deltaX = other.X - X;
        var deltaY = other.Y - Y;
        return Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
    }

    private static void EnsureFinite(double value, string parameterName)
    {
        if (!double.IsFinite(value))
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }
}

public readonly record struct SourceVector
{
    [JsonConstructor]
    public SourceVector(double x, double y)
    {
        if (!double.IsFinite(x))
        {
            throw new ArgumentOutOfRangeException(nameof(x));
        }
        if (!double.IsFinite(y))
        {
            throw new ArgumentOutOfRangeException(nameof(y));
        }

        X = x;
        Y = y;
    }

    public double X { get; }

    public double Y { get; }
}

public readonly record struct SourceRect
{
    [JsonConstructor]
    public SourceRect(double left, double top, double width, double height)
    {
        if (!double.IsFinite(left)
            || !double.IsFinite(top)
            || !double.IsFinite(width)
            || !double.IsFinite(height)
            || width < 0
            || height < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        Left = left;
        Top = top;
        Width = width;
        Height = height;
    }

    public double Left { get; }

    public double Top { get; }

    public double Width { get; }

    public double Height { get; }

    [JsonIgnore]
    public double Right => Left + Width;

    [JsonIgnore]
    public double Bottom => Top + Height;

    [JsonIgnore]
    public bool IsEmpty => Width == 0 || Height == 0;

    public static SourceRect FromPoints(SourcePoint first, SourcePoint second) => new(
        Math.Min(first.X, second.X),
        Math.Min(first.Y, second.Y),
        Math.Abs(second.X - first.X),
        Math.Abs(second.Y - first.Y));

    public bool Contains(SourcePoint point) =>
        point.X >= Left && point.X <= Right && point.Y >= Top && point.Y <= Bottom;

    public bool Intersects(SourceRect other) =>
        Math.Max(Left, other.Left) <= Math.Min(Right, other.Right)
        && Math.Max(Top, other.Top) <= Math.Min(Bottom, other.Bottom);

    public SourceRect Union(SourceRect other)
    {
        if (IsEmpty)
        {
            return other;
        }
        if (other.IsEmpty)
        {
            return this;
        }

        return new SourceRect(
            Math.Min(Left, other.Left),
            Math.Min(Top, other.Top),
            Math.Max(Right, other.Right) - Math.Min(Left, other.Left),
            Math.Max(Bottom, other.Bottom) - Math.Min(Top, other.Top));
    }

    public SourceRect Translate(SourceVector offset) => new(
        Left + offset.X,
        Top + offset.Y,
        Width,
        Height);

    public SourceRect Inflate(double horizontal, double vertical) => new(
        Left - horizontal,
        Top - vertical,
        Width + (horizontal * 2),
        Height + (vertical * 2));
}

public readonly record struct AnnotationColor
{
    [JsonConstructor]
    public AnnotationColor(
        double redComponent,
        double greenComponent,
        double blueComponent,
        double alphaComponent = 1)
    {
        ValidateComponent(redComponent, nameof(redComponent));
        ValidateComponent(greenComponent, nameof(greenComponent));
        ValidateComponent(blueComponent, nameof(blueComponent));
        ValidateComponent(alphaComponent, nameof(alphaComponent));
        RedComponent = redComponent;
        GreenComponent = greenComponent;
        BlueComponent = blueComponent;
        AlphaComponent = alphaComponent;
    }

    public double RedComponent { get; }

    public double GreenComponent { get; }

    public double BlueComponent { get; }

    public double AlphaComponent { get; }

    public static AnnotationColor VoxGreen { get; } = new(0.10, 0.66, 0.35);

    public static AnnotationColor Red { get; } = new(0.95, 0.20, 0.20);

    public static AnnotationColor White { get; } = new(1, 1, 1);

    public static AnnotationColor Black { get; } = new(0, 0, 0);

    private static void ValidateComponent(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value is < 0 or > 1)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }
}

public sealed record AnnotationStyle
{
    [JsonConstructor]
    public AnnotationStyle(
        AnnotationColor color,
        double lineWidth,
        AnnotationColor? fillColor)
    {
        if (!double.IsFinite(lineWidth) || lineWidth <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(lineWidth));
        }

        Color = color;
        LineWidth = lineWidth;
        FillColor = fillColor;
    }

    public AnnotationColor Color { get; }

    public double LineWidth { get; }

    public AnnotationColor? FillColor { get; }

    public static AnnotationStyle Default { get; } = new(
        AnnotationColor.VoxGreen,
        lineWidth: 6,
        fillColor: null);

    public AnnotationStyle WithColor(AnnotationColor color) =>
        new(color, LineWidth, FillColor);

    public AnnotationStyle WithLineWidth(double lineWidth) =>
        new(Color, lineWidth, FillColor);
}

public sealed record TextAnnotationStyle
{
    [JsonConstructor]
    public TextAnnotationStyle(AnnotationColor color, double fontSize, string fontName)
    {
        if (!double.IsFinite(fontSize) || fontSize <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(fontSize));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(fontName);

        Color = color;
        FontSize = fontSize;
        FontName = fontName.Trim();
    }

    public AnnotationColor Color { get; }

    public double FontSize { get; }

    public string FontName { get; }

    public static TextAnnotationStyle Default { get; } = new(
        AnnotationColor.VoxGreen,
        fontSize: 14,
        fontName: "Segoe UI");

    public TextAnnotationStyle WithColor(AnnotationColor color) =>
        new(color, FontSize, FontName);

    public TextAnnotationStyle WithFontSize(double fontSize) =>
        new(Color, fontSize, FontName);
}

public static class AnnotationPalette
{
    public static IReadOnlyList<AnnotationColor> Colors { get; } = Array.AsReadOnly(
        new[]
        {
            AnnotationColor.VoxGreen,
            AnnotationColor.Red,
            AnnotationColor.White,
            AnnotationColor.Black,
        });

    public static IReadOnlyList<double> LineWidths { get; } = Array.AsReadOnly(
        new[] { 6d, 8d, 10d });

    public static IReadOnlyList<double> FontSizes { get; } = Array.AsReadOnly(
        new[] { 14d, 24d, 32d });
}

public enum ScreenshotTool
{
    Select,
    Pen,
    Ellipse,
    Rectangle,
    Arrow,
    DotMarker,
    NumberedMarker,
    Text,
    Mosaic,
    TextRecognition,
    Translate,
}

public enum AnnotationKind
{
    Pen,
    Ellipse,
    Rectangle,
    Arrow,
    DotMarker,
    NumberedMarker,
    Text,
    Mosaic,
}

public enum AnnotationResizeHandle
{
    TopLeft,
    Top,
    TopRight,
    Left,
    Right,
    BottomLeft,
    Bottom,
    BottomRight,
}

[JsonPolymorphic(TypeDiscriminatorPropertyName = "$type")]
[JsonDerivedType(typeof(PenAnnotation), "pen")]
[JsonDerivedType(typeof(EllipseAnnotation), "ellipse")]
[JsonDerivedType(typeof(RectangleAnnotation), "rectangle")]
[JsonDerivedType(typeof(ArrowAnnotation), "arrow")]
[JsonDerivedType(typeof(DotMarkerAnnotation), "dotMarker")]
[JsonDerivedType(typeof(NumberedMarkerAnnotation), "numberedMarker")]
[JsonDerivedType(typeof(TextAnnotation), "text")]
[JsonDerivedType(typeof(MosaicAnnotation), "mosaic")]
public abstract class ScreenshotAnnotation
{
    protected ScreenshotAnnotation(Guid id)
    {
        if (id == Guid.Empty)
        {
            throw new ArgumentException("An annotation identifier is required.", nameof(id));
        }
        Id = id;
    }

    public Guid Id { get; }

    [JsonIgnore]
    public abstract AnnotationKind Kind { get; }

    [JsonIgnore]
    public abstract SourceRect Bounds { get; }

    public abstract ScreenshotAnnotation MoveBy(SourceVector offset);

    public abstract ScreenshotAnnotation Transform(SourceRect source, SourceRect target);

    public abstract ScreenshotAnnotation Duplicate(
        Guid id,
        SourceVector offset,
        int? numberedMarkerNumber = null);

    public virtual ScreenshotAnnotation WithColor(AnnotationColor color) => this;

    public virtual ScreenshotAnnotation WithLineWidth(double lineWidth) => this;

    public virtual ScreenshotAnnotation WithFontSize(double fontSize) => this;

    protected static SourcePoint TransformPoint(
        SourcePoint point,
        SourceRect source,
        SourceRect target)
    {
        var xRatio = source.Width <= 0 ? 0 : (point.X - source.Left) / source.Width;
        var yRatio = source.Height <= 0 ? 0 : (point.Y - source.Top) / source.Height;
        return new SourcePoint(
            target.Left + (xRatio * target.Width),
            target.Top + (yRatio * target.Height));
    }

    protected static SourceRect TransformRect(
        SourceRect rect,
        SourceRect source,
        SourceRect target)
    {
        var topLeft = TransformPoint(new SourcePoint(rect.Left, rect.Top), source, target);
        var bottomRight = TransformPoint(new SourcePoint(rect.Right, rect.Bottom), source, target);
        return SourceRect.FromPoints(topLeft, bottomRight);
    }

    protected static double ScaleLength(
        double value,
        SourceRect source,
        SourceRect target)
    {
        var xScale = source.Width <= 0 ? 1 : target.Width / source.Width;
        var yScale = source.Height <= 0 ? 1 : target.Height / source.Height;
        return value * Math.Max(0.01, Math.Min(Math.Abs(xScale), Math.Abs(yScale)));
    }
}

public sealed class PenAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public PenAnnotation(Guid id, IReadOnlyList<SourcePoint> points, AnnotationStyle style)
        : base(id)
    {
        ArgumentNullException.ThrowIfNull(points);
        if (points.Count == 0)
        {
            throw new ArgumentException("A pen annotation requires at least one point.", nameof(points));
        }
        Style = style ?? throw new ArgumentNullException(nameof(style));
        Points = Array.AsReadOnly(points.ToArray());
    }

    public IReadOnlyList<SourcePoint> Points { get; }

    public AnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.Pen;

    public override SourceRect Bounds => AnnotationBounds.ForPoints(Points);

    public override ScreenshotAnnotation MoveBy(SourceVector offset) => new PenAnnotation(
        Id,
        Points.Select(point => point.Translate(offset)).ToArray(),
        Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new PenAnnotation(
            Id,
            Points.Select(point => TransformPoint(point, source, target)).ToArray(),
            Style);

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new PenAnnotation(id, Points.Select(point => point.Translate(offset)).ToArray(), Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new PenAnnotation(Id, Points, Style.WithColor(color));

    public override ScreenshotAnnotation WithLineWidth(double lineWidth) =>
        new PenAnnotation(Id, Points, Style.WithLineWidth(lineWidth));
}

public sealed class EllipseAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public EllipseAnnotation(Guid id, SourceRect rect, AnnotationStyle style)
        : base(id)
    {
        if (rect.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(rect));
        }
        Rect = rect;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourceRect Rect { get; }

    public AnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.Ellipse;

    public override SourceRect Bounds => Rect;

    public override ScreenshotAnnotation MoveBy(SourceVector offset) =>
        new EllipseAnnotation(Id, Rect.Translate(offset), Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new EllipseAnnotation(Id, TransformRect(Rect, source, target), Style);

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new EllipseAnnotation(id, Rect.Translate(offset), Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new EllipseAnnotation(Id, Rect, Style.WithColor(color));

    public override ScreenshotAnnotation WithLineWidth(double lineWidth) =>
        new EllipseAnnotation(Id, Rect, Style.WithLineWidth(lineWidth));
}

public sealed class RectangleAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public RectangleAnnotation(Guid id, SourceRect rect, AnnotationStyle style)
        : base(id)
    {
        if (rect.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(rect));
        }
        Rect = rect;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourceRect Rect { get; }

    public AnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.Rectangle;

    public override SourceRect Bounds => Rect;

    public override ScreenshotAnnotation MoveBy(SourceVector offset) =>
        new RectangleAnnotation(Id, Rect.Translate(offset), Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new RectangleAnnotation(Id, TransformRect(Rect, source, target), Style);

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new RectangleAnnotation(id, Rect.Translate(offset), Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new RectangleAnnotation(Id, Rect, Style.WithColor(color));

    public override ScreenshotAnnotation WithLineWidth(double lineWidth) =>
        new RectangleAnnotation(Id, Rect, Style.WithLineWidth(lineWidth));
}

public sealed class ArrowAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public ArrowAnnotation(
        Guid id,
        SourcePoint start,
        SourcePoint end,
        AnnotationStyle style)
        : base(id)
    {
        Start = start;
        End = end;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourcePoint Start { get; }

    public SourcePoint End { get; }

    public AnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.Arrow;

    public override SourceRect Bounds => SourceRect
        .FromPoints(Start, End)
        .Inflate(Style.LineWidth * 3, Style.LineWidth * 3);

    public override ScreenshotAnnotation MoveBy(SourceVector offset) => new ArrowAnnotation(
        Id,
        Start.Translate(offset),
        End.Translate(offset),
        Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new ArrowAnnotation(
            Id,
            TransformPoint(Start, source, target),
            TransformPoint(End, source, target),
            Style);

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new ArrowAnnotation(id, Start.Translate(offset), End.Translate(offset), Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new ArrowAnnotation(Id, Start, End, Style.WithColor(color));

    public override ScreenshotAnnotation WithLineWidth(double lineWidth) =>
        new ArrowAnnotation(Id, Start, End, Style.WithLineWidth(lineWidth));
}

public sealed class DotMarkerAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public DotMarkerAnnotation(Guid id, SourcePoint center, double radius, AnnotationStyle style)
        : base(id)
    {
        if (!double.IsFinite(radius) || radius <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(radius));
        }
        Center = center;
        Radius = radius;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourcePoint Center { get; }

    public double Radius { get; }

    public AnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.DotMarker;

    public override SourceRect Bounds => new(
        Center.X - Radius,
        Center.Y - Radius,
        Radius * 2,
        Radius * 2);

    public override ScreenshotAnnotation MoveBy(SourceVector offset) =>
        new DotMarkerAnnotation(Id, Center.Translate(offset), Radius, Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new DotMarkerAnnotation(
            Id,
            TransformPoint(Center, source, target),
            ScaleLength(Radius, source, target),
            Style);

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new DotMarkerAnnotation(id, Center.Translate(offset), Radius, Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new DotMarkerAnnotation(Id, Center, Radius, Style.WithColor(color));

    public override ScreenshotAnnotation WithLineWidth(double lineWidth) =>
        new DotMarkerAnnotation(Id, Center, Radius, Style.WithLineWidth(lineWidth));
}

public sealed class NumberedMarkerAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public NumberedMarkerAnnotation(
        Guid id,
        SourcePoint center,
        int number,
        double radius,
        AnnotationStyle style)
        : base(id)
    {
        if (number <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(number));
        }
        if (!double.IsFinite(radius) || radius <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(radius));
        }
        Center = center;
        Number = number;
        Radius = radius;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourcePoint Center { get; }

    public int Number { get; }

    public double Radius { get; }

    public AnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.NumberedMarker;

    public override SourceRect Bounds => new(
        Center.X - Radius,
        Center.Y - Radius,
        Radius * 2,
        Radius * 2);

    public override ScreenshotAnnotation MoveBy(SourceVector offset) =>
        new NumberedMarkerAnnotation(Id, Center.Translate(offset), Number, Radius, Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new NumberedMarkerAnnotation(
            Id,
            TransformPoint(Center, source, target),
            Number,
            ScaleLength(Radius, source, target),
            Style);

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new NumberedMarkerAnnotation(
            id,
            Center.Translate(offset),
            numberedMarkerNumber ?? Number,
            Radius,
            Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new NumberedMarkerAnnotation(Id, Center, Number, Radius, Style.WithColor(color));

    public override ScreenshotAnnotation WithLineWidth(double lineWidth) =>
        new NumberedMarkerAnnotation(Id, Center, Number, Radius, Style.WithLineWidth(lineWidth));
}

public sealed class TextAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public TextAnnotation(
        Guid id,
        SourcePoint position,
        string content,
        TextAnnotationStyle style)
        : base(id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(content);
        Position = position;
        Content = content;
        Style = style ?? throw new ArgumentNullException(nameof(style));
    }

    public SourcePoint Position { get; }

    public string Content { get; }

    public TextAnnotationStyle Style { get; }

    public override AnnotationKind Kind => AnnotationKind.Text;

    public override SourceRect Bounds
    {
        get
        {
            var lines = Content.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
            var longest = lines.Max(static line => line.Length);
            return new SourceRect(
                Position.X,
                Position.Y,
                Math.Max(longest * Style.FontSize * 0.6, Style.FontSize * 2),
                Math.Max(1, lines.Length) * Style.FontSize * 1.3);
        }
    }

    public override ScreenshotAnnotation MoveBy(SourceVector offset) =>
        new TextAnnotation(Id, Position.Translate(offset), Content, Style);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new TextAnnotation(
            Id,
            TransformPoint(Position, source, target),
            Content,
            Style.WithFontSize(Math.Max(10, ScaleLength(Style.FontSize, source, target))));

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new TextAnnotation(id, Position.Translate(offset), Content, Style);

    public override ScreenshotAnnotation WithColor(AnnotationColor color) =>
        new TextAnnotation(Id, Position, Content, Style.WithColor(color));

    public override ScreenshotAnnotation WithFontSize(double fontSize) =>
        new TextAnnotation(Id, Position, Content, Style.WithFontSize(fontSize));
}

public sealed class MosaicAnnotation : ScreenshotAnnotation
{
    [JsonConstructor]
    public MosaicAnnotation(
        Guid id,
        IReadOnlyList<SourcePoint> points,
        double brushSize,
        double blockSize)
        : base(id)
    {
        ArgumentNullException.ThrowIfNull(points);
        if (points.Count == 0)
        {
            throw new ArgumentException("A mosaic annotation requires at least one point.", nameof(points));
        }
        if (!double.IsFinite(brushSize) || brushSize <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(brushSize));
        }
        if (!double.IsFinite(blockSize) || blockSize <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(blockSize));
        }

        Points = Array.AsReadOnly(points.ToArray());
        BrushSize = brushSize;
        BlockSize = blockSize;
    }

    public IReadOnlyList<SourcePoint> Points { get; }

    public double BrushSize { get; }

    public double BlockSize { get; }

    public override AnnotationKind Kind => AnnotationKind.Mosaic;

    public override SourceRect Bounds => AnnotationBounds.ForPoints(Points)
        .Inflate(BrushSize / 2, BrushSize / 2);

    public override ScreenshotAnnotation MoveBy(SourceVector offset) => new MosaicAnnotation(
        Id,
        Points.Select(point => point.Translate(offset)).ToArray(),
        BrushSize,
        BlockSize);

    public override ScreenshotAnnotation Transform(SourceRect source, SourceRect target) =>
        new MosaicAnnotation(
            Id,
            Points.Select(point => TransformPoint(point, source, target)).ToArray(),
            ScaleLength(BrushSize, source, target),
            ScaleLength(BlockSize, source, target));

    public override ScreenshotAnnotation Duplicate(Guid id, SourceVector offset, int? numberedMarkerNumber = null) =>
        new MosaicAnnotation(
            id,
            Points.Select(point => point.Translate(offset)).ToArray(),
            BrushSize,
            BlockSize);
}

internal static class AnnotationBounds
{
    public static SourceRect ForPoints(IReadOnlyList<SourcePoint> points)
    {
        var left = points.Min(static point => point.X);
        var top = points.Min(static point => point.Y);
        var right = points.Max(static point => point.X);
        var bottom = points.Max(static point => point.Y);
        return new SourceRect(left, top, right - left, bottom - top);
    }
}
