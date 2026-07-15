using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.Application.Screenshots;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;
using TextBox = System.Windows.Controls.TextBox;

namespace VoxFlow.Windows.App.Screenshot;

internal sealed class ScreenshotPointerEventArgs : EventArgs
{
    public ScreenshotPointerEventArgs(
        PixelPoint point,
        MouseButton button,
        int clickCount,
        ModifierKeys modifiers)
    {
        Point = point;
        Button = button;
        ClickCount = clickCount;
        Modifiers = modifiers;
    }

    public PixelPoint Point { get; }

    public MouseButton Button { get; }

    public int ClickCount { get; }

    public ModifierKeys Modifiers { get; }
}

internal sealed class ScreenshotKeyEventArgs : EventArgs
{
    public ScreenshotKeyEventArgs(Key key, ModifierKeys modifiers)
    {
        Key = key;
        Modifiers = modifiers;
    }

    public Key Key { get; }

    public ModifierKeys Modifiers { get; }

    public bool Handled { get; set; }
}

internal sealed class ScreenshotTextCommittedEventArgs : EventArgs
{
    public ScreenshotTextCommittedEventArgs(
        SourcePoint position,
        string? text,
        Guid? annotationId = null)
    {
        Position = position;
        Text = text;
        AnnotationId = annotationId;
    }

    public SourcePoint Position { get; }

    public string? Text { get; }

    public Guid? AnnotationId { get; }
}

internal enum ScreenshotInlineTranslationPresentationKind
{
    None,
    Loading,
    Progress,
    Failure,
}

internal sealed class ScreenshotOverlayWindow : System.Windows.Window
{
    private readonly Grid root;
    private readonly Canvas editorLayer;
    private readonly IScreenshotWindowActivation windowActivation;
    private readonly nint savedForegroundWindow;
    private readonly Action<bool>? textEditingActivationChanged;
    private HwndSource? windowSource;
    private TextBox? textEditor;
    private SourcePoint textPosition;
    private Guid? editedTextAnnotationId;
    private bool isCompletingText;
    private bool isTextEditingActive;

    public ScreenshotOverlayWindow(FrozenDisplayFrame frame)
        : this(
            frame,
            WindowsScreenshotWindowActivation.Shared,
            WindowsScreenshotWindowActivation.Shared.CaptureForegroundWindow(),
            textEditingActivationChanged: null)
    {
    }

    internal ScreenshotOverlayWindow(
        FrozenDisplayFrame frame,
        IScreenshotWindowActivation windowActivation,
        nint savedForegroundWindow,
        Action<bool>? textEditingActivationChanged)
    {
        Frame = frame ?? throw new ArgumentNullException(nameof(frame));
        this.windowActivation = windowActivation
            ?? throw new ArgumentNullException(nameof(windowActivation));
        this.savedForegroundWindow = savedForegroundWindow;
        this.textEditingActivationChanged = textEditingActivationChanged;
        Surface = new ScreenshotOverlaySurface(frame)
        {
            Focusable = false,
        };
        AutomationProperties.SetAutomationId(Surface, $"screenshot.overlay.{frame.DeviceName}");
        AutomationProperties.SetName(Surface, L10n.Localize("ScreenshotOverlayName"));

        editorLayer = new Canvas
        {
            IsHitTestVisible = true,
        };
        root = new Grid();
        root.Children.Add(Surface);
        root.Children.Add(editorLayer);
        Content = root;

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Background = Brushes.Black;
        AllowsTransparency = false;
        Focusable = false;
        Title = L10n.Localize("ScreenshotOverlayName");

        SourceInitialized += OnSourceInitialized;
        Surface.PreviewMouseDown += OnMouseDown;
        Surface.PreviewMouseMove += OnMouseMove;
        Surface.PreviewMouseUp += OnMouseUp;
        PreviewKeyDown += OnPreviewKeyDown;
    }

    public event EventHandler<ScreenshotPointerEventArgs>? PointerPressed;

    public event EventHandler<ScreenshotPointerEventArgs>? PointerMoved;

    public event EventHandler<ScreenshotPointerEventArgs>? PointerReleased;

    public event EventHandler<ScreenshotKeyEventArgs>? KeyPressed;

    public event EventHandler<ScreenshotTextCommittedEventArgs>? TextCommitted;

    public FrozenDisplayFrame Frame { get; }

    public ScreenshotOverlaySurface Surface { get; }

    internal TextBox? TextEditor => textEditor;

    public void CapturePointer() => Mouse.Capture(Surface, CaptureMode.Element);

    public void ReleasePointer()
    {
        if (ReferenceEquals(Mouse.Captured, Surface))
        {
            Mouse.Capture(null);
        }
    }

