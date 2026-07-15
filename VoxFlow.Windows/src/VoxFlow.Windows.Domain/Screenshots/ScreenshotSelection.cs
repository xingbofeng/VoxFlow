using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain.Screenshots;

public enum ScreenshotResizeHandle
{
    TopLeft,
    Top,
    TopRight,
    Left,
    Right,
    BottomLeft,
    Bottom,
    BottomRight,
}

public enum ScreenshotSelectionInteraction
{
    Idle,
    Creating,
    Moving,
    Resizing,
}

public enum ScreenshotSelectionCommand
{
    ToggleWindowSnap,
    FullDisplay,
    MoveLeft,
    MoveRight,
    MoveUp,
    MoveDown,
    Complete,
    DoubleClick,
    Cancel,
    RightClick,
}

public enum ScreenshotSelectionOutcome
{
    Continue,
    Completed,
    Cancelled,
}

public sealed record WindowTargetCandidate
{
    [JsonConstructor]
    public WindowTargetCandidate(long windowHandle, PixelRect bounds, int zOrder)
    {
        if (windowHandle == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(windowHandle));
        }
        if (bounds.IsEmpty)
        {
            throw new ArgumentOutOfRangeException(nameof(bounds));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(zOrder);

        WindowHandle = windowHandle;
        Bounds = bounds;
        ZOrder = zOrder;
    }

    public long WindowHandle { get; }

    public PixelRect Bounds { get; }

    public int ZOrder { get; }
}

public sealed record ScreenshotSelectionTransition(
    ScreenshotSelectionState State,
    ScreenshotSelectionOutcome Outcome,
    PixelRect? Region);

public sealed class ScreenshotSelectionState
{
    public const int MinimumRegionSize = 8;

    private readonly PixelPoint? interactionAnchor;
    private readonly PixelRect? interactionStartRegion;

    private ScreenshotSelectionState(
        ScreenshotDesktopLayout layout,
        PixelRect? region,
        WindowTargetCandidate? windowCandidate,
        bool isWindowSnapEnabled,
        ScreenshotSelectionInteraction interaction,
        PixelPoint? interactionAnchor,
        PixelRect? interactionStartRegion,
        ScreenshotResizeHandle? activeResizeHandle)
    {
        Layout = layout;
        Region = region;
        WindowCandidate = windowCandidate;
        IsWindowSnapEnabled = isWindowSnapEnabled;
        Interaction = interaction;
        this.interactionAnchor = interactionAnchor;
        this.interactionStartRegion = interactionStartRegion;
        ActiveResizeHandle = activeResizeHandle;
    }

    public ScreenshotDesktopLayout Layout { get; }

    public PixelRect? Region { get; }

    public WindowTargetCandidate? WindowCandidate { get; }

    public bool IsWindowSnapEnabled { get; }

    public ScreenshotSelectionInteraction Interaction { get; }

    public ScreenshotResizeHandle? ActiveResizeHandle { get; }

    public PixelRect? EffectiveRegion =>
        Region ?? (IsWindowSnapEnabled && WindowCandidate is not null
            ? WindowCandidate.Bounds.Intersection(Layout.VirtualBounds)
            : null);

    public bool HasValidRegion => IsValid(EffectiveRegion);

    public static ScreenshotSelectionState Create(ScreenshotDesktopLayout layout) => new(
        layout ?? throw new ArgumentNullException(nameof(layout)),
        region: null,
        windowCandidate: null,
        isWindowSnapEnabled: true,
        ScreenshotSelectionInteraction.Idle,
        interactionAnchor: null,
        interactionStartRegion: null,
        activeResizeHandle: null);

    public ScreenshotSelectionState WithRegion(PixelRect region)
    {
        if (!IsValid(region))
        {
            throw new ArgumentOutOfRangeException(nameof(region));
        }

        var clamped = region.ClampInside(Layout.VirtualBounds);
        return New(
            clamped,
            windowCandidate: null,
            Interaction: ScreenshotSelectionInteraction.Idle);
    }

    public ScreenshotSelectionState WithWindowCandidate(WindowTargetCandidate? candidate)
    {
        if (candidate is not null
            && !Layout.VirtualBounds.Intersects(candidate.Bounds))
        {
            throw new ArgumentOutOfRangeException(nameof(candidate));
        }

        return new ScreenshotSelectionState(
            Layout,
            Region,
            candidate,
            IsWindowSnapEnabled,
            Interaction,
            interactionAnchor,
            interactionStartRegion,
            ActiveResizeHandle);
    }

    public ScreenshotSelectionState BeginRegionDrag(PixelPoint point)
    {
        var clamped = ClampEndpoint(point);
        return new ScreenshotSelectionState(
            Layout,
            new PixelRect(clamped.X, clamped.Y, 0, 0),
            windowCandidate: null,
            IsWindowSnapEnabled,
            ScreenshotSelectionInteraction.Creating,
            clamped,
            interactionStartRegion: null,
            activeResizeHandle: null);
    }

