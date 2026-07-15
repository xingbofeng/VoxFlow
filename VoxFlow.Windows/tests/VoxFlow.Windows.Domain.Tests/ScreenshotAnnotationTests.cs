using System.Text.Json;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class ScreenshotAnnotationTests
{
    [Fact]
    public void Resizing_canvas_preserves_annotations_and_prevents_stale_render_dimensions()
    {
        var editor = new ScreenshotAnnotationEditor(new ScreenshotDocument(
            Guid.NewGuid(),
            new PixelSize(320, 200),
            [],
            revision: 0));
        Assert.True(editor.TryAddGesture(
            ScreenshotTool.Ellipse,
            new SourcePoint(20, 20),
            [new SourcePoint(120, 80)],
            text: null));
        var annotation = Assert.Single(editor.Document.Annotations);

        editor.ResizeCanvas(new PixelSize(640, 480));

        Assert.Equal(new PixelSize(640, 480), editor.Document.CanvasSize);
        Assert.Same(annotation, Assert.Single(editor.Document.Annotations));
        Assert.False(editor.CanUndo);
        Assert.False(editor.CanRedo);
    }

    [Fact]
    public void Every_annotation_type_round_trips_with_stable_discriminators()
    {
        var style = AnnotationStyle.Default;
        ScreenshotAnnotation[] annotations =
        [
            new PenAnnotation(Guid.NewGuid(), [new SourcePoint(1, 1), new SourcePoint(5, 5)], style),
            new EllipseAnnotation(Guid.NewGuid(), new SourceRect(10, 20, 30, 40), style),
            new RectangleAnnotation(Guid.NewGuid(), new SourceRect(20, 30, 40, 50), style),
            new ArrowAnnotation(Guid.NewGuid(), new SourcePoint(1, 2), new SourcePoint(30, 40), style),
            new DotMarkerAnnotation(Guid.NewGuid(), new SourcePoint(50, 60), 6, style),
            new NumberedMarkerAnnotation(Guid.NewGuid(), new SourcePoint(70, 80), 3, 9, style),
            new TextAnnotation(Guid.NewGuid(), new SourcePoint(10, 10), "line one\nline two", TextAnnotationStyle.Default),
            new MosaicAnnotation(Guid.NewGuid(), [new SourcePoint(4, 4), new SourcePoint(20, 20)], 40, 8),
        ];
        var document = new ScreenshotDocument(
            Guid.NewGuid(),
            new PixelSize(320, 240),
            annotations,
            revision: 7);

        var json = JsonSerializer.Serialize(document, DomainJson.Options);
        var restored = Assert.IsType<ScreenshotDocument>(
            JsonSerializer.Deserialize<ScreenshotDocument>(json, DomainJson.Options));

        Assert.Equal(8, restored.Annotations.Count);
        Assert.Collection(
            restored.Annotations,
            value => Assert.IsType<PenAnnotation>(value),
            value => Assert.IsType<EllipseAnnotation>(value),
            value => Assert.IsType<RectangleAnnotation>(value),
            value => Assert.IsType<ArrowAnnotation>(value),
            value => Assert.IsType<DotMarkerAnnotation>(value),
            value => Assert.IsType<NumberedMarkerAnnotation>(value),
            value => Assert.IsType<TextAnnotation>(value),
            value => Assert.IsType<MosaicAnnotation>(value));
        Assert.Contains("\"$type\":\"pen\"", json, StringComparison.Ordinal);
        Assert.Equal(7, restored.Revision);
    }

    [Fact]
    public void Tool_factory_enforces_mac_minimum_geometry_sampling_and_defaults()
    {
        Assert.False(ScreenshotAnnotationFactory.TryCreate(
            ScreenshotTool.Rectangle,
            new SourcePoint(10, 10),
            [new SourcePoint(11, 11)],
            null,
            1,
            out _));
        Assert.False(ScreenshotAnnotationFactory.TryCreate(
            ScreenshotTool.Arrow,
            new SourcePoint(0, 0),
            [new SourcePoint(3, 3)],
            null,
            1,
            out _));
        Assert.False(ScreenshotAnnotationFactory.TryCreate(
            ScreenshotTool.Text,
            new SourcePoint(5, 5),
            [],
            "   ",
            1,
            out _));

        Assert.True(ScreenshotAnnotationFactory.TryCreate(
            ScreenshotTool.Pen,
            new SourcePoint(0, 0),
            [
                new SourcePoint(1, 0),
                new SourcePoint(2, 0),
                new SourcePoint(2.5, 0),
                new SourcePoint(5, 0),
            ],
            null,
            1,
            out var pen));
        Assert.Equal(3, Assert.IsType<PenAnnotation>(pen).Points.Count);

        Assert.True(ScreenshotAnnotationFactory.TryCreate(
            ScreenshotTool.Mosaic,
            new SourcePoint(10, 10),
            [new SourcePoint(12, 10), new SourcePoint(14, 10)],
            null,
            1,
            out var mosaic));
        var mosaicValue = Assert.IsType<MosaicAnnotation>(mosaic);
        Assert.Equal(40, mosaicValue.BrushSize);
        Assert.Equal(8, mosaicValue.BlockSize);
    }

    [Theory]
    [InlineData(ScreenshotTool.Ellipse, AnnotationKind.Ellipse)]
    [InlineData(ScreenshotTool.Rectangle, AnnotationKind.Rectangle)]
    [InlineData(ScreenshotTool.Arrow, AnnotationKind.Arrow)]
    [InlineData(ScreenshotTool.DotMarker, AnnotationKind.DotMarker)]
    [InlineData(ScreenshotTool.NumberedMarker, AnnotationKind.NumberedMarker)]
    [InlineData(ScreenshotTool.Text, AnnotationKind.Text)]
    public void Shape_marker_and_text_tools_create_hit_testable_annotations_with_defaults(
        ScreenshotTool tool,
        AnnotationKind expectedKind)
    {
        var start = new SourcePoint(40, 40);
        var points = tool is ScreenshotTool.DotMarker
            or ScreenshotTool.NumberedMarker
            or ScreenshotTool.Text
                ? Array.Empty<SourcePoint>()
                : [new SourcePoint(80, 80)];

        Assert.True(ScreenshotAnnotationFactory.TryCreate(
            tool,
            start,
            points,
            tool == ScreenshotTool.Text ? "hello" : null,
            nextNumber: 4,
            out var annotation));

        Assert.Equal(expectedKind, annotation!.Kind);
        Assert.Equal(annotation.Id, AnnotationHitTester.HitTest([annotation], start));
        if (annotation is DotMarkerAnnotation dot)
        {
            Assert.Equal(6, dot.Radius);
        }
        if (annotation is NumberedMarkerAnnotation numbered)
        {
            Assert.Equal(9, numbered.Radius);
            Assert.Equal(4, numbered.Number);
        }
    }

    [Fact]
    public void Text_draft_matches_inline_editor_dimensions_and_cancel_commit_semantics()
    {
        var shortDraft = new TextAnnotationDraft(
            new SourcePoint(10, 10),
            "a",
            TextAnnotationStyle.Default);
        var longDraft = new TextAnnotationDraft(
            new SourcePoint(10, 10),
            new string('a', 100),
            TextAnnotationStyle.Default);
        var cancelled = new TextAnnotationDraft(
            new SourcePoint(10, 10),
            "  ",
            TextAnnotationStyle.Default);

        Assert.Equal(80, shortDraft.Width);
        Assert.Equal(220, longDraft.Width);
        Assert.Equal(28, TextAnnotationDraft.Height);
        Assert.False(cancelled.TryCommit(out _));
        Assert.True(shortDraft.TryCommit(out var annotation));
        Assert.Equal(14, annotation!.Style.FontSize);
    }

    [Fact]
    public void Marker_numbering_uses_existing_numbered_element_count()
    {
        var editor = CreateEditor();
        editor.Add(new NumberedMarkerAnnotation(
            Guid.NewGuid(), new SourcePoint(20, 20), 1, 9, AnnotationStyle.Default));
        editor.Add(new NumberedMarkerAnnotation(
            Guid.NewGuid(), new SourcePoint(40, 40), 2, 9, AnnotationStyle.Default));
        editor.Select([editor.Document.Annotations[1].Id]);
        editor.DeleteSelection();

        Assert.True(editor.TryAddGesture(
            ScreenshotTool.NumberedMarker,
            new SourcePoint(60, 60),
            [],
            text: null));

        var marker = Assert.IsType<NumberedMarkerAnnotation>(editor.Document.Annotations[^1]);
        Assert.Equal(2, marker.Number);
        Assert.Equal(9, marker.Radius);
    }

    [Fact]
    public void Hit_testing_multiselect_move_resize_and_delete_are_document_clamped_and_grouped()
    {
        var editor = CreateEditor();
        var rectangle = new RectangleAnnotation(
            Guid.NewGuid(), new SourceRect(10, 10, 40, 30), AnnotationStyle.Default);
        var text = new TextAnnotation(
            Guid.NewGuid(), new SourcePoint(80, 20), "hello", TextAnnotationStyle.Default);
        editor.Add(rectangle);
        editor.Add(text);

        editor.SelectAt(new SourcePoint(15, 15), extend: false);
        editor.SelectAt(new SourcePoint(85, 25), extend: true);
        Assert.Equal(2, editor.Selection.Ids.Count);
        Assert.Equal(new SourceRect(10, 10, 112, 30), editor.SelectedBounds);

        editor.MoveSelection(new SourceVector(-100, -100));
        Assert.Equal(0, editor.SelectedBounds!.Value.Left, 6);
        Assert.Equal(0, editor.SelectedBounds.Value.Top, 6);

        editor.ResizeSelection(
            AnnotationResizeHandle.BottomRight,
            new SourcePoint(250, 180));
        Assert.True(editor.SelectedBounds.Value.Right <= 200);
        Assert.True(editor.SelectedBounds.Value.Bottom <= 120);

        editor.DeleteSelection();
        Assert.Empty(editor.Document.Annotations);
        editor.Undo();
        Assert.Equal(2, editor.Document.Annotations.Count);
    }

    [Fact]
    public void Every_annotation_resize_handle_keeps_the_selection_valid_and_inside_the_canvas()
    {
        foreach (var handle in Enum.GetValues<AnnotationResizeHandle>())
        {
            var editor = CreateEditor();
            editor.Add(new RectangleAnnotation(
                Guid.NewGuid(),
                new SourceRect(40, 30, 80, 50),
                AnnotationStyle.Default));

            editor.ResizeSelection(handle, new SourcePoint(-100, 500));

            var bounds = editor.SelectedBounds!.Value;
            Assert.True(bounds.Width >= 2);
            Assert.True(bounds.Height >= 2);
            Assert.True(bounds.Left >= 0);
            Assert.True(bounds.Top >= 0);
            Assert.True(bounds.Right <= 200);
            Assert.True(bounds.Bottom <= 120);
        }
    }

    [Fact]
    public void Multi_selection_move_is_one_undoable_command()
    {
        var editor = CreateEditor();
        var first = new RectangleAnnotation(
            Guid.NewGuid(), new SourceRect(10, 10, 20, 20), AnnotationStyle.Default);
        var second = new EllipseAnnotation(
            Guid.NewGuid(), new SourceRect(50, 10, 20, 20), AnnotationStyle.Default);
        editor.Add(first);
        editor.Add(second);
        editor.Select([first.Id, second.Id]);
        var before = editor.Document.Annotations.Select(value => value.Bounds).ToArray();

        editor.MoveSelection(new SourceVector(30, 20));
        Assert.Equal(40, editor.Document.Annotations[0].Bounds.Left);
        Assert.Equal(80, editor.Document.Annotations[1].Bounds.Left);

        editor.Undo();
        Assert.Equal(before, editor.Document.Annotations.Select(value => value.Bounds));
    }

    [Fact]
    public void Undo_redo_treats_each_edit_as_one_command_and_new_edits_clear_redo()
    {
        var editor = CreateEditor();
        editor.TryAddGesture(
            ScreenshotTool.Pen,
            new SourcePoint(1, 1),
            [new SourcePoint(10, 10), new SourcePoint(20, 20)],
            null);
        Assert.Single(editor.Document.Annotations);

        editor.Undo();
        Assert.Empty(editor.Document.Annotations);
        Assert.True(editor.CanRedo);
        editor.Redo();
        Assert.Single(editor.Document.Annotations);

        editor.ApplyColor(AnnotationColor.Red);
        editor.Undo();
        editor.Add(new DotMarkerAnnotation(
            Guid.NewGuid(), new SourcePoint(100, 50), 6, AnnotationStyle.Default));
        Assert.False(editor.CanRedo);
    }

    [Fact]
    public void Internal_copy_paste_and_duplicate_offset_clamp_and_select_the_new_fragment()
    {
        var editor = CreateEditor();
        var marker = new DotMarkerAnnotation(
            Guid.NewGuid(), new SourcePoint(190, 110), 6, AnnotationStyle.Default);
        editor.Add(marker);
        editor.CopySelection();

        Assert.True(editor.Paste());
        Assert.Equal(2, editor.Document.Annotations.Count);
        Assert.Single(editor.Selection.Ids);
        Assert.True(editor.SelectedBounds!.Value.Right <= 200);
        Assert.True(editor.SelectedBounds.Value.Bottom <= 120);

        Assert.True(editor.DuplicateSelection());
        Assert.Equal(3, editor.Document.Annotations.Count);
        Assert.Equal(3, editor.Document.Annotations.Select(value => value.Id).Distinct().Count());
    }

    [Fact]
    public void Internal_clipboard_preserves_group_relationships_and_offsets_by_fifteen_pixels()
    {
        var editor = CreateEditor();
        var first = new RectangleAnnotation(
            Guid.NewGuid(), new SourceRect(10, 10, 20, 20), AnnotationStyle.Default);
        var second = new DotMarkerAnnotation(
            Guid.NewGuid(), new SourcePoint(50, 50), 6, AnnotationStyle.Default);
        editor.Add(first);
        editor.Add(second);
        editor.Select([first.Id, second.Id]);
        editor.CopySelection();

        Assert.True(editor.Paste());

        var pasted = editor.Document.Annotations.Skip(2).ToArray();
        Assert.Equal(25, pasted[0].Bounds.Left);
        Assert.Equal(59, pasted[1].Bounds.Left);
        Assert.Equal(34, pasted[1].Bounds.Left - pasted[0].Bounds.Left);
        Assert.Equal(pasted.Select(value => value.Id), editor.Selection.Ids);
    }

    [Fact]
    public void Style_palette_applies_supported_values_to_new_or_selected_annotations()
    {
        Assert.Equal(
            [AnnotationColor.VoxGreen, AnnotationColor.Red, AnnotationColor.White, AnnotationColor.Black],
            AnnotationPalette.Colors);
        Assert.Equal([6d, 8d, 10d], AnnotationPalette.LineWidths);
        Assert.Equal([14d, 24d, 32d], AnnotationPalette.FontSizes);

        var editor = CreateEditor();
        var rectangle = new RectangleAnnotation(
            Guid.NewGuid(), new SourceRect(10, 10, 50, 50), AnnotationStyle.Default);
        editor.Add(rectangle);
        editor.ApplyColor(AnnotationColor.Red);
        editor.ApplyLineWidth(10);

        var updated = Assert.IsType<RectangleAnnotation>(editor.Document.Annotations[0]);
        Assert.Equal(AnnotationColor.Red, updated.Style.Color);
        Assert.Equal(10, updated.Style.LineWidth);
        Assert.Throws<ArgumentOutOfRangeException>(() => editor.ApplyLineWidth(7));
        Assert.Throws<ArgumentOutOfRangeException>(() => editor.ApplyFontSize(18));
    }

    [Fact]
    public void Current_palette_style_is_inherited_by_new_shapes_and_text()
    {
        var editor = CreateEditor();
        editor.ApplyColor(AnnotationColor.Black);
        editor.ApplyLineWidth(8);
        editor.ApplyFontSize(32);

        Assert.True(editor.TryAddGesture(
            ScreenshotTool.Rectangle,
            new SourcePoint(10, 10),
            [new SourcePoint(50, 50)],
            null));
        Assert.True(editor.TryAddGesture(
            ScreenshotTool.Text,
            new SourcePoint(60, 60),
            [],
            "label"));

        var rectangle = Assert.IsType<RectangleAnnotation>(editor.Document.Annotations[0]);
        var text = Assert.IsType<TextAnnotation>(editor.Document.Annotations[1]);
        Assert.Equal(AnnotationColor.Black, rectangle.Style.Color);
        Assert.Equal(8, rectangle.Style.LineWidth);
        Assert.Equal(AnnotationColor.Black, text.Style.Color);
        Assert.Equal(32, text.Style.FontSize);
    }

    [Fact]
    public void Selecting_existing_annotations_reflects_their_style_and_style_changes_commit_once()
    {
        var editor = CreateEditor();
        var rectangleStyle = AnnotationStyle.Default
            .WithColor(AnnotationColor.Red)
            .WithLineWidth(10);
        var textStyle = TextAnnotationStyle.Default
            .WithColor(AnnotationColor.White)
            .WithFontSize(32);
        var rectangle = new RectangleAnnotation(
            Guid.NewGuid(),
            new SourceRect(10, 10, 40, 30),
            rectangleStyle);
        var text = new TextAnnotation(
            Guid.NewGuid(),
            new SourcePoint(70, 20),
            "caption",
            textStyle);
        editor.Add(rectangle);
        editor.Add(text);

        editor.Select([rectangle.Id]);
        Assert.Equal(AnnotationColor.Red, editor.CurrentStyle.Color);
        Assert.Equal(10, editor.CurrentStyle.LineWidth);
        Assert.Equal(AnnotationColor.Red, editor.CurrentTextStyle.Color);

        editor.Select([text.Id]);
        Assert.Equal(AnnotationColor.White, editor.CurrentStyle.Color);
        Assert.Equal(AnnotationColor.White, editor.CurrentTextStyle.Color);
        Assert.Equal(32, editor.CurrentTextStyle.FontSize);

        var revision = editor.Document.Revision;
        editor.ApplyColor(AnnotationColor.Black);
        Assert.Equal(revision + 1, editor.Document.Revision);
        Assert.Equal(
            AnnotationColor.Black,
            Assert.IsType<TextAnnotation>(editor.Document.Annotations[1]).Style.Color);

        editor.Undo();
        Assert.Equal(AnnotationColor.White, editor.CurrentTextStyle.Color);
        Assert.Equal(
            AnnotationColor.White,
            Assert.IsType<TextAnnotation>(editor.Document.Annotations[1]).Style.Color);
    }

    [Fact]
    public void Existing_multiline_text_edit_is_one_undoable_command_and_cancel_is_a_noop()
    {
        var editor = CreateEditor();
        var text = new TextAnnotation(
            Guid.NewGuid(),
            new SourcePoint(20, 20),
            "first line",
            TextAnnotationStyle.Default);
        editor.Add(text);
        var revision = editor.Document.Revision;

        Assert.True(editor.UpdateText(text.Id, "first line\nsecond line"));
        Assert.Equal(revision + 1, editor.Document.Revision);
        Assert.Equal(
            "first line\nsecond line",
            Assert.IsType<TextAnnotation>(editor.Document.Annotations[0]).Content);

        Assert.False(editor.UpdateText(text.Id, null));
        Assert.Equal(revision + 1, editor.Document.Revision);
        editor.Undo();
        Assert.Equal(
            "first line",
            Assert.IsType<TextAnnotation>(editor.Document.Annotations[0]).Content);
    }

    [Fact]
    public void Move_preview_is_live_without_mutating_history_and_release_commits_once()
    {
        var editor = CreateEditor();
        var rectangle = new RectangleAnnotation(
            Guid.NewGuid(), new SourceRect(10, 10, 40, 30), AnnotationStyle.Default);
        editor.Add(rectangle);
        var committedDocument = editor.Document;

        var preview = editor.PreviewMoveSelection(new SourceVector(25, 15));

        Assert.Same(committedDocument, editor.Document);
        Assert.Equal(35, preview.Single().Bounds.Left);
        Assert.Equal(25, preview.Single().Bounds.Top);

        editor.MoveSelection(new SourceVector(25, 15));
        Assert.Equal(35, editor.SelectedBounds!.Value.Left);
        editor.Undo();
        Assert.Equal(10, editor.SelectedBounds!.Value.Left);
        Assert.Equal(10, editor.SelectedBounds.Value.Top);
    }

    [Fact]
    public void Resize_preview_is_live_without_mutating_history_and_mosaic_has_no_resize_chrome()
    {
        var editor = CreateEditor();
        var rectangle = new RectangleAnnotation(
            Guid.NewGuid(), new SourceRect(10, 10, 40, 30), AnnotationStyle.Default);
        editor.Add(rectangle);
        var committedDocument = editor.Document;

        var preview = editor.PreviewResizeSelection(
            AnnotationResizeHandle.BottomRight,
            new SourcePoint(100, 80));

        Assert.Same(committedDocument, editor.Document);
        Assert.Equal(new SourceRect(10, 10, 90, 70), preview.Single().Bounds);
        editor.ResizeSelection(
            AnnotationResizeHandle.BottomRight,
            new SourcePoint(100, 80));
        editor.Undo();
        Assert.Equal(new SourceRect(10, 10, 40, 30), editor.SelectedBounds);

        var mosaic = new MosaicAnnotation(
            Guid.NewGuid(),
            [new SourcePoint(20, 20), new SourcePoint(40, 40)],
            40,
            8);
        editor.Add(mosaic);
        Assert.Null(editor.SelectedResizableBounds);
        Assert.Same(
            editor.Document.Annotations,
            editor.PreviewResizeSelection(
                AnnotationResizeHandle.BottomRight,
                new SourcePoint(150, 100)));
    }

    private static ScreenshotAnnotationEditor CreateEditor() => new(
        new ScreenshotDocument(
            Guid.NewGuid(),
            new PixelSize(200, 120),
            [],
            revision: 0));
}