    public void BeginTextEditing(
        SourcePoint position,
        PixelRect selection,
        TextAnnotationStyle style,
        string initialText = "",
        Guid? annotationId = null)
    {
        ArgumentNullException.ThrowIfNull(style);
        ArgumentNullException.ThrowIfNull(initialText);
        CompleteTextEditor(commit: true);
        textPosition = position;
        editedTextAnnotationId = annotationId;
        var local = Surface.SourceToLocal(position, selection);
        var brush = ScreenshotOverlaySurface.ToBrush(style.Color);
        var minimumWidth = Surface.SourceLengthToLocal(TextAnnotationDraft.MinimumWidth);
        var maximumWidth = Surface.SourceLengthToLocal(TextAnnotationDraft.MaximumWidth);
        var minimumHeight = Surface.SourceLengthToLocal(36);
        var maximumHeight = Surface.SourceLengthToLocal(180);
        textEditor = new TextBox
        {
            Text = initialText,
            MinWidth = minimumWidth,
            MaxWidth = maximumWidth,
            MinHeight = minimumHeight,
            MaxHeight = maximumHeight,
            FontFamily = new FontFamily(style.FontName),
            FontSize = Surface.SourceLengthToLocal(style.FontSize),
            Foreground = brush,
            Background = new SolidColorBrush(Color.FromArgb(230, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(27, 171, 89)),
            BorderThickness = new Thickness(2),
            Padding = new Thickness(4, 3, 4, 3),
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalContentAlignment = VerticalAlignment.Top,
        };
        AutomationProperties.SetAutomationId(textEditor, "screenshot.annotation.text.editor");
        AutomationProperties.SetName(textEditor, L10n.Localize("ScreenshotAnnotationTextEditor"));
        Canvas.SetLeft(textEditor, Math.Clamp(local.X, 0, Math.Max(0, ActualWidth - minimumWidth)));
        Canvas.SetTop(textEditor, Math.Clamp(local.Y, 0, Math.Max(0, ActualHeight - minimumHeight)));
        textEditor.PreviewKeyDown += OnTextEditorKeyDown;
        textEditor.LostKeyboardFocus += OnTextEditorLostKeyboardFocus;
        editorLayer.Children.Add(textEditor);
        EnterTextEditingActivation();
        _ = Activate();
        _ = textEditor.Focus();
        _ = Keyboard.Focus(textEditor);
        textEditor.CaretIndex = textEditor.Text.Length;
    }

    public void CancelTextEditing() => CompleteTextEditor(commit: false);

    internal void CommitTextEditing() => CompleteTextEditor(commit: true);

    internal static bool ShouldCommitTextEditing(Key key, ModifierKeys modifiers) =>
        key == Key.Enter && modifiers.HasFlag(ModifierKeys.Control);

    protected override void OnClosed(EventArgs e)
    {
        CompleteTextEditor(commit: false);
        ReleasePointer();
        windowSource?.RemoveHook(HandleWindowMessage);
        windowSource = null;
        SourceInitialized -= OnSourceInitialized;
        base.OnClosed(e);
    }

    internal static bool ShouldSuppressMouseActivation(int message, bool isTextEditing) =>
        message == WindowsScreenshotWindowActivation.WmMouseActivate && !isTextEditing;

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        WindowsScreenshotDpi.ApplyPhysicalBounds(this, Frame.Bounds);
        var handle = new WindowInteropHelper(this).Handle;
        windowActivation.SetNoActivate(handle, enabled: true);
        windowSource = HwndSource.FromHwnd(handle);
        windowSource?.AddHook(HandleWindowMessage);
    }

    private nint HandleWindowMessage(
        nint windowHandle,
        int message,
        nint wordParameter,
        nint longParameter,
        ref bool handled)
    {
        _ = windowHandle;
        _ = wordParameter;
        _ = longParameter;
        if (!ShouldSuppressMouseActivation(message, isTextEditingActive))
        {
            return nint.Zero;
        }
        handled = true;
        return new nint(WindowsScreenshotWindowActivation.MaNoActivate);
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs eventArgs)
    {
        var args = CreatePointerArgs(eventArgs, eventArgs.ChangedButton, eventArgs.ClickCount);
        PointerPressed?.Invoke(this, args);
        eventArgs.Handled = true;
    }

    private void OnMouseMove(object sender, MouseEventArgs eventArgs)
    {
        var button = eventArgs.LeftButton == MouseButtonState.Pressed
            ? MouseButton.Left
            : eventArgs.RightButton == MouseButtonState.Pressed
                ? MouseButton.Right
                : MouseButton.Middle;
        PointerMoved?.Invoke(
            this,
            new ScreenshotPointerEventArgs(
                Surface.LocalToPhysical(eventArgs.GetPosition(Surface)),
                button,
                clickCount: 0,
                Keyboard.Modifiers));
        eventArgs.Handled = true;
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs eventArgs)
    {
        PointerReleased?.Invoke(
            this,
            CreatePointerArgs(eventArgs, eventArgs.ChangedButton, eventArgs.ClickCount));
        eventArgs.Handled = true;
    }

