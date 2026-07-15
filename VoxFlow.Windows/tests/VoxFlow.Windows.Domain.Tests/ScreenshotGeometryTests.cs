using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class ScreenshotGeometryTests
{
    [Fact]
    public void Pixel_rect_normalizes_intersects_unions_and_translates_without_losing_negative_origins()
    {
        var rect = PixelRect.FromPoints(
            new PixelPoint(100, 200),
            new PixelPoint(-50, -25));
        var other = new PixelRect(50, 100, 100, 200);

        Assert.Equal(new PixelRect(-50, -25, 150, 225), rect);
        Assert.Equal(new PixelRect(50, 100, 50, 100), rect.Intersection(other));
        Assert.Equal(new PixelRect(-50, -25, 200, 325), rect.Union(other));
        Assert.Equal(new PixelRect(-40, -45, 150, 225), rect.Translate(10, -20));
        Assert.True(rect.Contains(new PixelPoint(-50, -25)));
        Assert.False(rect.Contains(new PixelPoint(100, 200)));
    }

    [Fact]
    public void Pixel_geometry_rejects_overflow_and_invalid_sizes()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new PixelSize(0, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() => new PixelRect(0, 0, -1, 1));
        Assert.Throws<OverflowException>(() =>
            new PixelRect(int.MaxValue - 2, 0, 2, 1).Translate(1, 0));
        Assert.Throws<OverflowException>(() => PixelRect.FromPoints(
            new PixelPoint(int.MinValue, 0),
            new PixelPoint(int.MaxValue, 1)));
    }

    [Theory]
    [InlineData(96, 100, 100)]
    [InlineData(120, 100, 80)]
    [InlineData(144, 150, 100)]
    [InlineData(192, 200, 100)]
    public void Coordinate_mapper_converts_physical_pixels_to_per_monitor_dips(
        int dpi,
        int physical,
        double expectedDip)
    {
        var display = new ScreenshotDisplay(
            "display",
            "DISPLAY1",
            new PixelRect(-1920, -300, 1920, 1080),
            dpi,
            dpi,
            DisplayRotation.Degrees0,
            isPrimary: false);
        var mapper = new ScreenshotCoordinateMapper(display);

        var dip = mapper.ToDip(new PixelPoint(-1920 + physical, -300 + physical));
        var restored = mapper.ToPhysical(dip);

        Assert.Equal(expectedDip, dip.X, 6);
        Assert.Equal(expectedDip, dip.Y, 6);
        Assert.Equal(new PixelPoint(-1920 + physical, -300 + physical), restored);
    }

    [Fact]
    public void Coordinate_mapper_uses_floor_ceil_edges_and_supports_rotated_mixed_dpi_displays()
    {
        var portrait = new ScreenshotDisplay(
            "portrait",
            "DISPLAY2",
            new PixelRect(0, -2160, 2160, 3840),
            144,
            192,
            DisplayRotation.Degrees90,
            isPrimary: true);
        var mapper = new ScreenshotCoordinateMapper(portrait);

        var dipRect = mapper.ToDip(new PixelRect(3, -2157, 301, 403));
        var physical = mapper.ToPhysical(dipRect);

        Assert.Equal(2, dipRect.Left, 6);
        Assert.Equal(1.5, dipRect.Top, 6);
        Assert.Equal(new PixelRect(3, -2157, 301, 403), physical);
        Assert.Equal(2160, portrait.Bounds.Width);
        Assert.Equal(3840, portrait.Bounds.Height);
    }

    [Fact]
    public void Desktop_layout_maps_points_using_the_monitor_that_contains_them()
    {
        var left = new ScreenshotDisplay(
            "left",
            "DISPLAY1",
            new PixelRect(-1920, 0, 1920, 1080),
            120,
            120,
            DisplayRotation.Degrees0,
            isPrimary: false);
        var main = new ScreenshotDisplay(
            "main",
            "DISPLAY2",
            new PixelRect(0, 0, 3840, 2160),
            192,
            192,
            DisplayRotation.Degrees0,
            isPrimary: true);
        var layout = new ScreenshotDesktopLayout([left, main]);

        Assert.Equal(new PixelRect(-1920, 0, 5760, 2160), layout.VirtualBounds);
        Assert.Equal("left", layout.DisplayAt(new PixelPoint(-100, 100))!.Id);
        Assert.Equal("main", layout.DisplayAt(new PixelPoint(100, 100))!.Id);
        Assert.Equal(80, layout.ToDisplayDip(new PixelPoint(-1820, 100)).X, 6);
        Assert.Equal(50, layout.ToDisplayDip(new PixelPoint(100, 100)).X, 6);
    }
}