    public ScreenshotSelectionState BeginMove(PixelPoint point)
    {
        var effective = EffectiveRegion;
        if (!IsValid(effective))
        {
            return this;
        }

        return new ScreenshotSelectionState(
            Layout,
            effective,
            windowCandidate: null,
            IsWindowSnapEnabled,
            ScreenshotSelectionInteraction.Moving,
            point,
            effective,
            activeResizeHandle: null);
    }

    public ScreenshotSelectionState BeginResize(ScreenshotResizeHandle handle)
    {
        if (!Enum.IsDefined(handle))
        {
            throw new ArgumentOutOfRangeException(nameof(handle));
        }
        var effective = EffectiveRegion;
        if (!IsValid(effective))
        {
            return this;
        }

        return new ScreenshotSelectionState(
            Layout,
            effective,
            windowCandidate: null,
            IsWindowSnapEnabled,
            ScreenshotSelectionInteraction.Resizing,
            interactionAnchor: null,
            effective,
            handle);
    }

    public ScreenshotSelectionState UpdatePointer(PixelPoint point)
    {
        switch (Interaction)
        {
            case ScreenshotSelectionInteraction.Creating:
            {
                var current = ClampEndpoint(point);
                var created = PixelRect.FromPoints(interactionAnchor!.Value, current);
                return Copy(region: created);
            }
            case ScreenshotSelectionInteraction.Moving:
            {
                var start = interactionStartRegion!.Value;
                var anchor = interactionAnchor!.Value;
                var deltaX = ClampToInt((long)point.X - anchor.X);
                var deltaY = ClampToInt((long)point.Y - anchor.Y);
                var moved = TranslateClamped(start, deltaX, deltaY, Layout.VirtualBounds);
                return Copy(region: moved);
            }
            case ScreenshotSelectionInteraction.Resizing:
            {
                var resized = ResizeRegion(
                    interactionStartRegion!.Value,
                    ActiveResizeHandle!.Value,
                    ClampEndpoint(point),
                    Layout.VirtualBounds);
                return Copy(region: resized);
            }
            case ScreenshotSelectionInteraction.Idle:
            default:
                return this;
        }
    }

    public ScreenshotSelectionState EndPointer()
    {
        var region = IsValid(Region) ? Region : null;
        return new ScreenshotSelectionState(
            Layout,
            region,
            WindowCandidate,
            IsWindowSnapEnabled,
            ScreenshotSelectionInteraction.Idle,
            interactionAnchor: null,
            interactionStartRegion: null,
            activeResizeHandle: null);
    }

    public ScreenshotSelectionTransition Apply(
        ScreenshotSelectionCommand command,
        PixelPoint? pointer)
    {
        if (!Enum.IsDefined(command))
        {
            throw new ArgumentOutOfRangeException(nameof(command));
        }

        switch (command)
        {
            case ScreenshotSelectionCommand.ToggleWindowSnap:
                return Continue(new ScreenshotSelectionState(
                    Layout,
                    Region,
                    WindowCandidate,
                    !IsWindowSnapEnabled,
                    ScreenshotSelectionInteraction.Idle,
                    interactionAnchor: null,
                    interactionStartRegion: null,
                    activeResizeHandle: null));
            case ScreenshotSelectionCommand.FullDisplay:
            {
                var display = pointer is null
                    ? Layout.PrimaryDisplay
                    : Layout.DisplayAt(pointer.Value) ?? Layout.PrimaryDisplay;
                return Continue(WithRegion(display.Bounds));
            }
            case ScreenshotSelectionCommand.MoveLeft:
                return Continue(Nudge(-1, 0));
            case ScreenshotSelectionCommand.MoveRight:
                return Continue(Nudge(1, 0));
            case ScreenshotSelectionCommand.MoveUp:
                return Continue(Nudge(0, -1));
            case ScreenshotSelectionCommand.MoveDown:
                return Continue(Nudge(0, 1));
            case ScreenshotSelectionCommand.Complete:
            case ScreenshotSelectionCommand.DoubleClick:
            {
                if (command == ScreenshotSelectionCommand.DoubleClick
                    && (pointer is null || EffectiveRegion?.Contains(pointer.Value) != true))
                {
                    return Continue(this);
                }
                var committed = CommitEffectiveRegion();
                return committed.HasValidRegion
                    ? new ScreenshotSelectionTransition(
                        committed,
                        ScreenshotSelectionOutcome.Completed,
                        committed.Region)
                    : Continue(committed);
            }
            case ScreenshotSelectionCommand.Cancel:
            case ScreenshotSelectionCommand.RightClick:
                return new ScreenshotSelectionTransition(
                    this,
                    ScreenshotSelectionOutcome.Cancelled,
                    Region: null);
            default:
                throw new ArgumentOutOfRangeException(nameof(command));
        }
    }

    private ScreenshotSelectionState Nudge(int deltaX, int deltaY)
    {
        var effective = EffectiveRegion;
        if (!IsValid(effective))
        {
            return this;
        }

        return New(
            TranslateClamped(effective!.Value, deltaX, deltaY, Layout.VirtualBounds),
            windowCandidate: null,
            Interaction: ScreenshotSelectionInteraction.Idle);
    }