    private ScreenshotPointerEventArgs CreatePointerArgs(
        MouseEventArgs eventArgs,
        MouseButton button,
        int clickCount) => new(
            Surface.LocalToPhysical(eventArgs.GetPosition(Surface)),
            button,
            clickCount,
            Keyboard.Modifiers);

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (textEditor is not null && eventArgs.Key == Key.Escape)
        {
            CompleteTextEditor(commit: false);
            eventArgs.Handled = true;
            return;
        }
        if (textEditor is not null)
        {
            return;
        }

        var args = new ScreenshotKeyEventArgs(eventArgs.Key, Keyboard.Modifiers);
        KeyPressed?.Invoke(this, args);
        eventArgs.Handled = args.Handled;
    }

    private void OnTextEditorKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.Escape)
        {
            eventArgs.Handled = true;
            CompleteTextEditor(commit: false);
        }
        else if (ShouldCommitTextEditing(eventArgs.Key, Keyboard.Modifiers))
        {
            eventArgs.Handled = true;
            CompleteTextEditor(commit: true);
        }
    }

    private void OnTextEditorLostKeyboardFocus(
        object sender,
        KeyboardFocusChangedEventArgs eventArgs) => CompleteTextEditor(commit: true);

    private void CompleteTextEditor(bool commit)
    {
        if (textEditor is null || isCompletingText)
        {
            return;
        }

        isCompletingText = true;
        try
        {
            var editor = textEditor;
            textEditor = null;
            var annotationId = editedTextAnnotationId;
            editedTextAnnotationId = null;
            editor.PreviewKeyDown -= OnTextEditorKeyDown;
            editor.LostKeyboardFocus -= OnTextEditorLostKeyboardFocus;
            editorLayer.Children.Remove(editor);
            TextCommitted?.Invoke(
                this,
                new ScreenshotTextCommittedEventArgs(
                    textPosition,
                    commit ? editor.Text : null,
                    annotationId));
        }
        finally
        {
            ExitTextEditingActivation();
            isCompletingText = false;
        }
    }

    private void EnterTextEditingActivation()
    {
        if (isTextEditingActive)
        {
            return;
        }
        isTextEditingActive = true;
        textEditingActivationChanged?.Invoke(true);
        Focusable = true;
        var handle = new WindowInteropHelper(this).Handle;
        windowActivation.SetNoActivate(handle, enabled: false);
    }

    private void ExitTextEditingActivation()
    {
        if (!isTextEditingActive)
        {
            return;
        }
        isTextEditingActive = false;
        Focusable = false;
        var handle = new WindowInteropHelper(this).Handle;
        windowActivation.SetNoActivate(handle, enabled: true);
        textEditingActivationChanged?.Invoke(false);
        _ = windowActivation.RestoreForegroundWindow(savedForegroundWindow);
    }
}

internal sealed class ScreenshotOverlaySurface : FrameworkElement
{
    private static readonly SolidColorBrush VoxGreenBrush = FrozenBrush(Color.FromRgb(27, 171, 89));
    private static readonly SolidColorBrush WhiteBrush = FrozenBrush(Colors.White);
    private static readonly SolidColorBrush BlackBrush = FrozenBrush(Colors.Black);
    private readonly FrozenDisplayFrame frame;
    private readonly BitmapSource background;
    private ScreenshotSelectionState? selectionState;
    private ScreenshotAnnotationEditor? annotationEditor;
    private ScreenshotAnnotation? previewAnnotation;
    private IReadOnlyList<ScreenshotAnnotation>? annotationTransformPreview;
    private FrozenScreenshot? annotationSourceImage;
    private readonly ScreenshotMosaicPatternCache mosaicPreviewCache = new();
    private IReadOnlyList<ScreenshotInlineTranslationLine> inlineTranslationLines = [];
    private ScreenshotInlineTranslationPresentationKind inlineTranslationPresentation;
    private string? inlineTranslationStatusText;

    public ScreenshotOverlaySurface(FrozenDisplayFrame frame)
    {
        this.frame = frame ?? throw new ArgumentNullException(nameof(frame));
        background = BitmapSource.Create(
            frame.Bounds.Width,
            frame.Bounds.Height,
            96,
            96,
            PixelFormats.Bgra32,
            palette: null,
            frame.Bgra.ToArray(),
            frame.Stride);
        background.Freeze();
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
    }

