namespace VoxFlow.Windows.Domain.Screenshots;

/// <summary>
/// Pure source-pixel annotation editor. Pointer previews stay outside this type;
/// one public mutation represents one completed user command.
/// </summary>
public sealed class ScreenshotAnnotationEditor
{
    private const double PasteOffset = 15;
    private const double MinimumResizeSize = 2;
    private readonly Stack<AnnotationEditCommand> undo = new();
    private readonly Stack<AnnotationEditCommand> redo = new();
    private IReadOnlyList<ScreenshotAnnotation> clipboard = [];

    public ScreenshotAnnotationEditor(ScreenshotDocument document)
    {
        Document = document ?? throw new ArgumentNullException(nameof(document));
        Selection = AnnotationSelection.Empty;
        CurrentStyle = AnnotationStyle.Default;
        CurrentTextStyle = TextAnnotationStyle.Default;
    }

    public ScreenshotDocument Document { get; private set; }

    public AnnotationSelection Selection { get; private set; }

    public AnnotationStyle CurrentStyle { get; private set; }

    public TextAnnotationStyle CurrentTextStyle { get; private set; }

    public bool CanUndo => undo.Count > 0;

    public bool CanRedo => redo.Count > 0;

    public bool CanPaste => clipboard.Count > 0;

    public SourceRect? SelectedBounds => BoundsFor(SelectedAnnotations());

    public SourceRect? SelectedResizableBounds => BoundsFor(
        SelectedAnnotations()
            .Where(static annotation => annotation.Kind != AnnotationKind.Mosaic)
            .ToArray());

    public void ResizeCanvas(PixelSize canvasSize)
    {
        if (Document.CanvasSize == canvasSize)
        {
            return;
        }

        Document = new ScreenshotDocument(
            Document.Id,
            canvasSize,
            Document.Annotations,
            checked(Document.Revision + 1));
        undo.Clear();
        redo.Clear();
    }

    public void Add(ScreenshotAnnotation annotation)
    {
        ArgumentNullException.ThrowIfNull(annotation);
        if (Document.Annotations.Any(value => value.Id == annotation.Id))
        {
            throw new ArgumentException("The annotation identifier already exists.", nameof(annotation));
        }

        var clamped = ClampAnnotation(annotation);
        Commit(
            [.. Document.Annotations, clamped],
            new AnnotationSelection([clamped.Id]));
    }

    public bool TryAddGesture(
        ScreenshotTool tool,
        SourcePoint start,
        IReadOnlyList<SourcePoint> points,
        string? text)
    {
        var nextNumber = Document.Annotations.Count(
            static value => value.Kind == AnnotationKind.NumberedMarker) + 1;
        if (!ScreenshotAnnotationFactory.TryCreate(
                tool,
                start,
                points,
                text,
                nextNumber,
                out var annotation,
                CurrentStyle,
                CurrentTextStyle))
        {
            return false;
        }

        Add(annotation!);
        return true;
    }

    public void Select(IReadOnlyList<Guid> ids)
    {
        ArgumentNullException.ThrowIfNull(ids);
        var available = Document.Annotations.Select(static value => value.Id).ToHashSet();
        if (ids.Any(id => !available.Contains(id)))
        {
            throw new ArgumentOutOfRangeException(nameof(ids));
        }
        Selection = new AnnotationSelection(ids);
        SynchronizeCurrentStyles(ids.LastOrDefault());
    }

    public void SelectAt(SourcePoint point, bool extend)
    {
        var hit = AnnotationHitTester.HitTest(Document.Annotations, point);
        if (hit is null)
        {
            if (!extend)
            {
                Selection = AnnotationSelection.Empty;
            }
            return;
        }

        var ids = Selection.Ids.ToList();
        if (!extend)
        {
            ids = [hit.Value];
        }
        else if (ids.Remove(hit.Value))
        {
            // Shift-click toggles an already-selected annotation off.
        }
        else
        {
            ids.Add(hit.Value);
        }
        Selection = new AnnotationSelection(ids);
        SynchronizeCurrentStyles(ids.Contains(hit.Value) ? hit.Value : ids.LastOrDefault());
    }

    public void SelectIntersecting(SourceRect rect, bool extend)
    {
        var hits = Document.Annotations
            .Where(annotation => annotation.Bounds.Intersects(rect))
            .Select(static annotation => annotation.Id)
            .ToList();
        if (extend)
        {
            hits = Selection.Ids.Concat(hits).Distinct().ToList();
        }
        Selection = new AnnotationSelection(hits);
        SynchronizeCurrentStyles(hits.LastOrDefault());
    }

