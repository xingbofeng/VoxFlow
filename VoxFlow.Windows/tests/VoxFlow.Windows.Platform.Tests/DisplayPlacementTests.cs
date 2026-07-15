using VoxFlow.Windows.Platform.Display;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class DisplayPlacementTests
{
    [Theory]
    [InlineData(100, 1260, 720)]
    [InlineData(125, 1575, 900)]
    [InlineData(150, 1890, 1080)]
    [InlineData(200, 2520, 1440)]
    public void Dpi_scale_round_trips_logical_layout_at_required_windows_scales(
        int percent,
        double expectedDeviceWidth,
        double expectedDeviceHeight)
    {
        var scale = DpiScale.FromPercent(percent);

        Assert.Equal(expectedDeviceWidth, scale.ToDevicePixels(1260));
        Assert.Equal(expectedDeviceHeight, scale.ToDevicePixels(720));
        Assert.Equal(1260, scale.ToLogicalPixels(expectedDeviceWidth));
        Assert.Equal(720, scale.ToLogicalPixels(expectedDeviceHeight));
    }

    [Fact]
    public void Physical_work_areas_are_normalized_to_device_independent_pixels()
    {
        var display = DisplayDescriptor.FromPhysicalWorkArea(
            "secondary",
            new PixelRect(1920, 0, 1920, 1080),
            DpiScale.FromPercent(150),
            isPrimary: false);

        Assert.Equal(new LogicalRect(1280, 0, 1280, 720), display.WorkArea);
    }

    [Fact]
    public void Main_window_restores_and_clamps_within_the_last_valid_display()
    {
        var displays = Displays();
        var state = new DisplayPlacementState(
            "secondary",
            new LogicalRect(2_500, 900, 900, 500));

        var placement = DisplayPlacementResolver.RestoreMainWindow(
            state,
            displays,
            defaultWidth: 1260,
            defaultHeight: 720,
            minimumWidth: 1260,
            minimumHeight: 720);

        Assert.Equal("secondary", placement.Display.Id);
        Assert.False(placement.UsedPrimaryFallback);
        Assert.Equal(1260, placement.Bounds.Width);
        Assert.Equal(720, placement.Bounds.Height);
        Assert.True(placement.Display.WorkArea.Contains(placement.Bounds));
    }

    [Fact]
    public void Missing_saved_display_falls_back_to_primary_and_centers_main_window()
    {
        var state = new DisplayPlacementState(
            "disconnected-monitor",
            new LogicalRect(9_999, 9_999, 1260, 720));

        var placement = DisplayPlacementResolver.RestoreMainWindow(
            state,
            Displays(),
            defaultWidth: 1260,
            defaultHeight: 720,
            minimumWidth: 1260,
            minimumHeight: 720);

        Assert.Equal("primary", placement.Display.Id);
        Assert.True(placement.UsedPrimaryFallback);
        Assert.Equal(new LogicalRect(330, 180, 1260, 720), placement.Bounds);
    }

    [Fact]
    public void Hud_uses_last_valid_display_or_primary_and_stays_40_dips_above_bottom()
    {
        var displays = Displays();

        var restored = DisplayPlacementResolver.PlaceHud(
            "secondary",
            displays,
            width: 360,
            height: 64,
            bottomInset: 40);
        var fallback = DisplayPlacementResolver.PlaceHud(
            "missing",
            displays,
            width: 360,
            height: 64,
            bottomInset: 40);

        Assert.Equal("secondary", restored.Display.Id);
        Assert.False(restored.UsedPrimaryFallback);
        Assert.Equal(
            restored.Display.WorkArea.Bottom - 40 - 64,
            restored.Bounds.Top);
        Assert.Equal(
            restored.Display.WorkArea.Left
                + ((restored.Display.WorkArea.Width - 360) / 2),
            restored.Bounds.Left);

        Assert.Equal("primary", fallback.Display.Id);
        Assert.True(fallback.UsedPrimaryFallback);
        Assert.True(fallback.Display.WorkArea.Contains(fallback.Bounds));
    }

    private static DisplayDescriptor[] Displays() =>
    [
        DisplayDescriptor.FromPhysicalWorkArea(
            "primary",
            new PixelRect(0, 0, 1920, 1080),
            DpiScale.FromPercent(100),
            isPrimary: true),
        DisplayDescriptor.FromPhysicalWorkArea(
            "secondary",
            new PixelRect(1920, 0, 3840, 2160),
            DpiScale.FromPercent(100),
            isPrimary: false),
    ];
}