    public void Update(
        ScreenshotSelectionState state,
        ScreenshotAnnotationEditor? editor,
        ScreenshotAnnotation? preview,
        IReadOnlyList<ScreenshotAnnotation>? transformPreview = null,
        FrozenScreenshot? sourceImage = null,
        IReadOnlyList<ScreenshotInlineTranslationLine>? translatedLines = null,
        ScreenshotInlineTranslationPresentationKind translationPresentation =
            ScreenshotInlineTranslationPresentationKind.None,
        string? translationStatusText = null)
    {
        selectionState = state ?? throw new ArgumentNullException(nameof(state));
        annotationEditor = editor;
        previewAnnotation = preview;
        annotationTransformPreview = transformPreview;
        if (!ReferenceEquals(annotationSourceImage, sourceImage))
        {
            annotationSourceImage = sourceImage;
            mosaicPreviewCache.Clear();
        }
        inlineTranslationLines = translatedLines ?? [];
        inlineTranslationPresentation = translationPresentation;
        inlineTranslationStatusText = translationStatusText;
        InvalidateVisual();
    }

    public PixelPoint LocalToPhysical(Point point)
    {
        var width = Math.Max(ActualWidth, 1);
        var height = Math.Max(ActualHeight, 1);
        return new PixelPoint(
            checked(frame.Bounds.Left + (int)Math.Round(point.X * frame.Bounds.Width / width)),
            checked(frame.Bounds.Top + (int)Math.Round(point.Y * frame.Bounds.Height / height)));
    }

    public Point SourceToLocal(SourcePoint point, PixelRect selection) => PhysicalToLocal(
        selection.Left + point.X,
        selection.Top + point.Y);

    internal double SourceLengthToLocal(double length) => ScaleSourceLength(length);

    public static SolidColorBrush ToBrush(AnnotationColor color) => FrozenBrush(Color.FromArgb(
        checked((byte)Math.Round(color.AlphaComponent * 255)),
        checked((byte)Math.Round(color.RedComponent * 255)),
        checked((byte)Math.Round(color.GreenComponent * 255)),
        checked((byte)Math.Round(color.BlueComponent * 255))));

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        drawingContext.DrawImage(background, new Rect(0, 0, ActualWidth, ActualHeight));
        if (selectionState is null)
        {
            return;
        }

