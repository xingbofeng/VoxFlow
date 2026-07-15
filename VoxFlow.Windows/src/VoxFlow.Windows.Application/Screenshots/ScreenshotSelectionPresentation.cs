using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.Application.Screenshots;

public enum ScreenshotCursorKind
{
    Arrow,
    Crosshair,
    OpenHand,
    ClosedHand,
    SizeWestEast,
    SizeNorthSouth,
    SizeNorthwestSoutheast,
    SizeNortheastSouthwest,
}

public enum ToolbarPlacement
{
    Below,
    Above,
}

public sealed record SelectionHandlePresentation(
    ScreenshotResizeHandle Handle,
    PixelRect Bounds);

public sealed record SelectionPresentationModel(
    PixelRect? Selection,
    string? DimensionLabel,
    IReadOnlyList<PixelRect> OutsideMasks,
    IReadOnlyList<SelectionHandlePresentation> ResizeHandles,
    double OutsideMaskOpacity,
    double CandidateFillOpacity,
    int BorderThickness,
    ScreenshotCursorKind Cursor);

public sealed record ToolbarPlacementResult(
    PixelRect Frame,
    ToolbarPlacement Placement);

/// <summary>
/// WPF-free presentation math matching the macOS selection overlay baseline.
/// All inputs and outputs remain in virtual-desktop physical pixels.
/// </summary>
public static class ScreenshotSelectionPresentation
{
    public const double NoSelectionMaskOpacity = 0.18;
    public const double SelectionMaskOpacity = 0.42;
    public const double CandidateFillOpacity = 0.22;
    public const int BorderThickness = 2;
    public const int HandleSize = 8;
    public const int ToolbarItemSize = 28;
    public const int ToolbarItemSpacing = 4;
    public const int ToolbarContentPadding = 8;
    public const int ToolbarHeight = 44;
    public const int ToolbarGap = 8;

    public static IReadOnlyList<ScreenshotTool> AnnotationTools { get; } =
        Array.AsReadOnly(new[]
        {
            ScreenshotTool.Select,
            ScreenshotTool.Pen,
            ScreenshotTool.Ellipse,
            ScreenshotTool.Rectangle,
            ScreenshotTool.Arrow,
            ScreenshotTool.DotMarker,
            ScreenshotTool.NumberedMarker,
            ScreenshotTool.Text,
            ScreenshotTool.Mosaic,
            ScreenshotTool.TextRecognition,
            ScreenshotTool.Translate,
        });

    // 11 annotation/workflow tools + color/width/font + 8 edit/export actions.
    public const int ToolbarItemCount = 22;

    public const int ToolbarWidth =
        (ToolbarItemCount * ToolbarItemSize)
        + ((ToolbarItemCount - 1) * ToolbarItemSpacing)
        + (ToolbarContentPadding * 2);

    public static SelectionPresentationModel Calculate(
        PixelRect viewport,
        PixelRect? selection,
        bool hasAnySelection,
        ScreenshotResizeHandle? activeHandle,
        bool isMoving)
    {
        if (viewport.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(viewport));
        }
        if (activeHandle is not null && !Enum.IsDefined(activeHandle.Value))
        {
            throw new ArgumentOutOfRangeException(nameof(activeHandle));
        }

        var clipped = selection?.Intersection(viewport);
        if (clipped is { IsEmpty: true })
        {
            clipped = null;
        }
        var masks = clipped is null
            ? Array.AsReadOnly(new[] { viewport })
            : Array.AsReadOnly(BuildMasks(viewport, clipped.Value));
        var handles = clipped is null
            ? Array.Empty<SelectionHandlePresentation>()
            : BuildHandles(clipped.Value);

