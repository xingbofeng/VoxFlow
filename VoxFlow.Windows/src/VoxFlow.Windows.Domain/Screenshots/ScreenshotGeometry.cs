using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain.Screenshots;

public readonly record struct PixelPoint(int X, int Y)
{
    public PixelPoint Translate(int deltaX, int deltaY) => new(
        CheckedInt((long)X + deltaX),
        CheckedInt((long)Y + deltaY));

    private static int CheckedInt(long value) =>
        value is >= int.MinValue and <= int.MaxValue
            ? (int)value
            : throw new OverflowException("The translated pixel point exceeds Int32 bounds.");
}

public readonly record struct PixelSize
{
    [JsonConstructor]
    public PixelSize(int width, int height)
    {
        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }
        if (height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        Width = width;
        Height = height;
    }

    public int Width { get; }

    public int Height { get; }
}

/// <summary>
/// A left-closed, right-open rectangle in Windows virtual-desktop physical pixels.
/// Empty rectangles are allowed so intersections have a total representation.
/// </summary>
public readonly record struct PixelRect
{
    [JsonConstructor]
    public PixelRect(int left, int top, int width, int height)
    {
        if (width < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }
        if (height < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        _ = CheckedInt((long)left + width);
        _ = CheckedInt((long)top + height);

        Left = left;
        Top = top;
        Width = width;
        Height = height;
    }

    public int Left { get; }

    public int Top { get; }

    public int Width { get; }

    public int Height { get; }

    [JsonIgnore]
    public int Right => CheckedInt((long)Left + Width);

    [JsonIgnore]
    public int Bottom => CheckedInt((long)Top + Height);

    [JsonIgnore]
    public bool IsEmpty => Width == 0 || Height == 0;

    [JsonIgnore]
    public PixelSize Size => IsEmpty
        ? throw new InvalidOperationException("An empty rectangle has no positive pixel size.")
        : new PixelSize(Width, Height);

    public static PixelRect FromPoints(PixelPoint first, PixelPoint second)
    {
        var left = Math.Min(first.X, second.X);
        var top = Math.Min(first.Y, second.Y);
        var right = Math.Max(first.X, second.X);
        var bottom = Math.Max(first.Y, second.Y);
        return FromEdges(left, top, right, bottom);
    }

    public static PixelRect FromEdges(long left, long top, long right, long bottom)
    {
        if (right < left)
        {
            throw new ArgumentOutOfRangeException(nameof(right));
        }
        if (bottom < top)
        {
            throw new ArgumentOutOfRangeException(nameof(bottom));
        }

        return new PixelRect(
            CheckedInt(left),
            CheckedInt(top),
            CheckedInt(right - left),
            CheckedInt(bottom - top));
    }

    public bool Contains(PixelPoint point) =>
        point.X >= Left
        && point.X < Right
        && point.Y >= Top
        && point.Y < Bottom;

    public bool Contains(PixelRect rect) =>
        rect.Left >= Left
        && rect.Top >= Top
        && rect.Right <= Right
        && rect.Bottom <= Bottom;

    public bool Intersects(PixelRect other) =>
        Math.Max(Left, other.Left) < Math.Min(Right, other.Right)
        && Math.Max(Top, other.Top) < Math.Min(Bottom, other.Bottom);

    public PixelRect Intersection(PixelRect other)
    {
        var left = Math.Max(Left, other.Left);
        var top = Math.Max(Top, other.Top);
        var right = Math.Max(left, Math.Min(Right, other.Right));
        var bottom = Math.Max(top, Math.Min(Bottom, other.Bottom));
        return FromEdges(left, top, right, bottom);
    }

    public PixelRect Union(PixelRect other)
    {
        if (IsEmpty)
        {
            return other;
        }
        if (other.IsEmpty)
        {
            return this;
        }

        return FromEdges(
            Math.Min(Left, other.Left),
            Math.Min(Top, other.Top),
            Math.Max(Right, other.Right),
            Math.Max(Bottom, other.Bottom));
    }

    public PixelRect Translate(int deltaX, int deltaY) => new(
        CheckedInt((long)Left + deltaX),
        CheckedInt((long)Top + deltaY),
        Width,
        Height);

    public PixelRect ClampInside(PixelRect container)
    {
        if (Width > container.Width || Height > container.Height)
        {
            throw new ArgumentOutOfRangeException(
                nameof(container),
                "The rectangle cannot fit inside the requested container.");
        }

        var left = Math.Clamp(Left, container.Left, container.Right - Width);
        var top = Math.Clamp(Top, container.Top, container.Bottom - Height);
        return new PixelRect(left, top, Width, Height);
    }

    private static int CheckedInt(long value) =>
        value is >= int.MinValue and <= int.MaxValue
            ? (int)value
            : throw new OverflowException("Pixel geometry exceeds Int32 bounds.");
}

public readonly record struct DipPoint
{
    [JsonConstructor]
    public DipPoint(double x, double y)
    {
        EnsureFinite(x, nameof(x));
        EnsureFinite(y, nameof(y));
        X = x;
        Y = y;
    }

    public double X { get; }

    public double Y { get; }

    private static void EnsureFinite(double value, string parameterName)
    {
        if (!double.IsFinite(value))
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }
}

public readonly record struct DipRect
{
    [JsonConstructor]
    public DipRect(double left, double top, double width, double height)
    {
        if (!double.IsFinite(left)
            || !double.IsFinite(top)
            || !double.IsFinite(width)
            || !double.IsFinite(height)
            || width < 0
            || height < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        Left = left;
        Top = top;
        Width = width;
        Height = height;
    }

    public double Left { get; }

    public double Top { get; }

    public double Width { get; }

    public double Height { get; }

    [JsonIgnore]
    public double Right => Left + Width;

    [JsonIgnore]
    public double Bottom => Top + Height;
}

public enum DisplayRotation
{
    Degrees0,
    Degrees90,
    Degrees180,
    Degrees270,
}

public sealed record ScreenshotDisplay
{
    [JsonConstructor]
    public ScreenshotDisplay(
        string id,
        string deviceName,
        PixelRect bounds,
        double dpiX,
        double dpiY,
        DisplayRotation rotation,
        bool isPrimary)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);
        if (bounds.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(bounds));
        }
        if (!double.IsFinite(dpiX) || dpiX <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dpiX));
        }
        if (!double.IsFinite(dpiY) || dpiY <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dpiY));
        }
        if (!Enum.IsDefined(rotation))
        {
            throw new ArgumentOutOfRangeException(nameof(rotation));
        }

        Id = id.Trim();
        DeviceName = deviceName.Trim();
        Bounds = bounds;
        DpiX = dpiX;
        DpiY = dpiY;
        Rotation = rotation;
        IsPrimary = isPrimary;
    }

    public string Id { get; }

    public string DeviceName { get; }

    public PixelRect Bounds { get; }

    public double DpiX { get; }

    public double DpiY { get; }

    public DisplayRotation Rotation { get; }

    public bool IsPrimary { get; }
}

