namespace VoxFlow.Windows.Platform.Display;

public readonly record struct PixelRect(
    double Left,
    double Top,
    double Width,
    double Height);

public readonly record struct LogicalRect(
    double Left,
    double Top,
    double Width,
    double Height)
{
    public double Right => Left + Width;

    public double Bottom => Top + Height;

    public bool Contains(LogicalRect other) =>
        other.Left >= Left
        && other.Top >= Top
        && other.Right <= Right
        && other.Bottom <= Bottom;
}

public sealed record DisplayDescriptor(
    string Id,
    LogicalRect WorkArea,
    DpiScale Scale,
    bool IsPrimary)
{
    public static DisplayDescriptor FromPhysicalWorkArea(
        string id,
        PixelRect workArea,
        DpiScale scale,
        bool isPrimary)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        if (workArea.Width <= 0 || workArea.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(workArea),
                "A display work area must have positive dimensions.");
        }

        return new DisplayDescriptor(
            id,
            new LogicalRect(
                scale.ToLogicalPixels(workArea.Left),
                scale.ToLogicalPixels(workArea.Top),
                scale.ToLogicalPixels(workArea.Width),
                scale.ToLogicalPixels(workArea.Height)),
            scale,
            isPrimary);
    }
}

public sealed record DisplayPlacementState(
    string DisplayId,
    LogicalRect Bounds);

public sealed record ResolvedDisplayPlacement(
    DisplayDescriptor Display,
    LogicalRect Bounds,
    bool UsedPrimaryFallback);
