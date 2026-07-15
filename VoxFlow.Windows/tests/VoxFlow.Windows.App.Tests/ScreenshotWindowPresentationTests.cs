using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotWindowPresentationTests
{
    [Fact]
    public async Task Media_view_raises_the_shared_screenshot_entry_command()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var view = new ScreenshotMediaView
            {
                DataContext = new ScreenshotMediaPageViewModel("Screenshots", "Capture screenshots"),
            };
            var raised = 0;
            view.StartScreenshotRequested += (_, _) => raised++;

            var button = Assert.IsType<Button>(view.FindName("StartScreenshotButton"));
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));

            Assert.Equal(1, raised);
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Screenshot_details_use_the_macOS_baseline_window_size_and_actions()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var viewModel = new ScreenshotDetailViewModel
            {
                Id = Guid.NewGuid().ToString("N"),
                Title = "Screenshot",
                CreatedAtText = "2026-07-13 12:00",
                ResolutionText = "1200 × 800",
                FileSizeText = "240 KB",
                CharacterCountText = "42",
            };
            var action = string.Empty;
            viewModel.ActionRequested += (_, value) => action = value;
            var window = new ScreenshotDetailWindow { DataContext = viewModel };

            Assert.Equal(960D, window.Width);
            Assert.Equal(720D, window.Height);
            Assert.Equal(
                ["Ocr", "Translation", "Summary"],
                window.TextSections.Items
                    .OfType<TabItem>()
                    .Select(item => Assert.IsType<string>(item.Tag)));
            viewModel.Execute("reprocess");
            Assert.Equal("reprocess", action);

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Screenshot_details_clamp_to_a_small_200_percent_work_area_and_keep_footer_reachable()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new ScreenshotDetailWindow();
            var workArea = new Rect(-960, 0, 960, 520);

            window.ApplyResponsiveBounds(workArea);
            window.Show();
            window.ApplyResponsiveBounds(workArea);
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.Loaded);
            window.UpdateLayout();

            Assert.Equal(912, window.Width);
            Assert.Equal(472, window.Height);
            Assert.True(window.Left >= workArea.Left);
            Assert.True(window.Top >= workArea.Top);
            Assert.True(window.Left + window.Width <= workArea.Right);
            Assert.True(window.Top + window.Height <= workArea.Bottom);
            Assert.Equal(
                ScrollBarVisibility.Auto,
                window.WindowScrollViewer.VerticalScrollBarVisibility);
            Assert.Equal(7, window.DetailActionPanel.Children.Count);
            Assert.True(window.WindowScrollViewer.ScrollableHeight > 0);
            window.WindowScrollViewer.ScrollToEnd();
            window.UpdateLayout();
            Assert.Equal(
                window.WindowScrollViewer.ScrollableHeight,
                window.WindowScrollViewer.VerticalOffset,
                precision: 3);
            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public void Toolbar_placement_uses_the_selected_monitor_physical_dpi_and_negative_coordinates()
    {
        var layout = new ScreenshotDesktopLayout(
        [
            new ScreenshotDisplay(
                "left",
                "DISPLAY2",
                new PixelRect(-2560, -200, 2560, 1440),
                144,
                144,
                DisplayRotation.Degrees0,
                isPrimary: false),
            new ScreenshotDisplay(
                "primary",
                "DISPLAY1",
                new PixelRect(0, 0, 1920, 1080),
                96,
                96,
                DisplayRotation.Degrees0,
                isPrimary: true),
        ]);

        var below = ScreenshotOverlayCoordinator.CalculateToolbarFrame(
            new PixelRect(-1800, 100, 800, 400),
            layout);
        Assert.Equal(
            (int)Math.Round(ScreenshotToolbarCatalog.WidthFor(22) * 1.5),
            below.Width);
        Assert.Equal(66, below.Height);
        Assert.Equal(512, below.Top);
        Assert.InRange(below.Left, -2560 + 12, -below.Width - 12);

        var above = ScreenshotOverlayCoordinator.CalculateToolbarFrame(
            new PixelRect(-1000, 1120, 700, 100),
            layout);
        Assert.True(above.Bottom <= 1120 - 12);
        Assert.True(above.Left >= -2560 + 12);
        Assert.True(above.Right <= -12);

        var portraitLayout = new ScreenshotDesktopLayout(
        [
            new ScreenshotDisplay(
                "portrait",
                "DISPLAY3",
                new PixelRect(1920, -300, 1080, 1920),
                192,
                192,
                DisplayRotation.Degrees90,
                isPrimary: false),
            new ScreenshotDisplay(
                "primary",
                "DISPLAY1",
                new PixelRect(0, 0, 1920, 1080),
                96,
                96,
                DisplayRotation.Degrees0,
                isPrimary: true),
        ]);
        var portrait = ScreenshotOverlayCoordinator.CalculateToolbarFrame(
            new PixelRect(2060, 200, 700, 900),
            portraitLayout);
        Assert.Equal(1048, portrait.Width);
        Assert.Equal(152, portrait.Height);
        Assert.True(portrait.Left >= 1920);
        Assert.True(portrait.Right <= 3000);
        Assert.True(portrait.Top >= -300);
        Assert.True(portrait.Bottom <= 1620);
    }

    [Fact]
    public void Inline_translation_input_uses_the_current_rendered_annotation_document()
    {
        const int width = 40;
        const int height = 30;
        const int stride = width * 4;
        var pixels = Enumerable.Repeat((byte)255, stride * height).ToArray();
        var source = new FrozenScreenshot(width, height, stride, pixels);
        var empty = new ScreenshotDocument(
            Guid.NewGuid(),
            new PixelSize(width, height),
            [],
            revision: 0);
        Assert.Same(source, ScreenshotOverlayCoordinator.RenderInlineTranslationInput(source, empty));

        var annotated = new ScreenshotDocument(
            Guid.NewGuid(),
            new PixelSize(width, height),
            [
                new RectangleAnnotation(
                    Guid.NewGuid(),
                    new SourceRect(5, 5, 20, 15),
                    AnnotationStyle.Default.WithColor(AnnotationColor.Red)),
            ],
            revision: 1);
        var rendered = ScreenshotOverlayCoordinator.RenderInlineTranslationInput(source, annotated);

        Assert.False(source.Bgra.Span.SequenceEqual(rendered.Bgra.Span));
        Assert.Equal(source.Width, rendered.Width);
        Assert.Equal(source.Height, rendered.Height);
    }

    [Fact]
    public void Every_annotation_document_edit_invalidates_inline_translation_but_selection_alone_does_not()
    {
        var editor = new ScreenshotAnnotationEditor(new ScreenshotDocument(
            Guid.NewGuid(),
            new PixelSize(240, 180),
            [],
            revision: 0));
        var observed = editor.Document;

        void AssertEditInvalidates(Action edit)
        {
            edit();
            Assert.True(ScreenshotOverlayCoordinator.RequiresInlineTranslationInvalidation(
                observed,
                editor.Document));
            observed = editor.Document;
        }

        var rectangle = new RectangleAnnotation(
            Guid.NewGuid(),
            new SourceRect(20, 20, 60, 40),
            AnnotationStyle.Default);
        AssertEditInvalidates(() => editor.Add(rectangle));
        AssertEditInvalidates(() => editor.MoveSelection(new SourceVector(10, 5)));
        AssertEditInvalidates(() => editor.ResizeSelection(
            AnnotationResizeHandle.BottomRight,
            new SourcePoint(120, 90)));
        AssertEditInvalidates(() => editor.ApplyColor(AnnotationColor.Red));

        var text = new TextAnnotation(
            Guid.NewGuid(),
            new SourcePoint(30, 110),
            "first",
            TextAnnotationStyle.Default);
        AssertEditInvalidates(() => editor.Add(text));
        AssertEditInvalidates(() => editor.UpdateText(text.Id, "first\nsecond"));
        AssertEditInvalidates(editor.Undo);
        AssertEditInvalidates(editor.Redo);

        editor.Select([rectangle.Id]);
        Assert.False(ScreenshotOverlayCoordinator.RequiresInlineTranslationInvalidation(
            observed,
            editor.Document));
    }

    [Fact]
    public void Text_tool_hits_existing_text_for_editing_even_when_another_annotation_is_above_it()
    {
        var text = new TextAnnotation(
            Guid.NewGuid(),
            new SourcePoint(20, 20),
            "editable",
            TextAnnotationStyle.Default);
        var coveringShape = new RectangleAnnotation(
            Guid.NewGuid(),
            new SourceRect(10, 10, 120, 60),
            AnnotationStyle.Default);

        Assert.Same(
            text,
            ScreenshotOverlayCoordinator.FindEditableText(
                [text, coveringShape],
                new SourcePoint(30, 30)));
        Assert.Null(ScreenshotOverlayCoordinator.FindEditableText(
            [text, coveringShape],
            new SourcePoint(200, 150)));
    }

    [Fact]
    public async Task Inline_text_editor_supports_multiline_commit_edit_and_escape_without_bubbling()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var frame = new FrozenDisplayFrame(
                "DISPLAY1",
                "adapter",
                new CapturePixelRect(0, 0, 400, 300),
                rotationDegrees: 0,
                stride: 1600,
                new byte[1600 * 300]);
            var activation = new CapturingScreenshotWindowActivation();
            var activationStates = new List<bool>();
            var window = new ScreenshotOverlayWindow(
                frame,
                activation,
                savedForegroundWindow: new nint(1234),
                activationStates.Add);
            ScreenshotTextCommittedEventArgs? committed = null;
            var forwardedKeys = 0;
            window.TextCommitted += (_, eventArgs) => committed = eventArgs;
            window.KeyPressed += (_, _) => forwardedKeys++;
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);

            var annotationId = Guid.NewGuid();
            window.BeginTextEditing(
                new SourcePoint(20, 20),
                new PixelRect(0, 0, 400, 300),
                TextAnnotationStyle.Default,
                "existing",
                annotationId);
            var editor = Assert.IsType<TextBox>(window.TextEditor);
            Assert.True(window.Focusable);
            Assert.True(editor.IsKeyboardFocused);
            Assert.False(activation.NoActivateStates.Last());
            Assert.Equal([true], activationStates);
            Assert.True(editor.AcceptsReturn);
            Assert.Equal(TextWrapping.Wrap, editor.TextWrapping);
            Assert.Equal("existing", editor.Text);
            Assert.False(ScreenshotOverlayWindow.ShouldCommitTextEditing(
                Key.Enter,
                ModifierKeys.None));
            Assert.False(ScreenshotOverlayWindow.ShouldCommitTextEditing(
                Key.Enter,
                ModifierKeys.Shift));
            Assert.True(ScreenshotOverlayWindow.ShouldCommitTextEditing(
                Key.Enter,
                ModifierKeys.Control));

            editor.Text = "changed but cancelled";
            var source = PresentationSource.FromVisual(window);
            Assert.NotNull(source);
            editor.RaiseEvent(new KeyEventArgs(
                Keyboard.PrimaryDevice,
                source,
                Environment.TickCount,
                Key.Escape)
            {
                RoutedEvent = Keyboard.PreviewKeyDownEvent,
            });
            Assert.Null(window.TextEditor);
            Assert.False(window.Focusable);
            Assert.True(activation.NoActivateStates.Last());
            Assert.Equal(new nint(1234), activation.RestoredWindows.Last());
            Assert.Equal([true, false], activationStates);
            Assert.Equal(annotationId, committed?.AnnotationId);
            Assert.Null(committed?.Text);
            Assert.Equal(0, forwardedKeys);

            committed = null;
            window.BeginTextEditing(
                new SourcePoint(20, 20),
                new PixelRect(0, 0, 400, 300),
                TextAnnotationStyle.Default,
                "existing",
                annotationId);
            window.TextEditor!.Text = "first line\nsecond line";
            window.CommitTextEditing();
            Assert.Equal("first line\nsecond line", committed?.Text);
            Assert.Equal(annotationId, committed?.AnnotationId);
            Assert.False(window.Focusable);
            Assert.Equal(new nint(1234), activation.RestoredWindows.Last());

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Overlay_surface_maps_scaled_local_points_to_physical_pixels_and_exposes_automation()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var frame = new FrozenDisplayFrame(
                "DISPLAY2",
                "adapter",
                new CapturePixelRect(-1200, 100, 1200, 800),
                rotationDegrees: 0,
                stride: 4800,
                new byte[4800 * 800]);
            var window = new ScreenshotOverlayWindow(frame);
            window.Surface.Measure(new Size(600, 400));
            window.Surface.Arrange(new Rect(0, 0, 600, 400));

            Assert.Equal(new PixelPoint(-600, 500), window.Surface.LocalToPhysical(
                new Point(300, 200)));
            Assert.Equal(
                "screenshot.overlay.DISPLAY2",
                AutomationProperties.GetAutomationId(window.Surface));
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(window.Surface)));
            Assert.True(window.Topmost);
            Assert.False(window.ShowActivated);
            Assert.False(window.Focusable);
            Assert.False(window.Surface.Focusable);
            Assert.False(window.ShowInTaskbar);
            Assert.Equal(WindowStyle.None, window.WindowStyle);
            Assert.Equal(ResizeMode.NoResize, window.ResizeMode);

            window.Close();
            return Task.CompletedTask;
        });
    }

    private sealed class CapturingScreenshotWindowActivation : IScreenshotWindowActivation
    {
        public List<bool> NoActivateStates { get; } = [];

        public List<nint> RestoredWindows { get; } = [];

        public nint CaptureForegroundWindow() => new(1234);

        public void SetNoActivate(nint windowHandle, bool enabled)
        {
            Assert.NotEqual(nint.Zero, windowHandle);
            NoActivateStates.Add(enabled);
        }

        public bool RestoreForegroundWindow(nint windowHandle)
        {
            RestoredWindows.Add(windowHandle);
            return true;
        }
    }
}