        return new SelectionPresentationModel(
            clipped,
            clipped is null ? null : $"{clipped.Value.Width} × {clipped.Value.Height}",
            masks,
            handles,
            hasAnySelection ? SelectionMaskOpacity : NoSelectionMaskOpacity,
            CandidateFillOpacity,
            BorderThickness,
            CursorFor(activeHandle, isMoving, clipped is not null));
    }

    public static ToolbarPlacementResult PlaceToolbar(
        PixelRect selection,
        PixelRect visibleBounds)
    {
        if (selection.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(selection));
        }
        if (visibleBounds.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(visibleBounds));
        }

        var proposedX = selection.Left + ((selection.Width - ToolbarWidth) / 2);
        var minimumX = visibleBounds.Left + ToolbarContentPadding;
        var maximumX = visibleBounds.Right - ToolbarWidth - ToolbarContentPadding;
        var x = maximumX < minimumX
            ? minimumX
            : Math.Clamp(proposedX, minimumX, maximumX);
        var belowY = selection.Bottom + ToolbarGap;
        if ((long)belowY + ToolbarHeight <= visibleBounds.Bottom)
        {
            return new ToolbarPlacementResult(
                new PixelRect(x, belowY, ToolbarWidth, ToolbarHeight),
                ToolbarPlacement.Below);
        }

        var aboveY = Math.Max(
            visibleBounds.Top + ToolbarContentPadding,
            selection.Top - ToolbarHeight - ToolbarGap);
        return new ToolbarPlacementResult(
            new PixelRect(x, aboveY, ToolbarWidth, ToolbarHeight),
            ToolbarPlacement.Above);
    }

    public static ScreenshotCursorKind CursorFor(
        ScreenshotResizeHandle? handle,
        bool isMoving,
        bool hasSelection)
    {
        if (handle is not null)
        {
            return handle.Value switch
            {
                ScreenshotResizeHandle.Top or ScreenshotResizeHandle.Bottom =>
                    ScreenshotCursorKind.SizeNorthSouth,
                ScreenshotResizeHandle.Left or ScreenshotResizeHandle.Right =>
                    ScreenshotCursorKind.SizeWestEast,
                ScreenshotResizeHandle.TopLeft or ScreenshotResizeHandle.BottomRight =>
                    ScreenshotCursorKind.SizeNorthwestSoutheast,
                ScreenshotResizeHandle.TopRight or ScreenshotResizeHandle.BottomLeft =>
                    ScreenshotCursorKind.SizeNortheastSouthwest,
                _ => throw new ArgumentOutOfRangeException(nameof(handle)),
            };
        }
        if (isMoving)
        {
            return ScreenshotCursorKind.ClosedHand;
        }
        return hasSelection
            ? ScreenshotCursorKind.OpenHand
            : ScreenshotCursorKind.Crosshair;
    }

    private static PixelRect[] BuildMasks(PixelRect viewport, PixelRect selection)
    {
        var masks = new List<PixelRect>(capacity: 4);
        AddIfVisible(masks, new PixelRect(
            viewport.Left,
            viewport.Top,
            viewport.Width,
            selection.Top - viewport.Top));
        AddIfVisible(masks, new PixelRect(
            viewport.Left,
            selection.Top,
            selection.Left - viewport.Left,
            selection.Height));
        AddIfVisible(masks, new PixelRect(
            selection.Right,
            selection.Top,
            viewport.Right - selection.Right,
            selection.Height));
        AddIfVisible(masks, new PixelRect(
            viewport.Left,
            selection.Bottom,
            viewport.Width,
            viewport.Bottom - selection.Bottom));
        return masks.ToArray();
    }

    private static IReadOnlyList<SelectionHandlePresentation> BuildHandles(PixelRect rect)
    {
        var half = HandleSize / 2;
        var middleX = rect.Left + (rect.Width / 2);
        var middleY = rect.Top + (rect.Height / 2);
        return Array.AsReadOnly(new[]
        {
            Handle(ScreenshotResizeHandle.TopLeft, rect.Left, rect.Top, half),
            Handle(ScreenshotResizeHandle.Top, middleX, rect.Top, half),
            Handle(ScreenshotResizeHandle.TopRight, rect.Right, rect.Top, half),
            Handle(ScreenshotResizeHandle.Left, rect.Left, middleY, half),
            Handle(ScreenshotResizeHandle.Right, rect.Right, middleY, half),
            Handle(ScreenshotResizeHandle.BottomLeft, rect.Left, rect.Bottom, half),
            Handle(ScreenshotResizeHandle.Bottom, middleX, rect.Bottom, half),
            Handle(ScreenshotResizeHandle.BottomRight, rect.Right, rect.Bottom, half),
        });
    }

    private static SelectionHandlePresentation Handle(
        ScreenshotResizeHandle handle,
        int centerX,
        int centerY,
        int half) => new(
            handle,
            new PixelRect(
                checked(centerX - half),
                checked(centerY - half),
                HandleSize,
                HandleSize));

    private static void AddIfVisible(ICollection<PixelRect> masks, PixelRect mask)
    {
        if (!mask.IsEmpty)
        {
            masks.Add(mask);
        }
    }
}
