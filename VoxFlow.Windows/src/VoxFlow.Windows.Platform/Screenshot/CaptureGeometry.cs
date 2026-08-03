namespace VoxFlow.Windows.Platform.Screenshot;

/// <summary>
/// A point in the signed Windows virtual-desktop physical-pixel coordinate space.
/// </summary>
public readonly record struct CapturePixelPoint(int X, int Y);

/// <summary>
/// A non-empty, left-closed/right-open rectangle in signed physical pixels.
/// </summary>
public readonly record struct CapturePixelRect
{
    public CapturePixelRect(int left, int top, int width, int height)
    {
        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }
        if (height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        _ = checked(left + width);
        _ = checked(top + height);
        Left = left;
        Top = top;
        Width = width;
        Height = height;
    }

    public int Left { get; }

    public int Top { get; }

    public int Width { get; }

    public int Height { get; }

    public int Right => checked(Left + Width);

    public int Bottom => checked(Top + Height);

    public bool Contains(CapturePixelPoint point) =>
        point.X >= Left && point.X < Right && point.Y >= Top && point.Y < Bottom;

    public bool Contains(CapturePixelRect other) =>
        other.Left >= Left
        && other.Top >= Top
        && other.Right <= Right
        && other.Bottom <= Bottom;

    public CapturePixelRect? Intersect(CapturePixelRect other)
    {
        var left = Math.Max(Left, other.Left);
        var top = Math.Max(Top, other.Top);
        var right = Math.Min(Right, other.Right);
        var bottom = Math.Min(Bottom, other.Bottom);
        return right > left && bottom > top
            ? new CapturePixelRect(left, top, right - left, bottom - top)
            : null;
    }

    public static CapturePixelRect Union(IEnumerable<CapturePixelRect> rectangles)
    {
        ArgumentNullException.ThrowIfNull(rectangles);
        using var iterator = rectangles.GetEnumerator();
        if (!iterator.MoveNext())
        {
            throw new ArgumentException("At least one rectangle is required.", nameof(rectangles));
        }

        var left = iterator.Current.Left;
        var top = iterator.Current.Top;
        var right = iterator.Current.Right;
        var bottom = iterator.Current.Bottom;
        while (iterator.MoveNext())
        {
            left = Math.Min(left, iterator.Current.Left);
            top = Math.Min(top, iterator.Current.Top);
            right = Math.Max(right, iterator.Current.Right);
            bottom = Math.Max(bottom, iterator.Current.Bottom);
        }

        return new CapturePixelRect(left, top, checked(right - left), checked(bottom - top));
    }
}

public sealed class FrozenScreenshot
{
    public FrozenScreenshot(int width, int height, int stride, ReadOnlySpan<byte> bgra)
    {
        ValidateBuffer(width, height, stride, bgra.Length);
        Width = width;
        Height = height;
        Stride = stride;
        Bgra = bgra.ToArray();
    }

    public int Width { get; }

    public int Height { get; }

    public int Stride { get; }

    /// <summary>An application-owned immutable BGRA8 snapshot.</summary>
    public ReadOnlyMemory<byte> Bgra { get; }

    internal static void ValidateBuffer(int width, int height, int stride, int bufferLength)
    {
        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }
        if (height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }
        var minimumStride = checked(width * 4);
        if (stride < minimumStride)
        {
            throw new ArgumentOutOfRangeException(nameof(stride));
        }
        if (bufferLength < checked(stride * height))
        {
            throw new ArgumentException("The BGRA buffer is smaller than its declared dimensions.", nameof(bufferLength));
        }
    }
}

public sealed class FrozenDisplayFrame
{
    public FrozenDisplayFrame(
        string deviceName,
        string adapterId,
        CapturePixelRect bounds,
        int rotationDegrees,
        int stride,
        ReadOnlySpan<byte> bgra)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);
        ArgumentException.ThrowIfNullOrWhiteSpace(adapterId);
        if (rotationDegrees is not (0 or 90 or 180 or 270))
        {
            throw new ArgumentOutOfRangeException(nameof(rotationDegrees));
        }
        FrozenScreenshot.ValidateBuffer(bounds.Width, bounds.Height, stride, bgra.Length);

        DeviceName = deviceName;
        AdapterId = adapterId;
        Bounds = bounds;
        RotationDegrees = rotationDegrees;
        Stride = stride;
        Bgra = bgra.ToArray();
    }

    public string DeviceName { get; }

    public string AdapterId { get; }

    public CapturePixelRect Bounds { get; }

    public int RotationDegrees { get; }

    public int Stride { get; }

    /// <summary>An application-owned immutable BGRA8 snapshot.</summary>
    public ReadOnlyMemory<byte> Bgra { get; }
}

/// <summary>
/// A desktop whose frames were all copied before screenshot overlay windows are created.
/// </summary>
public sealed class FrozenDesktop
{
    private readonly FrozenDisplayFrame[] frames;

    public FrozenDesktop(IEnumerable<FrozenDisplayFrame> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        this.frames = frames.ToArray();
        if (this.frames.Length == 0)
        {
            throw new ArgumentException("At least one frozen display is required.", nameof(frames));
        }

        Bounds = CapturePixelRect.Union(this.frames.Select(frame => frame.Bounds));
    }

    public IReadOnlyList<FrozenDisplayFrame> Frames => frames;

    public CapturePixelRect Bounds { get; }

    /// <summary>
    /// Crops and stitches a physical-pixel region. Unoccupied virtual-desktop gaps are opaque black.
    /// </summary>
    public FrozenScreenshot Crop(CapturePixelRect selection)
    {
        if (!Bounds.Contains(selection))
        {
            throw new ArgumentOutOfRangeException(nameof(selection), "The crop must stay within the frozen desktop bounds.");
        }

        var stride = checked(selection.Width * 4);
        var output = new byte[checked(stride * selection.Height)];
        for (var offset = 3; offset < output.Length; offset += 4)
        {
            output[offset] = byte.MaxValue;
        }

        var copiedPixels = 0L;
        foreach (var frame in frames)
        {
            var intersection = selection.Intersect(frame.Bounds);
            if (intersection is not { } sourceRect)
            {
                continue;
            }

            var sourceX = sourceRect.Left - frame.Bounds.Left;
            var sourceY = sourceRect.Top - frame.Bounds.Top;
            var targetX = sourceRect.Left - selection.Left;
            var targetY = sourceRect.Top - selection.Top;
            var bytesPerRow = checked(sourceRect.Width * 4);
            var source = frame.Bgra.Span;
            for (var row = 0; row < sourceRect.Height; row++)
            {
                var sourceOffset = checked(((sourceY + row) * frame.Stride) + (sourceX * 4));
                var targetOffset = checked(((targetY + row) * stride) + (targetX * 4));
                source.Slice(sourceOffset, bytesPerRow).CopyTo(output.AsSpan(targetOffset, bytesPerRow));
            }
            copiedPixels += (long)sourceRect.Width * sourceRect.Height;
        }

        if (copiedPixels == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(selection), "No frozen display pixels cover the crop.");
        }

        return new FrozenScreenshot(selection.Width, selection.Height, stride, output);
    }
}
