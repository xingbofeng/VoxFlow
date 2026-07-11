namespace VoxFlow.Windows.Platform.Display;

public static class DisplayPlacementResolver
{
    public static ResolvedDisplayPlacement RestoreMainWindow(
        DisplayPlacementState? state,
        IReadOnlyList<DisplayDescriptor> displays,
        double defaultWidth,
        double defaultHeight,
        double minimumWidth,
        double minimumHeight)
    {
        ValidateDimensions(defaultWidth, defaultHeight);
        ValidateDimensions(minimumWidth, minimumHeight);
        var selection = SelectDisplay(state?.DisplayId, displays);
        var workArea = selection.Display.WorkArea;

        if (selection.UsedFallback || state is null)
        {
            var width = Math.Min(workArea.Width, Math.Max(defaultWidth, minimumWidth));
            var height = Math.Min(workArea.Height, Math.Max(defaultHeight, minimumHeight));
            return new ResolvedDisplayPlacement(
                selection.Display,
                new LogicalRect(
                    workArea.Left + ((workArea.Width - width) / 2),
                    workArea.Top + ((workArea.Height - height) / 2),
                    width,
                    height),
                selection.UsedFallback);
        }

        var restoredWidth = Math.Min(
            workArea.Width,
            Math.Max(state.Bounds.Width, minimumWidth));
        var restoredHeight = Math.Min(
            workArea.Height,
            Math.Max(state.Bounds.Height, minimumHeight));
        var restoredLeft = Math.Clamp(
            state.Bounds.Left,
            workArea.Left,
            workArea.Right - restoredWidth);
        var restoredTop = Math.Clamp(
            state.Bounds.Top,
            workArea.Top,
            workArea.Bottom - restoredHeight);

        return new ResolvedDisplayPlacement(
            selection.Display,
            new LogicalRect(restoredLeft, restoredTop, restoredWidth, restoredHeight),
            false);
    }

    public static ResolvedDisplayPlacement PlaceHud(
        string? displayId,
        IReadOnlyList<DisplayDescriptor> displays,
        double width,
        double height,
        double bottomInset)
    {
        ValidateDimensions(width, height);
        if (bottomInset < 0 || !double.IsFinite(bottomInset))
        {
            throw new ArgumentOutOfRangeException(nameof(bottomInset));
        }

        var selection = SelectDisplay(displayId, displays);
        var workArea = selection.Display.WorkArea;
        var resolvedWidth = Math.Min(width, workArea.Width);
        var resolvedHeight = Math.Min(height, workArea.Height);
        var left = workArea.Left + ((workArea.Width - resolvedWidth) / 2);
        var preferredTop = workArea.Bottom - bottomInset - resolvedHeight;
        var top = Math.Clamp(
            preferredTop,
            workArea.Top,
            workArea.Bottom - resolvedHeight);

        return new ResolvedDisplayPlacement(
            selection.Display,
            new LogicalRect(left, top, resolvedWidth, resolvedHeight),
            selection.UsedFallback);
    }

    private static (DisplayDescriptor Display, bool UsedFallback) SelectDisplay(
        string? requestedId,
        IReadOnlyList<DisplayDescriptor> displays)
    {
        ArgumentNullException.ThrowIfNull(displays);
        if (displays.Count == 0)
        {
            throw new ArgumentException("At least one display is required.", nameof(displays));
        }

        if (!string.IsNullOrWhiteSpace(requestedId))
        {
            var requested = displays.FirstOrDefault(display =>
                string.Equals(display.Id, requestedId, StringComparison.Ordinal));
            if (requested is not null)
            {
                return (requested, false);
            }
        }

        return (displays.FirstOrDefault(display => display.IsPrimary) ?? displays[0], true);
    }

    private static void ValidateDimensions(double width, double height)
    {
        if (width <= 0 || height <= 0 || !double.IsFinite(width) || !double.IsFinite(height))
        {
            throw new ArgumentOutOfRangeException(
                nameof(width),
                "Placement dimensions must be finite and positive.");
        }
    }
}