    /// <summary>
    /// Replaces the content of one existing text annotation as a single undoable edit.
    /// Empty drafts and unchanged content leave the document untouched.
    /// </summary>
    public bool UpdateText(Guid id, string? content)
    {
        if (id == Guid.Empty)
        {
            throw new ArgumentException("A text annotation identifier is required.", nameof(id));
        }
        var current = Document.Annotations
            .OfType<TextAnnotation>()
            .FirstOrDefault(annotation => annotation.Id == id);
        if (current is null)
        {
            throw new ArgumentOutOfRangeException(nameof(id));
        }
        if (string.IsNullOrWhiteSpace(content))
        {
            return false;
        }

        var normalized = content.Trim();
        if (string.Equals(current.Content, normalized, StringComparison.Ordinal))
        {
            return false;
        }

        var updated = ClampAnnotation(new TextAnnotation(
            current.Id,
            current.Position,
            normalized,
            current.Style));
        Commit(
            Document.Annotations
                .Select(annotation => annotation.Id == id ? updated : annotation)
                .ToArray(),
            new AnnotationSelection([id]));
        return true;
    }

    public void MoveSelection(SourceVector requestedOffset)
    {
        var preview = CalculateMovePreview(requestedOffset);
        if (!preview.Changed)
        {
            return;
        }
        Commit(preview.Annotations, Selection);
    }

    public IReadOnlyList<ScreenshotAnnotation> PreviewMoveSelection(SourceVector requestedOffset) =>
        CalculateMovePreview(requestedOffset).Annotations;

    public void ResizeSelection(AnnotationResizeHandle handle, SourcePoint point)
    {
        var preview = CalculateResizePreview(handle, point);
        if (!preview.Changed)
        {
            return;
        }
        Commit(preview.Annotations, Selection);
    }

    public IReadOnlyList<ScreenshotAnnotation> PreviewResizeSelection(
        AnnotationResizeHandle handle,
        SourcePoint point) => CalculateResizePreview(handle, point).Annotations;

    public void DeleteSelection()
    {
        if (Selection.Ids.Count == 0)
        {
            return;
        }
        var selected = Selection.Ids.ToHashSet();
        Commit(
            Document.Annotations.Where(annotation => !selected.Contains(annotation.Id)).ToArray(),
            AnnotationSelection.Empty);
    }

    public void Clear()
    {
        if (Document.Annotations.Count == 0)
        {
            return;
        }
        Commit([], AnnotationSelection.Empty);
    }

    public void CopySelection()
    {
        var selected = Selection.Ids.ToHashSet();
        clipboard = Array.AsReadOnly(Document.Annotations
            .Where(annotation => selected.Contains(annotation.Id))
            .ToArray());
    }

    public bool Paste()
    {
        if (clipboard.Count == 0)
        {
            return false;
        }

        var nextNumber = Document.Annotations.Count(
            static annotation => annotation.Kind == AnnotationKind.NumberedMarker) + 1;
        var duplicates = new List<ScreenshotAnnotation>(clipboard.Count);
        foreach (var annotation in clipboard)
        {
            int? markerNumber = annotation.Kind == AnnotationKind.NumberedMarker
                ? nextNumber++
                : null;
            duplicates.Add(annotation.Duplicate(
                Guid.NewGuid(),
                new SourceVector(PasteOffset, PasteOffset),
                markerNumber));
        }

        var bounds = BoundsFor(duplicates)!;
        var correction = ClampOffset(bounds.Value, default, Document.CanvasBounds);
        if (correction != default)
        {
            duplicates = duplicates
                .Select(annotation => annotation.MoveBy(correction))
                .ToList();
        }

        Commit(
            [.. Document.Annotations, .. duplicates],
            new AnnotationSelection(duplicates.Select(static value => value.Id).ToArray()));
        return true;
    }

    public bool DuplicateSelection()
    {
        if (Selection.Ids.Count == 0)
        {
            return false;
        }
        CopySelection();
        return Paste();
    }

    public void ApplyColor(AnnotationColor color)
    {
        if (!AnnotationPalette.Colors.Contains(color))
        {
            throw new ArgumentOutOfRangeException(nameof(color));
        }
        CurrentStyle = CurrentStyle.WithColor(color);
        CurrentTextStyle = CurrentTextStyle.WithColor(color);
        ApplyToSelection(annotation => annotation.WithColor(color));
    }

