using VoxFlow.Windows.Application.Screenshots;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.Application.Tests;

public sealed class ScreenshotSelectionPresentationTests
{
    [Fact]
    public void Presentation_matches_mac_mask_border_handle_and_dimension_measurements()
    {
        var viewport = new PixelRect(0, 0, 1920, 1080);
        var selection = new PixelRect(100, 150, 640, 480);

        var model = ScreenshotSelectionPresentation.Calculate(
            viewport,
            selection,
            hasAnySelection: true,
            ScreenshotResizeHandle.BottomRight,
            isMoving: false);

        Assert.Equal(0.42, model.OutsideMaskOpacity, 6);
        Assert.Equal(2, model.BorderThickness);
        Assert.Equal("640 × 480", model.DimensionLabel);
        Assert.Equal(8, model.ResizeHandles.Count);
        Assert.All(model.ResizeHandles, handle =>
        {
            Assert.Equal(8, handle.Bounds.Width);
            Assert.Equal(8, handle.Bounds.Height);
        });
        Assert.Equal(ScreenshotCursorKind.SizeNorthwestSoutheast, model.Cursor);
        Assert.Equal(4, model.OutsideMasks.Count);
    }

    [Fact]
    public void No_selection_uses_eighteen_percent_mask_and_crosshair_cursor()
    {
        var model = ScreenshotSelectionPresentation.Calculate(
            new PixelRect(-100, -50, 800, 600),
            selection: null,
            hasAnySelection: false,
            activeHandle: null,
            isMoving: false);

        Assert.Equal(0.18, model.OutsideMaskOpacity, 6);
        Assert.Equal(ScreenshotCursorKind.Crosshair, model.Cursor);
        Assert.Single(model.OutsideMasks);
    }

    [Fact]
    public void Toolbar_prefers_below_then_moves_above_and_clamps_horizontally()
    {
        var visible = new PixelRect(0, 0, 1000, 800);
        var below = ScreenshotSelectionPresentation.PlaceToolbar(
            new PixelRect(100, 100, 800, 400),
            visible);
        var above = ScreenshotSelectionPresentation.PlaceToolbar(
            new PixelRect(900, 730, 80, 50),
            visible);

        Assert.Equal(716, below.Frame.Width);
        Assert.Equal(44, below.Frame.Height);
        Assert.Equal(508, below.Frame.Top);
        Assert.Equal(ToolbarPlacement.Below, below.Placement);
        Assert.Equal(ToolbarPlacement.Above, above.Placement);
        Assert.True(above.Frame.Left >= 8);
        Assert.True(above.Frame.Right <= visible.Right - 8);
    }

    [Theory]
    [InlineData(ScreenshotResizeHandle.Top, ScreenshotCursorKind.SizeNorthSouth)]
    [InlineData(ScreenshotResizeHandle.Left, ScreenshotCursorKind.SizeWestEast)]
    [InlineData(ScreenshotResizeHandle.TopLeft, ScreenshotCursorKind.SizeNorthwestSoutheast)]
    [InlineData(ScreenshotResizeHandle.TopRight, ScreenshotCursorKind.SizeNortheastSouthwest)]
    public void Resize_handles_map_to_native_cursor_semantics(
        ScreenshotResizeHandle handle,
        ScreenshotCursorKind expected)
    {
        Assert.Equal(expected, ScreenshotSelectionPresentation.CursorFor(handle, false, true));
    }

    [Fact]
    public void Annotation_selection_uses_mac_dashed_bounds_and_eight_white_green_handles()
    {
        var model = AnnotationSelectionPresentation.Calculate(
            new SourceRect(10, 20, 300, 200));

        Assert.Equal(1.5, model.BorderThickness);
        Assert.Equal([5d, 3d], model.DashPattern);
        Assert.Equal(AnnotationColor.VoxGreen, model.BorderColor);
        Assert.Equal(AnnotationColor.White, model.HandleFillColor);
        Assert.Equal(1, model.HandleBorderThickness);
        Assert.Equal(8, model.Handles.Count);
        Assert.All(model.Handles, handle =>
        {
            Assert.Equal(8, handle.Bounds.Width);
            Assert.Equal(8, handle.Bounds.Height);
        });
    }
}
