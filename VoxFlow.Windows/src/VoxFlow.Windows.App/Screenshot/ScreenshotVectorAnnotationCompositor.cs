using System.Globalization;
using System.Windows;
using System.Windows.Media;
using VoxFlow.Windows.Domain.Screenshots;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using Point = System.Windows.Point;

namespace VoxFlow.Windows.App.Screenshot;

internal static class ScreenshotVectorAnnotationCompositor
{
    public static void Draw(DrawingContext drawing, ScreenshotAnnotation annotation)
    {
        switch (annotation)
        {
            case PenAnnotation pen:
                DrawPen(drawing, pen);
                break;
            case EllipseAnnotation ellipse:
                DrawEllipse(drawing, ellipse);
                break;
            case RectangleAnnotation rectangle:
                DrawRectangle(drawing, rectangle);
                break;
            case ArrowAnnotation arrow:
                DrawArrow(drawing, arrow);
                break;
            case DotMarkerAnnotation dot:
                DrawDotMarker(drawing, dot);
                break;
            case NumberedMarkerAnnotation numbered:
                DrawNumberedMarker(drawing, numbered);
                break;
            case TextAnnotation text:
                DrawText(drawing, text);
                break;
            default:
                throw new NotSupportedException(
                    $"Unsupported screenshot annotation type: {annotation.GetType().Name}.");
        }
    }

    private static void DrawPen(DrawingContext drawing, PenAnnotation annotation)
    {
        var pen = ScreenshotDrawingPrimitives.Stroke(annotation.Style);
        if (annotation.Points.Count == 1)
        {
            drawing.DrawEllipse(
                pen.Brush,
                pen: null,
                ScreenshotDrawingPrimitives.Point(annotation.Points[0]),
                pen.Thickness / 2,
                pen.Thickness / 2);
            return;
        }

        drawing.DrawGeometry(
            brush: null,
            pen,
            ScreenshotDrawingPrimitives.Polyline(annotation.Points));
    }

    private static void DrawEllipse(DrawingContext drawing, EllipseAnnotation annotation)
    {
        var rect = ScreenshotDrawingPrimitives.Rect(annotation.Rect);
        drawing.DrawEllipse(
            ScreenshotDrawingPrimitives.Fill(annotation.Style),
            ScreenshotDrawingPrimitives.Stroke(annotation.Style),
            new Point(rect.Left + (rect.Width / 2), rect.Top + (rect.Height / 2)),
            rect.Width / 2,
            rect.Height / 2);
    }

    private static void DrawRectangle(
        DrawingContext drawing,
        RectangleAnnotation annotation)
    {
        drawing.DrawRectangle(
            ScreenshotDrawingPrimitives.Fill(annotation.Style),
            ScreenshotDrawingPrimitives.Stroke(annotation.Style),
            ScreenshotDrawingPrimitives.Rect(annotation.Rect));
    }

    private static void DrawArrow(DrawingContext drawing, ArrowAnnotation annotation)
    {
        var start = ScreenshotDrawingPrimitives.Point(annotation.Start);
        var end = ScreenshotDrawingPrimitives.Point(annotation.End);
        var deltaX = end.X - start.X;
        var deltaY = end.Y - start.Y;
        var length = Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
        var pen = ScreenshotDrawingPrimitives.Stroke(annotation.Style);
        if (length < double.Epsilon)
        {
            drawing.DrawEllipse(
                pen.Brush,
                pen: null,
                end,
                pen.Thickness / 2,
                pen.Thickness / 2);
            return;
        }

        drawing.DrawLine(pen, start, end);
        var angle = Math.Atan2(deltaY, deltaX);
        var headLength = Math.Max(10, annotation.Style.LineWidth * 4);
        const double headAngle = Math.PI / 6;
        var first = new Point(
            end.X - (headLength * Math.Cos(angle - headAngle)),
            end.Y - (headLength * Math.Sin(angle - headAngle)));
        var second = new Point(
            end.X - (headLength * Math.Cos(angle + headAngle)),
            end.Y - (headLength * Math.Sin(angle + headAngle)));

        var head = new StreamGeometry();
        using (var context = head.Open())
        {
            context.BeginFigure(end, isFilled: true, isClosed: true);
            context.LineTo(first, isStroked: true, isSmoothJoin: true);
            context.LineTo(second, isStroked: true, isSmoothJoin: true);
        }
        head.Freeze();
        drawing.DrawGeometry(pen.Brush, pen: null, head);
    }

    private static void DrawDotMarker(
        DrawingContext drawing,
        DotMarkerAnnotation annotation)
    {
        drawing.DrawEllipse(
            ScreenshotDrawingPrimitives.Brush(
                annotation.Style.FillColor ?? annotation.Style.Color),
            new System.Windows.Media.Pen(
                ScreenshotDrawingPrimitives.Brush(AnnotationColor.White),
                Math.Max(1, annotation.Style.LineWidth)),
            ScreenshotDrawingPrimitives.Point(annotation.Center),
            annotation.Radius,
            annotation.Radius);
    }

    private static void DrawNumberedMarker(
        DrawingContext drawing,
        NumberedMarkerAnnotation annotation)
    {
        drawing.DrawEllipse(
            ScreenshotDrawingPrimitives.Brush(
                annotation.Style.FillColor ?? annotation.Style.Color),
            new System.Windows.Media.Pen(
                ScreenshotDrawingPrimitives.Brush(AnnotationColor.White),
                Math.Max(1, annotation.Style.LineWidth)),
            ScreenshotDrawingPrimitives.Point(annotation.Center),
            annotation.Radius,
            annotation.Radius);

        var typeface = new Typeface(
            new FontFamily("Segoe UI"),
            FontStyles.Normal,
            FontWeights.Bold,
            FontStretches.Normal);
        var text = new FormattedText(
            annotation.Number.ToString(CultureInfo.InvariantCulture),
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            typeface,
            Math.Max(10, annotation.Radius),
            ScreenshotDrawingPrimitives.Brush(AnnotationColor.White),
            ScreenshotDrawingPrimitives.PixelsPerDip);
        drawing.DrawText(
            text,
            new Point(
                annotation.Center.X - (text.WidthIncludingTrailingWhitespace / 2),
                annotation.Center.Y - (text.Height / 2)));
    }

    private static void DrawText(DrawingContext drawing, TextAnnotation annotation)
    {
        var typeface = new Typeface(
            new FontFamily(annotation.Style.FontName),
            FontStyles.Normal,
            FontWeights.Normal,
            FontStretches.Normal);
        var text = new FormattedText(
            annotation.Content,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            typeface,
            annotation.Style.FontSize,
            ScreenshotDrawingPrimitives.Brush(annotation.Style.Color),
            ScreenshotDrawingPrimitives.PixelsPerDip)
        {
            TextAlignment = TextAlignment.Left,
            Trimming = TextTrimming.None,
        };
        drawing.DrawText(text, ScreenshotDrawingPrimitives.Point(annotation.Position));
    }
}