    public void ApplyLineWidth(double lineWidth)
    {
        if (!AnnotationPalette.LineWidths.Contains(lineWidth))
        {
            throw new ArgumentOutOfRangeException(nameof(lineWidth));
        }
        CurrentStyle = CurrentStyle.WithLineWidth(lineWidth);
        ApplyToSelection(annotation => annotation.WithLineWidth(lineWidth));
    }

    public void ApplyFontSize(double fontSize)
    {
        if (!AnnotationPalette.FontSizes.Contains(fontSize))
        {
            throw new ArgumentOutOfRangeException(nameof(fontSize));
        }
        CurrentTextStyle = CurrentTextStyle.WithFontSize(fontSize);
        ApplyToSelection(annotation => annotation.WithFontSize(fontSize));
    }

    public void Undo()
    {
        if (!undo.TryPop(out var command))
        {
            return;
        }
        redo.Push(command);
        Restore(command.Before);
    }

    public void Redo()
    {
        if (!redo.TryPop(out var command))
        {
            return;
        }
        undo.Push(command);
        Restore(command.After);
    }

    private void ApplyToSelection(Func<ScreenshotAnnotation, ScreenshotAnnotation> update)
    {
        if (Selection.Ids.Count == 0)
        {
            return;
        }
        var selected = Selection.Ids.ToHashSet();
        var changed = false;
        var annotations = Document.Annotations.Select(annotation =>
        {
            if (!selected.Contains(annotation.Id))
            {
                return annotation;
            }
            var updated = update(annotation);
            changed |= !ReferenceEquals(updated, annotation);
            return updated;
        }).ToArray();
        if (changed)
        {
            Commit(annotations, Selection);
        }
    }

    private ScreenshotAnnotation ClampAnnotation(ScreenshotAnnotation annotation)
    {
        var offset = ClampOffset(annotation.Bounds, default, Document.CanvasBounds);
        return offset == default ? annotation : annotation.MoveBy(offset);
    }

    private void Commit(
        IReadOnlyList<ScreenshotAnnotation> annotations,
        AnnotationSelection selection)
    {
        var before = CurrentSnapshot();
        var nextDocument = Document.WithAnnotations(annotations);
        var after = new EditorSnapshot(nextDocument, selection);
        undo.Push(new AnnotationEditCommand(before, after));
        redo.Clear();
        Restore(after);
    }

    private EditorSnapshot CurrentSnapshot() => new(Document, Selection);

    private void Restore(EditorSnapshot snapshot)
    {
        Document = snapshot.Document;
        Selection = snapshot.Selection;
        SynchronizeCurrentStyles(Selection.Ids.LastOrDefault());
    }

    private void SynchronizeCurrentStyles(Guid preferredId)
    {
        if (preferredId == Guid.Empty
            || !Selection.Contains(preferredId))
        {
            return;
        }
        var annotation = Document.Annotations.FirstOrDefault(value => value.Id == preferredId);
        switch (annotation)
        {
            case TextAnnotation text:
                CurrentStyle = CurrentStyle.WithColor(text.Style.Color);
                CurrentTextStyle = text.Style;
                break;
            case PenAnnotation pen:
                SynchronizeStrokeStyle(pen.Style);
                break;
            case EllipseAnnotation ellipse:
                SynchronizeStrokeStyle(ellipse.Style);
                break;
            case RectangleAnnotation rectangle:
                SynchronizeStrokeStyle(rectangle.Style);
                break;
            case ArrowAnnotation arrow:
                SynchronizeStrokeStyle(arrow.Style);
                break;
            case DotMarkerAnnotation marker:
                SynchronizeStrokeStyle(marker.Style);
                break;
            case NumberedMarkerAnnotation marker:
                SynchronizeStrokeStyle(marker.Style);
                break;
        }
    }

    private void SynchronizeStrokeStyle(AnnotationStyle style)
    {
        CurrentStyle = style;
        CurrentTextStyle = CurrentTextStyle.WithColor(style.Color);
    }

    private IReadOnlyList<ScreenshotAnnotation> SelectedAnnotations()
    {
        var selected = Selection.Ids.ToHashSet();
        return Document.Annotations
            .Where(annotation => selected.Contains(annotation.Id))
            .ToArray();
    }

