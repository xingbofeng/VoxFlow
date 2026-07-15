using System.Windows.Media;
using VoxFlow.Windows.Domain.Screenshots;
using MediaColor = System.Windows.Media.Color;
using MediaPen = System.Windows.Media.Pen;
using Point = System.Windows.Point;
using Rect = System.Windows.Rect;

namespace VoxFlow.Windows.App.Screenshot;

internal static class ScreenshotDrawingPrimitives
{
    public const double PixelsPerDip = 1;

    public static StreamGeometry Polyline(IReadOnlyList<SourcePoint> points)
    {
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(Point(points[0]), isFilled: false, isClosed: false);
            if (points.Count > 1)
            {
                context.PolyLineTo(
                    points.Skip(1).Select(Point).ToArray(),
                    isStroked: true,
                    isSmoothJoin: true);
            }
        }
        geometry.Freeze();
        return geometry;
    }

    public static MediaPen Stroke(AnnotationStyle style)
    {
        var pen = new MediaPen(Brush(style.Color), style.LineWidth)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            DashCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        return pen;
    }

    public static SolidColorBrush? Fill(AnnotationStyle style) =>
        style.FillColor is { } color ? Brush(color) : null;

    public static SolidColorBrush Brush(AnnotationColor color)
    {
        var brush = new SolidColorBrush(MediaColor.FromArgb(
            Component(color.AlphaComponent),
            Component(color.RedComponent),
            Component(color.GreenComponent),
            Component(color.BlueComponent)));
        brush.Freeze();
        return brush;
    }

    public static double RelativeLuminance(AnnotationColor color) =>
        (0.2126 * color.RedComponent)
        + (0.7152 * color.GreenComponent)
        + (0.0722 * color.BlueComponent);

    public static Point Point(SourcePoint point) => new(point.X, point.Y);

    public static Rect Rect(SourceRect rect) =>
        new(rect.Left, rect.Top, rect.Width, rect.Height);

    private static byte Component(double value) => checked((byte)Math.Round(
        value * byte.MaxValue,
        MidpointRounding.AwayFromZero));
}