        DrawSelection(drawingContext, selectionState);
        if (selectionState.EffectiveRegion is { IsEmpty: false } selection)
        {
            DrawAnnotations(drawingContext, selection);
            DrawInlineTranslationStatus(drawingContext, selection);
        }
    }

    private void DrawInlineTranslationStatus(
        DrawingContext drawingContext,
        PixelRect selection)
    {
        if (inlineTranslationPresentation == ScreenshotInlineTranslationPresentationKind.None
            || string.IsNullOrWhiteSpace(inlineTranslationStatusText))
        {
            return;
        }

        var formatted = CreateText(
            inlineTranslationStatusText,
            12,
            WhiteBrush,
            FontWeights.SemiBold,
            "Segoe UI");
        var clipped = selection.Intersection(ToDomainRect(frame.Bounds));
        if (clipped.IsEmpty)
        {
            return;
        }

        Rect box;
        if (inlineTranslationPresentation == ScreenshotInlineTranslationPresentationKind.Loading)
        {
            var local = PhysicalToLocal(clipped);
            var width = Math.Max(72, formatted.Width + 20);
            var height = 74D;
            box = new Rect(
                local.Left + ((local.Width - width) / 2),
                local.Top + ((local.Height - height) / 2),
                width,
                height);
            drawingContext.DrawRoundedRectangle(
                FrozenBrush(Color.FromArgb(107, 0, 0, 0)),
                null,
                box,
                12,
                12);
        }
        else
        {
            var local = PhysicalToLocal(clipped);
            var width = Math.Min(
                Math.Max(120, formatted.Width + 20),
                Math.Max(120, local.Width));
            var height = formatted.Height + 10;
            var x = Math.Clamp(
                local.Left + ((local.Width - width) / 2),
                8,
                Math.Max(8, ActualWidth - width - 8));
            var preferredY = local.Bottom + 59;
            var y = preferredY + height <= ActualHeight
                ? preferredY
                : Math.Max(8, local.Top - 59 - height);
            box = new Rect(x, y, width, height);
            drawingContext.DrawRoundedRectangle(
                FrozenBrush(Color.FromArgb(224, 210, 42, 42)),
                null,
                box,
                8,
                8);
        }

        drawingContext.DrawText(
            formatted,
            new Point(
                box.Left + ((box.Width - formatted.Width) / 2),
                box.Top + ((box.Height - formatted.Height) / 2)));
    }

    private void DrawSelection(DrawingContext drawingContext, ScreenshotSelectionState state)
    {
        var displayBounds = ToDomainRect(frame.Bounds);
        var effective = state.EffectiveRegion;
        var clipped = effective?.Intersection(displayBounds);
        if (clipped is { IsEmpty: true })
        {
            clipped = null;
        }

        var maskOpacity = state.HasValidRegion
            ? ScreenshotSelectionPresentation.SelectionMaskOpacity
            : ScreenshotSelectionPresentation.NoSelectionMaskOpacity;
        var maskBrush = FrozenBrush(Color.FromArgb(
            checked((byte)Math.Round(maskOpacity * 255)),
            0,
            0,
            0));
        if (clipped is null)
        {
            drawingContext.DrawRectangle(maskBrush, null, new Rect(0, 0, ActualWidth, ActualHeight));
        }
        else
        {
            foreach (var mask in BuildOutsideMasks(displayBounds, clipped.Value))
            {
                drawingContext.DrawRectangle(maskBrush, null, PhysicalToLocal(mask));
            }
        }

        if (state.Region is null
            && state.IsWindowSnapEnabled
            && state.WindowCandidate is { } candidate
            && candidate.Bounds.Intersects(displayBounds))
        {
            var candidateRect = candidate.Bounds.Intersection(displayBounds);
            var fill = FrozenBrush(Color.FromArgb(56, 27, 171, 89));
            drawingContext.DrawRectangle(
                fill,
                new Pen(VoxGreenBrush, ScaleLineWidth(2)),
                PhysicalToLocal(candidateRect));
        }

        if (effective is not { IsEmpty: false } region)
        {
            return;
        }

        drawingContext.DrawRectangle(
            null,
            new Pen(VoxGreenBrush, ScaleLineWidth(ScreenshotSelectionPresentation.BorderThickness)),
            PhysicalToLocal(region));
        foreach (var handle in GlobalSelectionHandles(region))
        {
            if (handle.Bounds.Intersects(displayBounds))
            {
                var handleRect = PhysicalToLocal(handle.Bounds);
                drawingContext.DrawRoundedRectangle(
                    VoxGreenBrush,
                    null,
                    handleRect,
                    ScaleSourceLength(2),
                    ScaleSourceLength(2));
            }
        }

        DrawDimensionLabel(drawingContext, region);
    }

    private void DrawAnnotations(DrawingContext drawingContext, PixelRect selection)
    {
        var clipped = selection.Intersection(ToDomainRect(frame.Bounds));
        if (clipped.IsEmpty)
        {
            return;
        }

        drawingContext.PushClip(new RectangleGeometry(PhysicalToLocal(clipped)));
        if (inlineTranslationLines.Count > 0)
        {
            ScreenshotInlineTranslationRenderer.Draw(
                drawingContext,
                inlineTranslationLines,
                bounds => SourceToLocal(
                    new SourceRect(bounds.X, bounds.Y, bounds.Width, bounds.Height),
                    selection),
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
        }
        if (annotationEditor is not null)
        {
            var annotations = annotationTransformPreview ?? annotationEditor.Document.Annotations;
            foreach (var annotation in annotations)
            {
                DrawAnnotation(drawingContext, annotation, selection, isPreview: false);
            }
            if (SelectedResizableBounds(annotationEditor, annotations) is
                { IsEmpty: false } selectedBounds)
            {
                DrawAnnotationSelection(drawingContext, selectedBounds, selection);
            }
        }
        if (previewAnnotation is not null)
        {
            DrawAnnotation(drawingContext, previewAnnotation, selection, isPreview: true);
        }
        drawingContext.Pop();
    }

    private void DrawAnnotation(
        DrawingContext drawingContext,
        ScreenshotAnnotation annotation,
        PixelRect selection,
        bool isPreview)
    {
        var opacity = isPreview ? 0.72 : 1;
        switch (annotation)
        {
            case PenAnnotation pen:
                DrawPolyline(drawingContext, pen.Points, selection, pen.Style, opacity);
                break;
            case EllipseAnnotation ellipse:
            {
                var rect = SourceToLocal(ellipse.Rect, selection);
                drawingContext.DrawEllipse(
                    ellipse.Style.FillColor is { } fill ? WithOpacity(ToBrush(fill), opacity) : null,
                    StylePen(ellipse.Style, opacity),
                    new Point(rect.Left + (rect.Width / 2), rect.Top + (rect.Height / 2)),
                    rect.Width / 2,
                    rect.Height / 2);
                break;
            }
            case RectangleAnnotation rectangle:
            {
                drawingContext.DrawRectangle(
                    rectangle.Style.FillColor is { } rectangleFill
                        ? WithOpacity(ToBrush(rectangleFill), opacity)
                        : null,
                    StylePen(rectangle.Style, opacity),
                    SourceToLocal(rectangle.Rect, selection));
                break;
            }
            case ArrowAnnotation arrow:
                DrawArrow(drawingContext, arrow, selection, opacity);
                break;
            case DotMarkerAnnotation marker:
            {
                var center = SourceToLocal(marker.Center, selection);
                var radius = ScaleSourceLength(marker.Radius);
                drawingContext.DrawEllipse(
                    WithOpacity(ToBrush(marker.Style.FillColor ?? marker.Style.Color), opacity),
                    new Pen(WhiteBrush, Math.Max(1, ScaleSourceLength(marker.Style.LineWidth))),
                    center,
                    radius,
                    radius);
                break;
            }
            case NumberedMarkerAnnotation marker:
                DrawNumberedMarker(drawingContext, marker, selection, opacity);
                break;
            case TextAnnotation text:
                DrawTextAnnotation(drawingContext, text, selection, opacity);
                break;
            case MosaicAnnotation mosaic:
                DrawMosaicPreview(drawingContext, mosaic, selection, opacity);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(annotation));
        }
    }

    private void DrawPolyline(
        DrawingContext drawingContext,
        IReadOnlyList<SourcePoint> points,
        PixelRect selection,
        AnnotationStyle style,
        double opacity)
    {
        if (points.Count < 2)
        {
            return;
        }
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(SourceToLocal(points[0], selection), isFilled: false, isClosed: false);
            context.PolyLineTo(
                points.Skip(1).Select(point => SourceToLocal(point, selection)).ToArray(),
                isStroked: true,
                isSmoothJoin: true);
        }
        geometry.Freeze();
        drawingContext.DrawGeometry(null, StylePen(style, opacity), geometry);
    }

    private void DrawArrow(
        DrawingContext drawingContext,
        ArrowAnnotation arrow,
        PixelRect selection,
        double opacity)
    {
        var start = SourceToLocal(arrow.Start, selection);
        var end = SourceToLocal(arrow.End, selection);
        var pen = StylePen(arrow.Style, opacity);
        drawingContext.DrawLine(pen, start, end);
        var deltaX = end.X - start.X;
        var deltaY = end.Y - start.Y;
        if (Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY)) <= 0.01)
        {
            return;
        }
        var angle = Math.Atan2(deltaY, deltaX);
        var headLength = Math.Max(10, ScaleSourceLength(arrow.Style.LineWidth * 4));
        const double headAngle = Math.PI / 6;
        var first = new Point(
            end.X - (headLength * Math.Cos(angle - headAngle)),
            end.Y - (headLength * Math.Sin(angle - headAngle)));
        var second = new Point(
            end.X - (headLength * Math.Cos(angle + headAngle)),
            end.Y - (headLength * Math.Sin(angle + headAngle)));
        var head = new StreamGeometry();
        using (var context = head.Open())
        {
            context.BeginFigure(end, isFilled: true, isClosed: true);
            context.LineTo(first, isStroked: true, isSmoothJoin: true);
            context.LineTo(second, isStroked: true, isSmoothJoin: true);
        }
        head.Freeze();
        drawingContext.DrawGeometry(pen.Brush, null, head);
    }

    private void DrawNumberedMarker(
        DrawingContext drawingContext,
        NumberedMarkerAnnotation marker,
        PixelRect selection,
        double opacity)
    {
        var center = SourceToLocal(marker.Center, selection);
        var radius = ScaleSourceLength(marker.Radius);
        drawingContext.DrawEllipse(
            WithOpacity(ToBrush(marker.Style.FillColor ?? marker.Style.Color), opacity),
            new Pen(WhiteBrush, Math.Max(1, ScaleSourceLength(marker.Style.LineWidth))),
            center,
            radius,
            radius);
        var formatted = CreateText(
            marker.Number.ToString(CultureInfo.InvariantCulture),
            Math.Max(10, radius),
            WhiteBrush,
            FontWeights.Bold,
            "Segoe UI");
        drawingContext.DrawText(
            formatted,
            new Point(center.X - (formatted.Width / 2), center.Y - (formatted.Height / 2)));
    }

    private void DrawTextAnnotation(
        DrawingContext drawingContext,
        TextAnnotation text,
        PixelRect selection,
        double opacity)
    {
        var formatted = CreateText(
            text.Content,
            ScaleSourceLength(text.Style.FontSize),
            WithOpacity(ToBrush(text.Style.Color), opacity),
            FontWeights.Normal,
            text.Style.FontName);
        drawingContext.DrawText(formatted, SourceToLocal(text.Position, selection));
    }

    private void DrawMosaicPreview(
        DrawingContext drawingContext,
        MosaicAnnotation mosaic,
        PixelRect selection,
        double opacity)
    {
        if (mosaic.Points.Count == 0)
        {
            return;
        }

        if (annotationSourceImage is null)
        {
            DrawMosaicFallback(drawingContext, mosaic, selection, opacity);
            return;
        }

        var block = ScreenshotMosaicCompositor.NormalizeBlockSize(
            annotationSourceImage,
            mosaic.BlockSize);
        var pattern = mosaicPreviewCache.GetOrCreate(
            annotationSourceImage,
            block,
            checked((int)Math.Floor(mosaic.Bounds.Left)),
            checked((int)Math.Floor(mosaic.Bounds.Top)));

        drawingContext.PushClip(MosaicLocalClip(mosaic, selection));
        ScreenshotMosaicCompositor.DrawPattern(
            drawingContext,
            pattern.Bitmap,
            SourceToLocal(
                new SourceRect(
                    pattern.CanvasBounds.Left,
                    pattern.CanvasBounds.Top,
                    pattern.CanvasBounds.Width,
                    pattern.CanvasBounds.Height),
                selection));
        drawingContext.Pop();
    }

    private void DrawMosaicFallback(
        DrawingContext drawingContext,
        MosaicAnnotation mosaic,
        PixelRect selection,
        double opacity)
    {
        var brush = WithOpacity(BlackBrush, opacity * 0.28);
        var pen = new Pen(brush, ScaleSourceLength(mosaic.BrushSize))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        if (mosaic.Points.Count == 1)
        {
            var center = SourceToLocal(mosaic.Points[0], selection);
            var radius = ScaleSourceLength(mosaic.BrushSize / 2);
            drawingContext.DrawEllipse(brush, null, center, radius, radius);
            return;
        }
        for (var index = 1; index < mosaic.Points.Count; index++)
        {
            drawingContext.DrawLine(
                pen,
                SourceToLocal(mosaic.Points[index - 1], selection),
                SourceToLocal(mosaic.Points[index], selection));
        }
    }

    private Geometry MosaicLocalClip(MosaicAnnotation mosaic, PixelRect selection)
    {
        if (mosaic.Points.Count == 1)
        {
            var center = SourceToLocal(mosaic.Points[0], selection);
            var radius = ScaleSourceLength(mosaic.BrushSize / 2);
            var circle = new EllipseGeometry(center, radius, radius);
            circle.Freeze();
            return circle;
        }

        var path = new StreamGeometry();
        using (var context = path.Open())
        {
            context.BeginFigure(
                SourceToLocal(mosaic.Points[0], selection),
                isFilled: false,
                isClosed: false);
            context.PolyLineTo(
                mosaic.Points
                    .Skip(1)
                    .Select(point => SourceToLocal(point, selection))
                    .ToArray(),
                isStroked: true,
                isSmoothJoin: true);
        }
        path.Freeze();
        var pen = new Pen(BlackBrush, ScaleSourceLength(mosaic.BrushSize))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        var widened = path.GetWidenedPathGeometry(pen, 0.25, ToleranceType.Absolute);
        widened.Freeze();
        return widened;
    }

    private static SourceRect? SelectedResizableBounds(
        ScreenshotAnnotationEditor editor,
        IReadOnlyList<ScreenshotAnnotation> annotations)
    {
        var selected = editor.Selection.Ids.ToHashSet();
        var bounds = annotations
            .Where(annotation => selected.Contains(annotation.Id)
                && annotation.Kind != AnnotationKind.Mosaic)
            .Select(static annotation => annotation.Bounds)
            .ToArray();
        return bounds.Length == 0
            ? null
            : bounds.Aggregate(static (current, next) => current.Union(next));
    }

    private void DrawAnnotationSelection(
        DrawingContext drawingContext,
        SourceRect bounds,
        PixelRect selection)
    {
        var presentation = AnnotationSelectionPresentation.Calculate(bounds);
        var pen = new Pen(
            ToBrush(presentation.BorderColor),
            ScaleSourceLength(presentation.BorderThickness))
        {
            DashStyle = new DashStyle(presentation.DashPattern, 0),
        };
        pen.Freeze();
        drawingContext.DrawRectangle(null, pen, SourceToLocal(bounds, selection));
        foreach (var handle in presentation.Handles)
        {
            drawingContext.DrawRectangle(
                ToBrush(presentation.HandleFillColor),
                new Pen(ToBrush(presentation.BorderColor), presentation.HandleBorderThickness),
                SourceToLocal(handle.Bounds, selection));
        }
    }

    private void DrawDimensionLabel(DrawingContext drawingContext, PixelRect selection)
    {
        var anchor = new PixelPoint(selection.Left, selection.Top);
        if (!ToDomainRect(frame.Bounds).Contains(anchor))
        {
            return;
        }
        var text = CreateText(
            $"{selection.Width} × {selection.Height}",
            11,
            WhiteBrush,
            FontWeights.Medium,
            "Cascadia Mono");
        var topLeft = PhysicalToLocal(selection.Left, selection.Top);
        var x = Math.Clamp(topLeft.X, 4, Math.Max(4, ActualWidth - text.Width - 8));
        var y = Math.Clamp(topLeft.Y - 20, 4, Math.Max(4, ActualHeight - text.Height - 4));
        var box = new Rect(x - 3, y - 1, text.Width + 6, text.Height + 2);
        drawingContext.DrawRectangle(
            FrozenBrush(Color.FromArgb(235, 27, 171, 89)),
            null,
            box);
        drawingContext.DrawText(text, new Point(x, y));
    }

    private Pen StylePen(AnnotationStyle style, double opacity)
    {
        var pen = new Pen(
            WithOpacity(ToBrush(style.Color), opacity),
            ScaleSourceLength(style.LineWidth))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        return pen;
    }

    private FormattedText CreateText(
        string text,
        double fontSize,
        Brush brush,
        FontWeight weight,
        string family) => new(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily(family), FontStyles.Normal, weight, FontStretches.Normal),
            fontSize,
            brush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private Point PhysicalToLocal(double x, double y) => new(
        (x - frame.Bounds.Left) * Math.Max(ActualWidth, 1) / frame.Bounds.Width,
        (y - frame.Bounds.Top) * Math.Max(ActualHeight, 1) / frame.Bounds.Height);

    private Rect PhysicalToLocal(PixelRect rect)
    {
        var topLeft = PhysicalToLocal(rect.Left, rect.Top);
        var bottomRight = PhysicalToLocal(rect.Right, rect.Bottom);
        return new Rect(topLeft, bottomRight);
    }

    private Rect SourceToLocal(SourceRect rect, PixelRect selection)
    {
        var topLeft = SourceToLocal(new SourcePoint(rect.Left, rect.Top), selection);
        var bottomRight = SourceToLocal(new SourcePoint(rect.Right, rect.Bottom), selection);
        return new Rect(topLeft, bottomRight);
    }

    private double ScaleSourceLength(double value)
    {
        var xScale = Math.Max(ActualWidth, 1) / frame.Bounds.Width;
        var yScale = Math.Max(ActualHeight, 1) / frame.Bounds.Height;
        return value * Math.Min(xScale, yScale);
    }

    private double ScaleLineWidth(double physicalWidth) => ScaleSourceLength(physicalWidth);

    private static IReadOnlyList<PixelRect> BuildOutsideMasks(PixelRect viewport, PixelRect selection)
    {
        var masks = new List<PixelRect>(4);
        Add(new PixelRect(viewport.Left, viewport.Top, viewport.Width, selection.Top - viewport.Top));
        Add(new PixelRect(viewport.Left, selection.Top, selection.Left - viewport.Left, selection.Height));
        Add(new PixelRect(selection.Right, selection.Top, viewport.Right - selection.Right, selection.Height));
        Add(new PixelRect(viewport.Left, selection.Bottom, viewport.Width, viewport.Bottom - selection.Bottom));
        return masks;

        void Add(PixelRect rect)
        {
            if (!rect.IsEmpty)
            {
                masks.Add(rect);
            }
        }
    }

    private static IReadOnlyList<SelectionHandlePresentation> GlobalSelectionHandles(PixelRect rect)
    {
        var size = ScreenshotSelectionPresentation.HandleSize;
        var half = size / 2;
        var middleX = rect.Left + (rect.Width / 2);
        var middleY = rect.Top + (rect.Height / 2);
        return
        [
            Handle(ScreenshotResizeHandle.TopLeft, rect.Left, rect.Top),
            Handle(ScreenshotResizeHandle.Top, middleX, rect.Top),
            Handle(ScreenshotResizeHandle.TopRight, rect.Right, rect.Top),
            Handle(ScreenshotResizeHandle.Left, rect.Left, middleY),
            Handle(ScreenshotResizeHandle.Right, rect.Right, middleY),
            Handle(ScreenshotResizeHandle.BottomLeft, rect.Left, rect.Bottom),
            Handle(ScreenshotResizeHandle.Bottom, middleX, rect.Bottom),
            Handle(ScreenshotResizeHandle.BottomRight, rect.Right, rect.Bottom),
        ];

        SelectionHandlePresentation Handle(ScreenshotResizeHandle handle, int x, int y) =>
            new(handle, new PixelRect(x - half, y - half, size, size));
    }

    private static PixelRect ToDomainRect(CapturePixelRect rect) =>
        new(rect.Left, rect.Top, rect.Width, rect.Height);

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static SolidColorBrush WithOpacity(SolidColorBrush source, double opacity) =>
        FrozenBrush(Color.FromArgb(
            checked((byte)Math.Round(source.Color.A * Math.Clamp(opacity, 0, 1))),
            source.Color.R,
            source.Color.G,
            source.Color.B));
}