public sealed class ScreenshotCoordinateMapper
{
    private const double DipDpi = 96;
    private const double EdgeEpsilon = 0.0000001;

    public ScreenshotCoordinateMapper(ScreenshotDisplay display)
    {
        Display = display ?? throw new ArgumentNullException(nameof(display));
    }

    public ScreenshotDisplay Display { get; }

    public DipPoint ToDip(PixelPoint point) => new(
        (point.X - (double)Display.Bounds.Left) * DipDpi / Display.DpiX,
        (point.Y - (double)Display.Bounds.Top) * DipDpi / Display.DpiY);

    public DipRect ToDip(PixelRect rect)
    {
        var topLeft = ToDip(new PixelPoint(rect.Left, rect.Top));
        return new DipRect(
            topLeft.X,
            topLeft.Y,
            rect.Width * DipDpi / Display.DpiX,
            rect.Height * DipDpi / Display.DpiY);
    }

    public PixelPoint ToPhysical(DipPoint point) => new(
        CheckedRound(Display.Bounds.Left + (point.X * Display.DpiX / DipDpi)),
        CheckedRound(Display.Bounds.Top + (point.Y * Display.DpiY / DipDpi)));

    public PixelRect ToPhysical(DipRect rect)
    {
        var left = CheckedFloor(
            Display.Bounds.Left + (rect.Left * Display.DpiX / DipDpi));
        var top = CheckedFloor(
            Display.Bounds.Top + (rect.Top * Display.DpiY / DipDpi));
        var right = CheckedCeiling(
            Display.Bounds.Left + (rect.Right * Display.DpiX / DipDpi));
        var bottom = CheckedCeiling(
            Display.Bounds.Top + (rect.Bottom * Display.DpiY / DipDpi));
        return PixelRect.FromEdges(left, top, right, bottom);
    }

    private static int CheckedRound(double value) => CheckedInt(
        Math.Round(value, MidpointRounding.AwayFromZero));

    private static int CheckedFloor(double value) => CheckedInt(
        Math.Floor(value + EdgeEpsilon));

    private static int CheckedCeiling(double value) => CheckedInt(
        Math.Ceiling(value - EdgeEpsilon));

    private static int CheckedInt(double value) =>
        value is >= int.MinValue and <= int.MaxValue
            ? (int)value
            : throw new OverflowException("Mapped screenshot coordinate exceeds Int32 bounds.");
}

public sealed class ScreenshotDesktopLayout
{
    private readonly IReadOnlyList<ScreenshotDisplay> displays;

    public ScreenshotDesktopLayout(IReadOnlyList<ScreenshotDisplay> displays)
    {
        ArgumentNullException.ThrowIfNull(displays);
        if (displays.Count == 0)
        {
            throw new ArgumentException("At least one display is required.", nameof(displays));
        }
        if (displays.Any(static display => display is null))
        {
            throw new ArgumentException("Displays cannot contain null values.", nameof(displays));
        }
        if (displays.Select(static value => value.Id).Distinct(StringComparer.Ordinal).Count()
            != displays.Count)
        {
            throw new ArgumentException("Display identifiers must be unique.", nameof(displays));
        }
        if (displays.Count(static value => value.IsPrimary) != 1)
        {
            throw new ArgumentException("Exactly one primary display is required.", nameof(displays));
        }

        this.displays = Array.AsReadOnly(displays.ToArray());
        VirtualBounds = this.displays
            .Select(static value => value.Bounds)
            .Aggregate(static (current, next) => current.Union(next));
    }

    public IReadOnlyList<ScreenshotDisplay> Displays => displays;

    public ScreenshotDisplay PrimaryDisplay =>
        displays.Single(static value => value.IsPrimary);

    public PixelRect VirtualBounds { get; }

    public ScreenshotDisplay? DisplayAt(PixelPoint point) =>
        displays.FirstOrDefault(display => display.Bounds.Contains(point));

    public DipPoint ToDisplayDip(PixelPoint point)
    {
        var display = DisplayAt(point)
            ?? throw new ArgumentOutOfRangeException(
                nameof(point),
                "The point is outside every active display.");
        return new ScreenshotCoordinateMapper(display).ToDip(point);
    }
}