    private AnnotationPreview CalculateMovePreview(SourceVector requestedOffset)
    {
        var bounds = SelectedBounds;
        if (bounds is null)
        {
            return new AnnotationPreview(Document.Annotations, Changed: false);
        }

        var offset = ClampOffset(bounds.Value, requestedOffset, Document.CanvasBounds);
        if (offset == default)
        {
            return new AnnotationPreview(Document.Annotations, Changed: false);
        }

        var selected = Selection.Ids.ToHashSet();
        var updated = Document.Annotations
            .Select(annotation => selected.Contains(annotation.Id)
                ? annotation.MoveBy(offset)
                : annotation)
            .ToArray();
        return new AnnotationPreview(updated, Changed: true);
    }

    private AnnotationPreview CalculateResizePreview(
        AnnotationResizeHandle handle,
        SourcePoint point)
    {
        if (!Enum.IsDefined(handle))
        {
            throw new ArgumentOutOfRangeException(nameof(handle));
        }
        var source = SelectedResizableBounds;
        if (source is null)
        {
            return new AnnotationPreview(Document.Annotations, Changed: false);
        }

        var target = ResizeBounds(source.Value, handle, point, Document.CanvasBounds);
        if (target == source.Value)
        {
            return new AnnotationPreview(Document.Annotations, Changed: false);
        }

        var selected = Selection.Ids.ToHashSet();
        var updated = Document.Annotations
            .Select(annotation => selected.Contains(annotation.Id)
                && annotation.Kind != AnnotationKind.Mosaic
                    ? annotation.Transform(source.Value, target)
                    : annotation)
            .ToArray();
        return new AnnotationPreview(updated, Changed: true);
    }

    private static SourceRect? BoundsFor(IReadOnlyList<ScreenshotAnnotation> annotations)
    {
        if (annotations.Count == 0)
        {
            return null;
        }
        return annotations
            .Select(static annotation => annotation.Bounds)
            .Aggregate(static (current, next) => current.Union(next));
    }

    private readonly record struct AnnotationPreview(
        IReadOnlyList<ScreenshotAnnotation> Annotations,
        bool Changed);

    private static SourceVector ClampOffset(
        SourceRect bounds,
        SourceVector requested,
        SourceRect container)
    {
        var minimumX = container.Left - bounds.Left;
        var maximumX = container.Right - bounds.Right;
        var minimumY = container.Top - bounds.Top;
        var maximumY = container.Bottom - bounds.Bottom;
        var x = minimumX > maximumX
            ? minimumX
            : Math.Clamp(requested.X, minimumX, maximumX);
        var y = minimumY > maximumY
            ? minimumY
            : Math.Clamp(requested.Y, minimumY, maximumY);
        return new SourceVector(x, y);
    }

    private static SourceRect ResizeBounds(
        SourceRect source,
        AnnotationResizeHandle handle,
        SourcePoint point,
        SourceRect container)
    {
        var left = source.Left;
        var top = source.Top;
        var right = source.Right;
        var bottom = source.Bottom;
        var movesLeft = handle is
            AnnotationResizeHandle.TopLeft
            or AnnotationResizeHandle.Left
            or AnnotationResizeHandle.BottomLeft;
        var movesRight = handle is
            AnnotationResizeHandle.TopRight
            or AnnotationResizeHandle.Right
            or AnnotationResizeHandle.BottomRight;
        var movesTop = handle is
            AnnotationResizeHandle.TopLeft
            or AnnotationResizeHandle.Top
            or AnnotationResizeHandle.TopRight;
        var movesBottom = handle is
            AnnotationResizeHandle.BottomLeft
            or AnnotationResizeHandle.Bottom
            or AnnotationResizeHandle.BottomRight;

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
        if (right - left < MinimumResizeSize)
        {
            if (movesLeft && !movesRight)
            {
                left = right - MinimumResizeSize;
            }
            else
            {
                right = left + MinimumResizeSize;
            }
        }
        if (bottom - top < MinimumResizeSize)
        {
            if (movesTop && !movesBottom)
            {
                top = bottom - MinimumResizeSize;
            }
            else
            {
                bottom = top + MinimumResizeSize;
            }
        }

        left = Math.Clamp(left, container.Left, container.Right - MinimumResizeSize);
        top = Math.Clamp(top, container.Top, container.Bottom - MinimumResizeSize);
        right = Math.Clamp(right, left + MinimumResizeSize, container.Right);
        bottom = Math.Clamp(bottom, top + MinimumResizeSize, container.Bottom);
        return new SourceRect(left, top, right - left, bottom - top);
    }

    private sealed record EditorSnapshot(
        ScreenshotDocument Document,
        AnnotationSelection Selection);

    private sealed record AnnotationEditCommand(
        EditorSnapshot Before,
        EditorSnapshot After);
}
