using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class SelectionResultWindowPlacementTests
{
    [Theory]
    [InlineData(1.0)]
    [InlineData(1.25)]
    [InlineData(1.5)]
    [InlineData(2.0)]
    public void Right_side_centered_placement_uses_logical_440_by_560_at_each_dpi(double scale)
    {
        var display = new SelectionDisplay("main", new WindowBounds(0, 0, 1600, 1000), scale);
        var placement = SelectionResultWindowPlacement.Calculate(
            new WindowBounds(100, 200, 800, 600),
            [display], display, display);

        Assert.Equal(440, placement.Width);
        Assert.Equal(560, placement.Height);
        Assert.Equal(Math.Min(928 / scale, (1600 - 28 - (440 * scale)) / scale), placement.Left, 3);
        Assert.Equal(
            Math.Max(0, (200 + ((600 - (560 * scale)) / 2)) / scale),
            placement.Top,
            3);
    }

    [Fact]
    public void Missing_target_display_falls_back_to_mouse_display_then_clamps_to_visible_work_area()
    {
        var mouse = new SelectionDisplay("mouse", new WindowBounds(0, 0, 900, 700), 1);
        var placement = SelectionResultWindowPlacement.Calculate(
            new WindowBounds(2200, 100, 400, 300),
            [mouse], targetDisplay: null, mouseDisplay: mouse);

        Assert.Equal(432, placement.Left);
        Assert.Equal(28, placement.Top);
        Assert.Equal(440, placement.Width);
        Assert.Equal(560, placement.Height);
    }

    [Fact]
    public void Too_small_work_area_clamps_without_producing_negative_coordinates()
    {
        var display = new SelectionDisplay("small", new WindowBounds(10, 20, 300, 200), 1);
        var placement = SelectionResultWindowPlacement.Calculate(
            new WindowBounds(10, 20, 20, 20), [display], display, display);

        Assert.Equal(10, placement.Left);
        Assert.Equal(20, placement.Top);
    }
}
