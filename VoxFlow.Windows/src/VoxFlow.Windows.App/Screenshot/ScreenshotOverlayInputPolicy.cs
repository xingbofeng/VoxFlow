using System.Windows.Input;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Screenshot;

internal enum ScreenshotCopyShortcutAction
{
    Ignore,
    CompleteSelection,
    CopySelectedAnnotations,
}

internal static class ScreenshotOverlayInputPolicy
{
    private const int WindowClickDragThresholdPixels = 2;

    public static ScreenshotCopyShortcutAction ResolveCopyShortcut(
        bool hasValidRegion,
        int selectedAnnotationCount)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(selectedAnnotationCount);
        if (selectedAnnotationCount > 0)
        {
            return ScreenshotCopyShortcutAction.CopySelectedAnnotations;
        }
        return hasValidRegion
            ? ScreenshotCopyShortcutAction.CompleteSelection
            : ScreenshotCopyShortcutAction.Ignore;
    }

    public static bool ShouldForwardFromTextEditor(Key key) => key == Key.Escape;

    public static bool ShouldBeginFreeRegionFromWindowCandidate(
        PixelPoint start,
        PixelPoint current) =>
        Math.Abs((long)current.X - start.X) >= WindowClickDragThresholdPixels
        || Math.Abs((long)current.Y - start.Y) >= WindowClickDragThresholdPixels;

    public static bool ShouldClearSelectionAfterCommit(ScreenshotTool tool) => tool is
        ScreenshotTool.Pen
        or ScreenshotTool.Ellipse
        or ScreenshotTool.Rectangle
        or ScreenshotTool.Arrow
        or ScreenshotTool.DotMarker
        or ScreenshotTool.NumberedMarker
        or ScreenshotTool.Mosaic;
}