    private ScreenshotSelectionState CommitEffectiveRegion()
    {
        var effective = EffectiveRegion;
        return IsValid(effective)
            ? New(
                effective!.Value.ClampInside(Layout.VirtualBounds),
                windowCandidate: null,
                Interaction: ScreenshotSelectionInteraction.Idle)
            : this;
    }

    private ScreenshotSelectionTransition Continue(ScreenshotSelectionState state) => new(
        state,
        ScreenshotSelectionOutcome.Continue,
        state.EffectiveRegion);

    private ScreenshotSelectionState New(
        PixelRect? region,
        WindowTargetCandidate? windowCandidate,
        ScreenshotSelectionInteraction Interaction) => new(
            Layout,
            region,
            windowCandidate,
            IsWindowSnapEnabled,
            Interaction,
            interactionAnchor: null,
            interactionStartRegion: null,
            activeResizeHandle: null);

    private ScreenshotSelectionState Copy(PixelRect region) => new(
        Layout,
        region,
        WindowCandidate,
        IsWindowSnapEnabled,
        Interaction,
        interactionAnchor,
        interactionStartRegion,
        ActiveResizeHandle);

    private PixelPoint ClampEndpoint(PixelPoint point) => new(
        Math.Clamp(point.X, Layout.VirtualBounds.Left, Layout.VirtualBounds.Right),
        Math.Clamp(point.Y, Layout.VirtualBounds.Top, Layout.VirtualBounds.Bottom));

    private static PixelRect TranslateClamped(
        PixelRect rect,
        int deltaX,
        int deltaY,
        PixelRect bounds)
    {
        var minimumX = bounds.Left - (long)rect.Left;
        var maximumX = bounds.Right - (long)rect.Right;
        var minimumY = bounds.Top - (long)rect.Top;
        var maximumY = bounds.Bottom - (long)rect.Bottom;
        var clampedX = Math.Clamp((long)deltaX, minimumX, maximumX);
        var clampedY = Math.Clamp((long)deltaY, minimumY, maximumY);
        return rect.Translate(ClampToInt(clampedX), ClampToInt(clampedY));
    }

    private static PixelRect ResizeRegion(
        PixelRect original,
        ScreenshotResizeHandle handle,
        PixelPoint point,
        PixelRect bounds)
    {
        long left = original.Left;
        long top = original.Top;
        long right = original.Right;
        long bottom = original.Bottom;
        var movesLeft = handle is
            ScreenshotResizeHandle.TopLeft
            or ScreenshotResizeHandle.Left
            or ScreenshotResizeHandle.BottomLeft;
        var movesRight = handle is
            ScreenshotResizeHandle.TopRight
            or ScreenshotResizeHandle.Right
            or ScreenshotResizeHandle.BottomRight;
        var movesTop = handle is
            ScreenshotResizeHandle.TopLeft
            or ScreenshotResizeHandle.Top
            or ScreenshotResizeHandle.TopRight;
        var movesBottom = handle is
            ScreenshotResizeHandle.BottomLeft
            or ScreenshotResizeHandle.Bottom
            or ScreenshotResizeHandle.BottomRight;

        if (movesLeft)
        {
            left = point.X;
        }
        if (movesRight)
        {
            right = point.X;
        }
        if (movesTop)
        {
            top = point.Y;
        }
        if (movesBottom)
        {
            bottom = point.Y;
        }

        if (left > right)
        {
            (left, right) = (right, left);
        }
        if (top > bottom)
        {
            (top, bottom) = (bottom, top);
        }

        if (right - left < MinimumRegionSize)
        {
            if (movesLeft && !movesRight)
            {
                left = right - MinimumRegionSize;
            }
            else
            {
                right = left + MinimumRegionSize;
            }
        }
        if (bottom - top < MinimumRegionSize)
        {
            if (movesTop && !movesBottom)
            {
                top = bottom - MinimumRegionSize;
            }
            else
            {
                bottom = top + MinimumRegionSize;
            }
        }

        var width = right - left;
        var height = bottom - top;
        if (left < bounds.Left)
        {
            left = bounds.Left;
            right = left + width;
        }
        if (right > bounds.Right)
        {
            right = bounds.Right;
            left = right - width;
        }
        if (top < bounds.Top)
        {
            top = bounds.Top;
            bottom = top + height;
        }
        if (bottom > bounds.Bottom)
        {
            bottom = bounds.Bottom;
            top = bottom - height;
        }

        return PixelRect.FromEdges(left, top, right, bottom);
    }

    private static bool IsValid(PixelRect? region) =>
        region is { Width: >= MinimumRegionSize, Height: >= MinimumRegionSize };

    private static int ClampToInt(long value) =>
        value is >= int.MinValue and <= int.MaxValue
            ? (int)value
            : throw new OverflowException("Selection movement exceeds Int32 bounds.");
}
