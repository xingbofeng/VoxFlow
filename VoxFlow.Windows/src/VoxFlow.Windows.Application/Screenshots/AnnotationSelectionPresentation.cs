using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.Application.Screenshots;

public sealed record AnnotationHandlePresentation(
    AnnotationResizeHandle Handle,
    SourceRect Bounds);

public sealed record AnnotationSelectionPresentationModel(
    SourceRect Bounds,
    double BorderThickness,
    IReadOnlyList<double> DashPattern,
    AnnotationColor BorderColor,
    AnnotationColor HandleFillColor,
    double HandleBorderThickness,
    IReadOnlyList<AnnotationHandlePresentation> Handles);

public static class AnnotationSelectionPresentation
{
    public const double BorderThickness = 1.5;
    public const double HandleSize = 8;
    public const double HandleBorderThickness = 1;

    public static IReadOnlyList<double> DashPattern { get; } =
        Array.AsReadOnly(new[] { 5d, 3d });

    public static AnnotationSelectionPresentationModel Calculate(SourceRect bounds)
    {
        if (bounds.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(bounds));
        }

        var half = HandleSize / 2;
        var middleX = bounds.Left + (bounds.Width / 2);
        var middleY = bounds.Top + (bounds.Height / 2);
        var handles = Array.AsReadOnly(new[]
        {
            Handle(AnnotationResizeHandle.TopLeft, bounds.Left, bounds.Top, half),
            Handle(AnnotationResizeHandle.Top, middleX, bounds.Top, half),
            Handle(AnnotationResizeHandle.TopRight, bounds.Right, bounds.Top, half),
            Handle(AnnotationResizeHandle.Left, bounds.Left, middleY, half),
            Handle(AnnotationResizeHandle.Right, bounds.Right, middleY, half),
            Handle(AnnotationResizeHandle.BottomLeft, bounds.Left, bounds.Bottom, half),
            Handle(AnnotationResizeHandle.Bottom, middleX, bounds.Bottom, half),
            Handle(AnnotationResizeHandle.BottomRight, bounds.Right, bounds.Bottom, half),
        });
        return new AnnotationSelectionPresentationModel(
            bounds,
            BorderThickness,
            DashPattern,
            AnnotationColor.VoxGreen,
            AnnotationColor.White,
            HandleBorderThickness,
            handles);
    }

    private static AnnotationHandlePresentation Handle(
        AnnotationResizeHandle handle,
        double centerX,
        double centerY,
        double half) => new(
            handle,
            new SourceRect(
                centerX - half,
                centerY - half,
                HandleSize,
                HandleSize));
}
