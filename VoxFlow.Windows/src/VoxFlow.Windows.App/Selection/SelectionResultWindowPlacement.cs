using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Selection;

/// <summary>
/// Converts physical target/display bounds to the WPF logical coordinates used
/// by the result window. The pure calculation keeps monitor unplug and DPI
/// behavior testable without creating a Window.
/// </summary>
public sealed record SelectionDisplay
{
    public SelectionDisplay(string id, WindowBounds workArea, double dpiScale)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentNullException.ThrowIfNull(workArea);
        if (!double.IsFinite(dpiScale) || dpiScale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dpiScale));
        }

        Id = id;
        WorkArea = workArea;
        DpiScale = dpiScale;
    }

    public string Id { get; }

    public WindowBounds WorkArea { get; }

    public double DpiScale { get; }
}

public sealed record SelectionWindowPlacement(
    double Left,
    double Top,
    double Width,
    double Height,
    string DisplayId);

public static class SelectionResultWindowPlacement
{
    public const double LogicalWidth = 440;
    public const double LogicalHeight = 560;
    public const double PhysicalMargin = 28;

    public static SelectionWindowPlacement Calculate(
        WindowBounds targetBounds,
        IReadOnlyList<SelectionDisplay> displays,
        SelectionDisplay? targetDisplay,
        SelectionDisplay? mouseDisplay)
    {
        ArgumentNullException.ThrowIfNull(targetBounds);
        ArgumentNullException.ThrowIfNull(displays);
        var display = targetDisplay
            ?? mouseDisplay
            ?? displays.FirstOrDefault()
            ?? throw new ArgumentException("At least one display is required.", nameof(displays));
        var scale = display.DpiScale;
        var width = LogicalWidth * scale;
        var height = LogicalHeight * scale;
        var desiredLeft = targetBounds.Left + targetBounds.Width + PhysicalMargin;
        var desiredTop = targetBounds.Top + ((targetBounds.Height - height) / 2);
        var left = ClampToWorkArea(
            desiredLeft,
            display.WorkArea.Left,
            display.WorkArea.Width,
            width);
        var top = ClampToWorkArea(
            desiredTop,
            display.WorkArea.Top,
            display.WorkArea.Height,
            height);
        return new SelectionWindowPlacement(
            left / scale,
            top / scale,
            LogicalWidth,
            LogicalHeight,
            display.Id);
    }

    private static double ClampToWorkArea(
        double desired,
        double workAreaStart,
        double workAreaLength,
        double contentLength)
    {
        var minimum = workAreaStart + PhysicalMargin;
        var maximum = workAreaStart + workAreaLength - PhysicalMargin - contentLength;
        if (maximum < minimum)
        {
            return workAreaStart;
        }

        return Math.Clamp(desired, minimum, maximum);
    }
}
