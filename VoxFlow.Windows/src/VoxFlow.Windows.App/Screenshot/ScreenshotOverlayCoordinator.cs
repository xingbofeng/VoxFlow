using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using System.Globalization;
using VoxFlow.Windows.Application.Screenshots;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Platform.Screenshot;
using Cursor = System.Windows.Input.Cursor;
using Cursors = System.Windows.Input.Cursors;
using WpfMouseButton = System.Windows.Input.MouseButton;

namespace VoxFlow.Windows.App.Screenshot;

public sealed record ScreenshotOverlayResult(
    Guid RunId,
    ScreenshotCompletionKind CompletionKind,
    PixelRect Selection,
    FrozenScreenshot Image,
    ScreenshotDocument Document,
    IReadOnlyList<ScreenshotInlineTranslationLine> InlineTranslationLines,
    string? SourceWindowTitle = null);

internal enum ScreenshotEscapeDisposition
{
    CancelTextDraft,
    CloseStylePopover,
    CancelAnnotationPreview,
    ClearAnnotationSelection,
    CancelSession,
}

/// <summary>
/// Owns one frozen-desktop editing session. Capture is deliberately absent
/// from this type so no overlay can ever appear in a captured frame.
/// </summary>
public sealed class ScreenshotOverlayCoordinator : IDisposable
{
    private enum PointerInteraction
    {
        None,
        WindowCandidate,
        DesktopSelection,
        AnnotationGesture,
        AnnotationMove,
        AnnotationResize,
        AnnotationMarquee,
    }

    private readonly WindowTargetCatalog targetCatalog;
    private readonly List<ScreenshotOverlayWindow> windows = [];
    private readonly Dispatcher dispatcher;
    private readonly IScreenshotInlineTranslationService? inlineTranslation;
    private readonly ScreenshotKeyboardHookRouter keyboardRouter;
    private readonly IScreenshotWindowActivation windowActivation;
    private FrozenDesktop? desktop;
    private ScreenshotSelectionState? selectionState;
    private ScreenshotAnnotationEditor? annotationEditor;
    private ScreenshotToolbarWindow? toolbar;
    private TaskCompletionSource<ScreenshotOverlayResult?>? completion;
    private CancellationTokenRegistration cancellationRegistration;
    private IReadOnlyList<WindowCaptureTarget> windowTargets = [];
    private Guid runId;
    private PixelPoint? lastPointer;
    private PointerInteraction pointerInteraction;
    private ScreenshotOverlayWindow? pointerWindow;
    private PixelPoint pointerStart;
    private SourcePoint annotationStart;
    private readonly List<SourcePoint> annotationPoints = [];
    private ScreenshotAnnotation? previewAnnotation;
    private IReadOnlyList<ScreenshotAnnotation>? annotationTransformPreview;
    private AnnotationResizeHandle? annotationResizeHandle;
    private FrozenScreenshot? annotationSourceImage;
    private PixelRect? annotationSourceRegion;
    private bool disposed;
    private CancellationToken sessionCancellation;
    private CancellationTokenSource? inlineTranslationCancellation;
    private IReadOnlyList<ScreenshotInlineTranslationLine> inlineTranslationLines = [];
    private bool isInlineTranslationVisible;
    private string? sourceWindowTitle;
    private ScreenshotInlineTranslationPresentationKind inlineTranslationPresentation;
    private string? inlineTranslationStatusText;
    private ScreenshotDocument? observedAnnotationDocument;
    private long annotationGeneration;
    private ScreenshotKeyboardHookRouter.ScreenshotKeyboardHookSession? keyboardSession;
    private nint savedForegroundWindow;
    private nint pendingForegroundWindow;
    private bool toolbarKeyboardMode;

    public ScreenshotOverlayCoordinator()
        : this(
            new WindowTargetCatalog(),
            Dispatcher.CurrentDispatcher,
            inlineTranslation: null,
            new ScreenshotKeyboardHookRouter(),
            WindowsScreenshotWindowActivation.Shared)
    {
    }

    public ScreenshotOverlayCoordinator(IScreenshotInlineTranslationService? inlineTranslation)
        : this(
            new WindowTargetCatalog(),
            Dispatcher.CurrentDispatcher,
            inlineTranslation,
            new ScreenshotKeyboardHookRouter(),
            WindowsScreenshotWindowActivation.Shared)
    {
    }

    public ScreenshotOverlayCoordinator(
        IScreenshotInlineTranslationService? inlineTranslation,
        ScreenshotKeyboardHookRouter keyboardRouter)
        : this(
            new WindowTargetCatalog(),
            Dispatcher.CurrentDispatcher,
            inlineTranslation,
            keyboardRouter,
            WindowsScreenshotWindowActivation.Shared)
    {
    }

    internal ScreenshotOverlayCoordinator(
        WindowTargetCatalog targetCatalog,
        Dispatcher dispatcher,
        IScreenshotInlineTranslationService? inlineTranslation = null,
        ScreenshotKeyboardHookRouter? keyboardRouter = null,
        IScreenshotWindowActivation? windowActivation = null)
    {
        this.targetCatalog = targetCatalog ?? throw new ArgumentNullException(nameof(targetCatalog));
        this.dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        this.inlineTranslation = inlineTranslation;
        this.keyboardRouter = keyboardRouter ?? new ScreenshotKeyboardHookRouter();
        this.windowActivation = windowActivation ?? WindowsScreenshotWindowActivation.Shared;
    }

    public bool IsActive => completion is not null;

    /// <summary>
    /// Snapshots the foreground owner synchronously at command dispatch time so
    /// a slower desktop freeze cannot replace it with an application window.
    /// </summary>
    public void PreserveForegroundWindow()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!dispatcher.CheckAccess())
        {
            throw new InvalidOperationException(
                "The screenshot foreground window must be preserved on the WPF UI thread.");
        }

        pendingForegroundWindow = windowActivation.CaptureForegroundWindow();
    }

    public Task<ScreenshotOverlayResult?> RunAsync(
        FrozenDesktop frozenDesktop,
        Guid screenshotRunId,
        ScreenshotOverlayResult? resumeState = null,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(frozenDesktop);
        if (screenshotRunId == Guid.Empty)
        {
            throw new ArgumentException("A screenshot run identifier is required.", nameof(screenshotRunId));
        }
        if (!dispatcher.CheckAccess())
        {
            throw new InvalidOperationException("The screenshot overlay must start on the WPF UI thread.");
        }
        if (completion is not null)
        {
            throw new InvalidOperationException("A screenshot overlay session is already active.");
        }
        if (resumeState is not null && resumeState.RunId != screenshotRunId)
        {
            throw new ArgumentException(
                "The resumed screenshot must belong to the active run.",
                nameof(resumeState));
        }

        desktop = frozenDesktop;
        runId = screenshotRunId;
        completion = new TaskCompletionSource<ScreenshotOverlayResult?>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        selectionState = ScreenshotSelectionState.Create(CreateLayout(frozenDesktop));
        if (resumeState is not null)
        {
            var resumedRegion = resumeState.Selection.Intersection(selectionState.Layout.VirtualBounds);
            if (resumedRegion.IsEmpty
                || resumeState.Document.CanvasSize != resumedRegion.Size)
            {
                throw new ArgumentException(
                    "The resumed selection is outside the frozen desktop.",
                    nameof(resumeState));
            }
            selectionState = selectionState.WithRegion(resumedRegion);
            annotationEditor = new ScreenshotAnnotationEditor(resumeState.Document);
        }
        else
        {
            annotationEditor = null;
        }
        observedAnnotationDocument = annotationEditor?.Document;
        annotationGeneration = 0;
        windowTargets = targetCatalog.GetTargets();
        pointerInteraction = PointerInteraction.None;
        previewAnnotation = null;
        annotationPoints.Clear();
        sessionCancellation = cancellationToken;
        inlineTranslationLines = resumeState?.InlineTranslationLines.ToArray() ?? [];
        isInlineTranslationVisible = inlineTranslationLines.Count > 0;
        sourceWindowTitle = resumeState?.SourceWindowTitle;
        inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.None;
        inlineTranslationStatusText = null;
        savedForegroundWindow = pendingForegroundWindow != nint.Zero
            ? pendingForegroundWindow
            : windowActivation.CaptureForegroundWindow();
        keyboardSession = keyboardRouter.BeginSession(HandleKeyboardCommand);
        toolbarKeyboardMode = false;

        try
        {
            foreach (var frame in frozenDesktop.Frames)
            {
                var window = new ScreenshotOverlayWindow(
                    frame,
                    windowActivation,
                    savedForegroundWindow,
                    OnTextEditingActivationChanged);
                window.PointerPressed += OnPointerPressed;
                window.PointerMoved += OnPointerMoved;
                window.PointerReleased += OnPointerReleased;
                window.KeyPressed += OnKeyPressed;
                window.TextCommitted += OnTextCommitted;
                windows.Add(window);
                window.Show();
            }

            RefreshVisuals();
            _ = windowActivation.RestoreForegroundWindow(savedForegroundWindow);
            if (resumeState is not null)
            {
                ShowOrPlaceToolbar();
            }
            if (cancellationToken.CanBeCanceled)
            {
                cancellationRegistration = cancellationToken.Register(() =>
                    _ = dispatcher.BeginInvoke(
                        DispatcherPriority.Send,
                        new Action(CancelSession)));
            }
            return completion.Task;
        }
        catch
        {
            CleanupWindows();
            completion = null;
            desktop = null;
            selectionState = null;
            throw;
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        if (dispatcher.CheckAccess())
        {
            CancelSession();
        }
        else
        {
            _ = dispatcher.InvokeAsync(CancelSession, DispatcherPriority.Send);
        }
    }

    private void OnPointerPressed(object? sender, ScreenshotPointerEventArgs eventArgs)
    {
        if (selectionState is null || sender is not ScreenshotOverlayWindow window)
        {
            return;
        }
        ExitToolbarKeyboardMode(restoreForeground: true);
        toolbar?.DismissStylePopover();
        lastPointer = eventArgs.Point;
        if (eventArgs.Button == WpfMouseButton.Right)
        {
            CancelSession();
            return;
        }
        if (eventArgs.Button != WpfMouseButton.Left)
        {
            return;
        }
        if (eventArgs.ClickCount >= 2
            && selectionState.EffectiveRegion?.Contains(eventArgs.Point) == true)
        {
            RememberWindowCandidate(selectionState.WindowCandidate);
            CompleteSession(ScreenshotCompletionKind.Complete);
            return;
        }

        pointerWindow = window;
        pointerStart = eventArgs.Point;
        if (selectionState.Region is null
            && selectionState.IsWindowSnapEnabled
            && selectionState.WindowCandidate is not null)
        {
            pointerInteraction = PointerInteraction.WindowCandidate;
            window.CapturePointer();
            return;
        }

        if (selectionState.EffectiveRegion is not { IsEmpty: false } region)
        {
            ResetAnnotationsForNewSelection();
            selectionState = selectionState.BeginRegionDrag(eventArgs.Point);
            pointerInteraction = PointerInteraction.DesktopSelection;
            window.CapturePointer();
            RefreshVisuals();
            return;
        }

        EnsureAnnotationEditor();
        var source = ToSource(eventArgs.Point, region);
        var activeTool = toolbar?.ViewModel.ActiveTool ?? ScreenshotTool.Select;
        if (activeTool == ScreenshotTool.Text && region.Contains(eventArgs.Point))
        {
            var existing = FindEditableText(annotationEditor!.Document.Annotations, source);
            if (existing is not null)
            {
                annotationEditor.Select([existing.Id]);
                RefreshVisuals();
                var globalPosition = new PixelPoint(
                    region.Left + checked((int)Math.Round(existing.Position.X)),
                    region.Top + checked((int)Math.Round(existing.Position.Y)));
                var editingWindow = windows.FirstOrDefault(candidate =>
                    ToDomainRect(candidate.Frame.Bounds).Contains(globalPosition)) ?? window;
                editingWindow.BeginTextEditing(
                    existing.Position,
                    region,
                    existing.Style,
                    existing.Content,
                    existing.Id);
            }
            else
            {
                window.BeginTextEditing(
                    source,
                    region,
                    annotationEditor.CurrentTextStyle);
            }
            return;
        }
        if (activeTool is not ScreenshotTool.Select
            && activeTool is not ScreenshotTool.TextRecognition
            && activeTool is not ScreenshotTool.Translate
            && region.Contains(eventArgs.Point))
        {
            annotationStart = source;
            annotationPoints.Clear();
            annotationPoints.Add(source);
            pointerInteraction = PointerInteraction.AnnotationGesture;
            window.CapturePointer();
            UpdateAnnotationPreview(activeTool);
            RefreshVisuals();
            return;
        }

        if (annotationEditor is not null
            && annotationEditor.Document.Annotations.Count > 0
            && region.Contains(eventArgs.Point))
        {
            var resizeHandle = FindAnnotationHandle(annotationEditor.SelectedResizableBounds, source);
            if (resizeHandle is not null)
            {
                annotationResizeHandle = resizeHandle;
                annotationStart = source;
                pointerInteraction = PointerInteraction.AnnotationResize;
                window.CapturePointer();
                return;
            }

            var hit = AnnotationHitTester.HitTest(annotationEditor.Document.Annotations, source);
            if (hit is not null)
            {
                annotationEditor.SelectAt(
                    source,
                    eventArgs.Modifiers.HasFlag(ModifierKeys.Shift));
                annotationStart = source;
                pointerInteraction = PointerInteraction.AnnotationMove;
                window.CapturePointer();
                RefreshVisuals();
                return;
            }

            if (eventArgs.Modifiers.HasFlag(ModifierKeys.Shift))
            {
                annotationStart = source;
                pointerInteraction = PointerInteraction.AnnotationMarquee;
                window.CapturePointer();
                annotationEditor.Select([]);
                RefreshVisuals();
                return;
            }
            annotationEditor.Select([]);
        }

        var selectionHandle = annotationEditor?.Document.Annotations.Count > 0
            ? null
            : FindSelectionHandle(region, eventArgs.Point);
        if (selectionHandle is not null)
        {
            sourceWindowTitle = null;
            InvalidateInlineTranslation();
            selectionState = selectionState.BeginResize(selectionHandle.Value);
        }
        else if (region.Contains(eventArgs.Point))
        {
            sourceWindowTitle = null;
            InvalidateInlineTranslation();
            selectionState = selectionState.BeginMove(eventArgs.Point);
        }
        else
        {
            InvalidateInlineTranslation();
            ResetAnnotationsForNewSelection();
            selectionState = selectionState.BeginRegionDrag(eventArgs.Point);
        }
        pointerInteraction = PointerInteraction.DesktopSelection;
        window.CapturePointer();
        RefreshVisuals();
    }

    private void OnPointerMoved(object? sender, ScreenshotPointerEventArgs eventArgs)
    {
        if (selectionState is null)
        {
            return;
        }
        lastPointer = eventArgs.Point;
        switch (pointerInteraction)
        {
            case PointerInteraction.WindowCandidate:
                if (!ScreenshotOverlayInputPolicy.ShouldBeginFreeRegionFromWindowCandidate(
                        pointerStart,
                        eventArgs.Point))
                {
                    return;
                }
                ResetAnnotationsForNewSelection();
                selectionState = selectionState
                    .WithWindowCandidate(null)
                    .BeginRegionDrag(pointerStart)
                    .UpdatePointer(eventArgs.Point);
                pointerInteraction = PointerInteraction.DesktopSelection;
                HideToolbar();
                RefreshVisuals();
                return;
            case PointerInteraction.DesktopSelection:
                selectionState = selectionState.UpdatePointer(eventArgs.Point);
                HideToolbar();
                RefreshVisuals();
                return;
            case PointerInteraction.AnnotationGesture:
            {
                if (selectionState.EffectiveRegion is not { } region)
                {
                    return;
                }
                annotationPoints.Add(ClampSource(ToSource(eventArgs.Point, region), region.Size));
                UpdateAnnotationPreview(toolbar?.ViewModel.ActiveTool ?? ScreenshotTool.Select);
                RefreshVisuals();
                return;
            }
            case PointerInteraction.AnnotationMove:
                UpdateAnnotationMovePreview(eventArgs.Point);
                RefreshVisuals();
                return;
            case PointerInteraction.AnnotationResize:
                UpdateAnnotationResizePreview(eventArgs.Point);
                RefreshVisuals();
                return;
            case PointerInteraction.AnnotationMarquee:
                UpdateCursor(eventArgs.Point);
                return;
            case PointerInteraction.None:
            default:
                UpdateWindowCandidate(eventArgs.Point);
                UpdateCursor(eventArgs.Point);
                return;
        }
    }

    private void OnPointerReleased(object? sender, ScreenshotPointerEventArgs eventArgs)
    {
        if (selectionState is null || eventArgs.Button != WpfMouseButton.Left)
        {
            return;
        }
        pointerWindow?.ReleasePointer();
        try
        {
            switch (pointerInteraction)
            {
                case PointerInteraction.WindowCandidate:
                    if (selectionState.WindowCandidate is { } candidate)
                    {
                        RememberWindowCandidate(candidate);
                        selectionState = selectionState.WithRegion(
                            candidate.Bounds.Intersection(selectionState.Layout.VirtualBounds));
                        InvalidateInlineTranslation();
                        EnsureAnnotationEditor();
                    }
                    break;
                case PointerInteraction.DesktopSelection:
                    selectionState = selectionState.UpdatePointer(eventArgs.Point).EndPointer();
                    EnsureAnnotationEditor();
                    break;
                case PointerInteraction.AnnotationGesture:
                    CommitAnnotationGesture(eventArgs.Point);
                    break;
                case PointerInteraction.AnnotationMove:
                    CommitAnnotationMove(eventArgs.Point);
                    break;
                case PointerInteraction.AnnotationResize:
                    CommitAnnotationResize(eventArgs.Point);
                    break;
                case PointerInteraction.AnnotationMarquee:
                    CommitAnnotationMarquee(eventArgs.Point, eventArgs.Modifiers);
                    break;
                case PointerInteraction.None:
                default:
                    break;
            }
        }
        finally
        {
            pointerInteraction = PointerInteraction.None;
            pointerWindow = null;
            previewAnnotation = null;
            annotationTransformPreview = null;
            annotationPoints.Clear();
            annotationResizeHandle = null;
        }
        ShowOrPlaceToolbar();
        RefreshVisuals();
    }

    private void HandleKeyboardCommand(ScreenshotKeyboardCommand command)
    {
        if (selectionState is null)
        {
            return;
        }
        if (command == ScreenshotKeyboardCommand.FocusToolbar)
        {
            if (toolbarKeyboardMode)
            {
                toolbar?.DismissStylePopover(restoreFocus: false);
                ExitToolbarKeyboardMode(restoreForeground: true);
            }
            else
            {
                _ = EnterToolbarKeyboardMode(backward: false);
            }
            return;
        }
        if (toolbarKeyboardMode && toolbar is not null)
        {
            switch (command)
            {
                case ScreenshotKeyboardCommand.TabForward:
                    _ = toolbar.MoveKeyboardFocus(1);
                    return;
                case ScreenshotKeyboardCommand.TabBackward:
                    _ = toolbar.MoveKeyboardFocus(-1);
                    return;
                case ScreenshotKeyboardCommand.MoveLeft:
                case ScreenshotKeyboardCommand.MoveUp:
                    _ = toolbar.MoveKeyboardFocus(-1);
                    return;
                case ScreenshotKeyboardCommand.MoveRight:
                case ScreenshotKeyboardCommand.MoveDown:
                    _ = toolbar.MoveKeyboardFocus(1);
                    return;
                case ScreenshotKeyboardCommand.ActivateToolbarItem:
                    _ = toolbar.InvokeKeyboardFocusedButton();
                    return;
            }
        }

        var eventArgs = command switch
        {
            ScreenshotKeyboardCommand.TabForward => new ScreenshotKeyEventArgs(
                Key.Tab,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.TabBackward => new ScreenshotKeyEventArgs(
                Key.Tab,
                ModifierKeys.Shift),
            ScreenshotKeyboardCommand.FullDisplay => new ScreenshotKeyEventArgs(
                Key.F,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.MoveLeft => new ScreenshotKeyEventArgs(
                Key.Left,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.MoveRight => new ScreenshotKeyEventArgs(
                Key.Right,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.MoveUp => new ScreenshotKeyEventArgs(
                Key.Up,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.MoveDown => new ScreenshotKeyEventArgs(
                Key.Down,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.Complete => new ScreenshotKeyEventArgs(
                Key.Enter,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.Escape => new ScreenshotKeyEventArgs(
                Key.Escape,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.Delete => new ScreenshotKeyEventArgs(
                Key.Delete,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.Backspace => new ScreenshotKeyEventArgs(
                Key.Back,
                ModifierKeys.None),
            ScreenshotKeyboardCommand.Copy => new ScreenshotKeyEventArgs(
                Key.C,
                ModifierKeys.Control),
            ScreenshotKeyboardCommand.Paste => new ScreenshotKeyEventArgs(
                Key.V,
                ModifierKeys.Control),
            ScreenshotKeyboardCommand.Duplicate => new ScreenshotKeyEventArgs(
                Key.D,
                ModifierKeys.Control),
            ScreenshotKeyboardCommand.Undo => new ScreenshotKeyEventArgs(
                Key.Z,
                ModifierKeys.Control),
            ScreenshotKeyboardCommand.Redo => new ScreenshotKeyEventArgs(
                Key.Z,
                ModifierKeys.Control | ModifierKeys.Shift),
            ScreenshotKeyboardCommand.ActivateToolbarItem => null,
            ScreenshotKeyboardCommand.FocusToolbar => null,
            _ => throw new ArgumentOutOfRangeException(nameof(command), command, null),
        };
        if (eventArgs is not null)
        {
            OnKeyPressed(sender: null, eventArgs);
        }
    }

    private void OnKeyPressed(object? sender, ScreenshotKeyEventArgs eventArgs)
    {
        if (selectionState is null)
        {
            return;
        }
        if (eventArgs.Key == Key.F6)
        {
            if (toolbarKeyboardMode || ReferenceEquals(sender, toolbar))
            {
                toolbar?.DismissStylePopover(restoreFocus: false);
                ExitToolbarKeyboardMode(restoreForeground: true);
            }
            else
            {
                _ = EnterToolbarKeyboardMode(backward: false);
            }
            eventArgs.Handled = true;
            return;
        }
        if (eventArgs.Key == Key.Escape && DismissTransientOverlayState())
        {
            eventArgs.Handled = true;
            return;
        }
        var control = eventArgs.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = eventArgs.Modifiers.HasFlag(ModifierKeys.Shift);
        if (control)
        {
            switch (eventArgs.Key)
            {
                case Key.C:
                    switch (ScreenshotOverlayInputPolicy.ResolveCopyShortcut(
                        selectionState.HasValidRegion,
                        annotationEditor?.Selection.Ids.Count ?? 0))
                    {
                        case ScreenshotCopyShortcutAction.CompleteSelection:
                            CompleteSession(ScreenshotCompletionKind.Complete);
                            break;
                        case ScreenshotCopyShortcutAction.CopySelectedAnnotations:
                            annotationEditor?.CopySelection();
                            break;
                        case ScreenshotCopyShortcutAction.Ignore:
                            break;
                        default:
                            throw new ArgumentOutOfRangeException(nameof(eventArgs));
                    }
                    eventArgs.Handled = true;
                    return;
                case Key.V:
                    if (annotationEditor?.Paste() == true)
                    {
                        RefreshVisuals();
                    }
                    eventArgs.Handled = true;
                    return;
                case Key.D:
                    if (annotationEditor?.DuplicateSelection() == true)
                    {
                        RefreshVisuals();
                    }
                    eventArgs.Handled = true;
                    return;
                case Key.Z when shift:
                    annotationEditor?.Redo();
                    RefreshVisuals();
                    eventArgs.Handled = true;
                    return;
                case Key.Z:
                    annotationEditor?.Undo();
                    RefreshVisuals();
                    eventArgs.Handled = true;
                    return;
                case Key.Y:
                    annotationEditor?.Redo();
                    RefreshVisuals();
                    eventArgs.Handled = true;
                    return;
            }
        }

        ScreenshotSelectionCommand? command = eventArgs.Key switch
        {
            Key.Tab => ScreenshotSelectionCommand.ToggleWindowSnap,
            Key.F => ScreenshotSelectionCommand.FullDisplay,
            Key.Left => ScreenshotSelectionCommand.MoveLeft,
            Key.Right => ScreenshotSelectionCommand.MoveRight,
            Key.Up => ScreenshotSelectionCommand.MoveUp,
            Key.Down => ScreenshotSelectionCommand.MoveDown,
            Key.Enter => ScreenshotSelectionCommand.Complete,
            Key.Escape => ScreenshotSelectionCommand.Cancel,
            _ => null,
        };
        if (eventArgs.Key == Key.Delete || eventArgs.Key == Key.Back)
        {
            annotationEditor?.DeleteSelection();
            RefreshVisuals();
            eventArgs.Handled = true;
            return;
        }
        if (command is null)
        {
            return;
        }

        if (command is ScreenshotSelectionCommand.FullDisplay
            or ScreenshotSelectionCommand.MoveLeft
            or ScreenshotSelectionCommand.MoveRight
            or ScreenshotSelectionCommand.MoveUp
            or ScreenshotSelectionCommand.MoveDown)
        {
            sourceWindowTitle = null;
            InvalidateInlineTranslation();
        }

        var commandWindowCandidate = selectionState.WindowCandidate;
        var transition = selectionState.Apply(command.Value, lastPointer);
        selectionState = transition.State;
        eventArgs.Handled = true;
        if (transition.Outcome == ScreenshotSelectionOutcome.Cancelled)
        {
            CancelSession();
        }
        else if (transition.Outcome == ScreenshotSelectionOutcome.Completed)
        {
            RememberWindowCandidate(commandWindowCandidate);
            CompleteSession(ScreenshotCompletionKind.Complete);
        }
        else
        {
            EnsureAnnotationEditor();
            if (command == ScreenshotSelectionCommand.ToggleWindowSnap
                && selectionState.IsWindowSnapEnabled
                && lastPointer is { } pointer)
            {
                UpdateWindowCandidate(pointer);
            }
            ShowOrPlaceToolbar();
            RefreshVisuals();
        }
    }

    private void OnTextCommitted(object? sender, ScreenshotTextCommittedEventArgs eventArgs)
    {
        if (annotationEditor is not null
            && eventArgs.AnnotationId is { } annotationId)
        {
            _ = annotationEditor.UpdateText(annotationId, eventArgs.Text);
        }
        else if (annotationEditor is not null && !string.IsNullOrWhiteSpace(eventArgs.Text))
        {
            _ = annotationEditor.TryAddGesture(
                ScreenshotTool.Text,
                eventArgs.Position,
                [],
                eventArgs.Text);
        }
        RefreshVisuals();
    }

    private bool DismissTransientOverlayState()
    {
        var textWindow = windows.FirstOrDefault(window => window.TextEditor is not null);
        var annotationPreviewActive = pointerInteraction is PointerInteraction.AnnotationGesture
            or PointerInteraction.AnnotationMove
            or PointerInteraction.AnnotationResize
            or PointerInteraction.AnnotationMarquee;
        switch (ResolveEscapeDisposition(
                    textWindow is not null,
                    toolbar?.IsStylePopoverOpen == true,
                    annotationPreviewActive,
                    (annotationEditor?.Selection.Ids.Count ?? 0) > 0))
        {
            case ScreenshotEscapeDisposition.CancelTextDraft:
                textWindow!.CancelTextEditing();
                return true;
            case ScreenshotEscapeDisposition.CloseStylePopover:
                toolbar!.DismissStylePopover(restoreFocus: true);
                return true;
            case ScreenshotEscapeDisposition.CancelAnnotationPreview:
                pointerWindow?.ReleasePointer();
                pointerInteraction = PointerInteraction.None;
                pointerWindow = null;
                previewAnnotation = null;
                annotationTransformPreview = null;
                annotationPoints.Clear();
                annotationResizeHandle = null;
                ShowOrPlaceToolbar();
                RefreshVisuals();
                return true;
            case ScreenshotEscapeDisposition.ClearAnnotationSelection:
                annotationEditor!.Select([]);
                RefreshVisuals();
                return true;
            case ScreenshotEscapeDisposition.CancelSession:
                return false;
            default:
                throw new ArgumentOutOfRangeException();
        }
    }

    internal static ScreenshotEscapeDisposition ResolveEscapeDisposition(
        bool hasTextDraft,
        bool hasStylePopover,
        bool hasAnnotationPreview,
        bool hasAnnotationSelection)
    {
        if (hasTextDraft)
        {
            return ScreenshotEscapeDisposition.CancelTextDraft;
        }
        if (hasStylePopover)
        {
            return ScreenshotEscapeDisposition.CloseStylePopover;
        }
        if (hasAnnotationPreview)
        {
            return ScreenshotEscapeDisposition.CancelAnnotationPreview;
        }
        return hasAnnotationSelection
            ? ScreenshotEscapeDisposition.ClearAnnotationSelection
            : ScreenshotEscapeDisposition.CancelSession;
    }

    private void OnToolbarInvoked(object? sender, ScreenshotToolbarInvokedEventArgs eventArgs)
    {
        EnsureAnnotationEditor();
        switch (eventArgs.Action)
        {
            case ScreenshotToolbarAction.Select:
            case ScreenshotToolbarAction.Pen:
            case ScreenshotToolbarAction.Ellipse:
            case ScreenshotToolbarAction.Rectangle:
            case ScreenshotToolbarAction.Arrow:
            case ScreenshotToolbarAction.DotMarker:
            case ScreenshotToolbarAction.NumberedMarker:
            case ScreenshotToolbarAction.Text:
            case ScreenshotToolbarAction.Mosaic:
                break;
            case ScreenshotToolbarAction.TextRecognition:
                CompleteSession(ScreenshotCompletionKind.TextRecognition);
                return;
            case ScreenshotToolbarAction.Translate:
                _ = ToggleInlineTranslationAsync();
                return;
            case ScreenshotToolbarAction.Color when eventArgs.Value is AnnotationColor color:
                annotationEditor?.ApplyColor(color);
                break;
            case ScreenshotToolbarAction.LineWidth when eventArgs.Value is double lineWidth:
                annotationEditor?.ApplyLineWidth(lineWidth);
                break;
            case ScreenshotToolbarAction.FontSize when eventArgs.Value is double fontSize:
                annotationEditor?.ApplyFontSize(fontSize);
                break;
            case ScreenshotToolbarAction.Color:
            case ScreenshotToolbarAction.LineWidth:
            case ScreenshotToolbarAction.FontSize:
                break;
            case ScreenshotToolbarAction.Copy:
                annotationEditor?.CopySelection();
                break;
            case ScreenshotToolbarAction.Paste:
                _ = annotationEditor?.Paste();
                break;
            case ScreenshotToolbarAction.Duplicate:
                _ = annotationEditor?.DuplicateSelection();
                break;
            case ScreenshotToolbarAction.Undo:
                annotationEditor?.Undo();
                break;
            case ScreenshotToolbarAction.Redo:
                annotationEditor?.Redo();
                break;
            case ScreenshotToolbarAction.Download:
                CompleteSession(ScreenshotCompletionKind.Download);
                return;
            case ScreenshotToolbarAction.Cancel:
                CancelSession();
                return;
            case ScreenshotToolbarAction.Complete:
                CompleteSession(ScreenshotCompletionKind.Complete);
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(eventArgs));
        }
        RefreshVisuals();
    }

    private async Task ToggleInlineTranslationAsync()
    {
        foreach (var window in windows)
        {
            window.CommitTextEditing();
        }
        if (inlineTranslationCancellation is not null)
        {
            inlineTranslationCancellation.Cancel();
            inlineTranslationLines = [];
            isInlineTranslationVisible = false;
            inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.None;
            inlineTranslationStatusText = null;
            toolbar?.ViewModel.SelectTool(ScreenshotTool.Select);
            RefreshVisuals();
            return;
        }
        if (inlineTranslationLines.Count > 0)
        {
            isInlineTranslationVisible = !isInlineTranslationVisible;
            toolbar?.ViewModel.SelectTool(
                isInlineTranslationVisible ? ScreenshotTool.Translate : ScreenshotTool.Select);
            RefreshVisuals();
            return;
        }
        if (inlineTranslation is null
            || desktop is null
            || selectionState?.EffectiveRegion is not { IsEmpty: false } region
            || completion is null)
        {
            return;
        }

        var requestRunId = runId;
        var rawCrop = desktop.Crop(new CapturePixelRect(
            region.Left,
            region.Top,
            region.Width,
            region.Height));
        EnsureAnnotationEditor();
        ObserveAnnotationDocumentChanges();
        var crop = RenderInlineTranslationInput(rawCrop, annotationEditor!.Document);
        var requestAnnotationGeneration = annotationGeneration;
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(sessionCancellation);
        inlineTranslationCancellation = cancellation;
        toolbar?.ViewModel.SelectTool(ScreenshotTool.Translate);
        inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.Loading;
        inlineTranslationStatusText = Localization.L10n.Localize(
            "ScreenshotInlineTranslationInProgress");
        RefreshVisuals();
        var progress = new Progress<ScreenshotInlineTranslationProgress>(update =>
        {
            if (completion is null
                || runId != requestRunId
                || requestAnnotationGeneration != annotationGeneration
                || cancellation.IsCancellationRequested)
            {
                return;
            }
            inlineTranslationLines = update.Lines.ToArray();
            isInlineTranslationVisible = inlineTranslationLines.Count > 0;
            inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.Progress;
            inlineTranslationStatusText = string.Format(
                CultureInfo.CurrentUICulture,
                Localization.L10n.Localize("ScreenshotInlineTranslationProgressFormat"),
                update.Completed,
                update.Total);
            RefreshVisuals();
        });
        try
        {
            var result = await inlineTranslation.TranslateAsync(
                requestRunId,
                $"inline-{requestRunId:N}",
                crop,
                CultureInfo.CurrentUICulture.Name,
                progress,
                cancellation.Token);
            if (completion is not null
                && runId == requestRunId
                && requestAnnotationGeneration == annotationGeneration
                && result.Status is ScreenshotInlineTranslationStatus.Succeeded
                    or ScreenshotInlineTranslationStatus.PartiallyCompleted)
            {
                inlineTranslationLines = result.Lines.ToArray();
                isInlineTranslationVisible = inlineTranslationLines.Count > 0;
                inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.None;
                inlineTranslationStatusText = null;
            }
            else if (completion is not null
                     && runId == requestRunId
                     && requestAnnotationGeneration == annotationGeneration)
            {
                inlineTranslationLines = [];
                isInlineTranslationVisible = false;
                inlineTranslationPresentation = result.Status is
                    ScreenshotInlineTranslationStatus.Cancelled or ScreenshotInlineTranslationStatus.Stale
                        ? ScreenshotInlineTranslationPresentationKind.None
                        : ScreenshotInlineTranslationPresentationKind.Failure;
                inlineTranslationStatusText = result.Status switch
                {
                    ScreenshotInlineTranslationStatus.ProviderUnavailable =>
                        Localization.L10n.Localize("ScreenshotInlineTranslationNotReady"),
                    ScreenshotInlineTranslationStatus.OcrUnavailable =>
                        Localization.L10n.Localize("ScreenshotInlineTranslationOcrUnavailable"),
                    ScreenshotInlineTranslationStatus.Empty =>
                        Localization.L10n.Localize("ScreenshotResultNoText"),
                    ScreenshotInlineTranslationStatus.Failed =>
                        Localization.L10n.Localize("ScreenshotInlineTranslationFailed"),
                    _ => null,
                };
                toolbar?.ViewModel.SelectTool(ScreenshotTool.Select);
            }
        }
        finally
        {
            if (ReferenceEquals(inlineTranslationCancellation, cancellation))
            {
                inlineTranslationCancellation = null;
            }
            cancellation.Dispose();
            if (completion is not null && runId == requestRunId)
            {
                RefreshVisuals();
            }
        }
    }

    private void InvalidateInlineTranslation()
    {
        inlineTranslationCancellation?.Cancel();
        inlineTranslationLines = [];
        isInlineTranslationVisible = false;
        inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.None;
        inlineTranslationStatusText = null;
        if (toolbar?.ViewModel.ActiveTool == ScreenshotTool.Translate)
        {
            toolbar.ViewModel.SelectTool(ScreenshotTool.Select);
        }
    }

    private void UpdateWindowCandidate(PixelPoint point)
    {
        if (selectionState is null
            || selectionState.Region is not null
            || !selectionState.IsWindowSnapEnabled)
        {
            return;
        }

        var candidate = windowTargets.FirstOrDefault(target =>
            target.Bounds.Contains(new CapturePixelPoint(point.X, point.Y)));
        var domainCandidate = candidate is null
            ? null
            : new WindowTargetCandidate(
                candidate.WindowHandle,
                ToDomainRect(candidate.Bounds),
                candidate.ZOrder);
        if (selectionState.WindowCandidate != domainCandidate)
        {
            selectionState = selectionState.WithWindowCandidate(domainCandidate);
            RefreshVisuals();
        }
    }

    private void EnsureAnnotationEditor()
    {
        if (selectionState?.EffectiveRegion is not { IsEmpty: false } region)
        {
            return;
        }
        if (annotationEditor is null)
        {
            annotationEditor = new ScreenshotAnnotationEditor(new ScreenshotDocument(
                Guid.NewGuid(),
                region.Size,
                [],
                revision: 0));
            return;
        }

        annotationEditor.ResizeCanvas(region.Size);
    }

    private void ResetAnnotationsForNewSelection()
    {
        sourceWindowTitle = null;
        annotationEditor = null;
        previewAnnotation = null;
        annotationTransformPreview = null;
        annotationPoints.Clear();
        annotationResizeHandle = null;
        observedAnnotationDocument = null;
        annotationGeneration = checked(annotationGeneration + 1);
        toolbar?.ViewModel.SelectTool(ScreenshotTool.Select);
        InvalidateInlineTranslation();
    }

    private void UpdateAnnotationPreview(ScreenshotTool tool)
    {
        if (annotationEditor is null)
        {
            previewAnnotation = null;
            return;
        }
        var nextNumber = annotationEditor.Document.Annotations.Count(annotation =>
            annotation.Kind == AnnotationKind.NumberedMarker) + 1;
        _ = ScreenshotAnnotationFactory.TryCreate(
            tool,
            annotationStart,
            annotationPoints,
            text: null,
            nextNumber,
            out previewAnnotation,
            annotationEditor.CurrentStyle,
            annotationEditor.CurrentTextStyle);
    }

    private void CommitAnnotationGesture(PixelPoint point)
    {
        if (annotationEditor is null
            || selectionState?.EffectiveRegion is not { } region)
        {
            return;
        }
        var source = ClampSource(ToSource(point, region), region.Size);
        if (annotationPoints.Count == 0 || annotationPoints[^1] != source)
        {
            annotationPoints.Add(source);
        }
        var tool = toolbar?.ViewModel.ActiveTool ?? ScreenshotTool.Select;
        var added = annotationEditor.TryAddGesture(
            tool,
            annotationStart,
            annotationPoints,
            text: null);
        if (added && ScreenshotOverlayInputPolicy.ShouldClearSelectionAfterCommit(tool))
        {
            annotationEditor.Select([]);
        }
    }

    private void CommitAnnotationMove(PixelPoint point)
    {
        if (annotationEditor is null
            || selectionState?.EffectiveRegion is not { } region)
        {
            return;
        }
        var end = ClampSource(ToSource(point, region), region.Size);
        annotationEditor.MoveSelection(new SourceVector(
            end.X - annotationStart.X,
            end.Y - annotationStart.Y));
    }

    private void UpdateAnnotationMovePreview(PixelPoint point)
    {
        if (annotationEditor is null
            || selectionState?.EffectiveRegion is not { } region)
        {
            annotationTransformPreview = null;
            return;
        }
        var end = ClampSource(ToSource(point, region), region.Size);
        annotationTransformPreview = annotationEditor.PreviewMoveSelection(new SourceVector(
            end.X - annotationStart.X,
            end.Y - annotationStart.Y));
    }

    private void CommitAnnotationResize(PixelPoint point)
    {
        if (annotationEditor is null
            || annotationResizeHandle is null
            || selectionState?.EffectiveRegion is not { } region)
        {
            return;
        }
        annotationEditor.ResizeSelection(
            annotationResizeHandle.Value,
            ClampSource(ToSource(point, region), region.Size));
    }

    private void UpdateAnnotationResizePreview(PixelPoint point)
    {
        if (annotationEditor is null
            || annotationResizeHandle is null
            || selectionState?.EffectiveRegion is not { } region)
        {
            annotationTransformPreview = null;
            return;
        }
        annotationTransformPreview = annotationEditor.PreviewResizeSelection(
            annotationResizeHandle.Value,
            ClampSource(ToSource(point, region), region.Size));
    }

    private void CommitAnnotationMarquee(PixelPoint point, ModifierKeys modifiers)
    {
        if (annotationEditor is null
            || selectionState?.EffectiveRegion is not { } region)
        {
            return;
        }
        var end = ClampSource(ToSource(point, region), region.Size);
        var rect = SourceRect.FromPoints(annotationStart, end);
        if (!rect.IsEmpty)
        {
            annotationEditor.SelectIntersecting(
                rect,
                modifiers.HasFlag(ModifierKeys.Shift));
        }
    }

    private void RefreshVisuals()
    {
        if (selectionState is null)
        {
            return;
        }
        ObserveAnnotationDocumentChanges();
        if (toolbar is not null)
        {
            var hasSelection = (annotationEditor?.Selection.Ids.Count ?? 0) > 0;
            toolbar.ViewModel.UpdateCommandAvailability(
                new ScreenshotToolbarCommandAvailability(
                    CanCopy: hasSelection,
                    CanPaste: annotationEditor?.CanPaste == true,
                    CanDuplicate: hasSelection,
                    CanUndo: annotationEditor?.CanUndo == true,
                    CanRedo: annotationEditor?.CanRedo == true));
            if (annotationEditor is not null)
            {
                toolbar.ViewModel.SynchronizeStyleState(
                    annotationEditor.CurrentStyle,
                    annotationEditor.CurrentTextStyle);
            }
        }
        var annotationSource = GetAnnotationSourceImage();
        foreach (var window in windows)
        {
            window.Surface.Update(
                selectionState,
                annotationEditor,
                previewAnnotation,
                annotationTransformPreview,
                annotationSource,
                isInlineTranslationVisible ? inlineTranslationLines : [],
                inlineTranslationPresentation,
                inlineTranslationStatusText);
        }
        UpdateCursor(lastPointer);
    }

    private void UpdateCursor(PixelPoint? point)
    {
        if (selectionState is null)
        {
            return;
        }
        foreach (var window in windows)
        {
            Cursor cursor;
            if (point is { } current
                && ToDomainRect(window.Frame.Bounds).Contains(current))
            {
                cursor = CursorAt(current);
            }
            else
            {
                cursor = selectionState.EffectiveRegion is null ? Cursors.Cross : Cursors.Arrow;
            }
            window.Surface.Cursor = cursor;
        }
    }

    private Cursor CursorAt(PixelPoint point)
    {
        if (selectionState?.EffectiveRegion is not { } region)
        {
            return Cursors.Cross;
        }
        if (pointerInteraction == PointerInteraction.AnnotationGesture)
        {
            return Cursors.Pen;
        }
        var annotationHandle = annotationEditor is null
            ? null
            : FindAnnotationHandle(annotationEditor.SelectedResizableBounds, ToSource(point, region));
        if (annotationHandle is not null)
        {
            return CursorFor(annotationHandle.Value);
        }
        var selectionHandle = annotationEditor?.Document.Annotations.Count > 0
            ? null
            : FindSelectionHandle(region, point);
        if (selectionHandle is not null)
        {
            return CursorFor(selectionHandle.Value);
        }
        if (region.Contains(point))
        {
            return pointerInteraction is PointerInteraction.DesktopSelection
                or PointerInteraction.AnnotationMove
                ? Cursors.Hand
                : Cursors.SizeAll;
        }
        return Cursors.Cross;
    }

    private void ShowOrPlaceToolbar()
    {
        if (selectionState?.EffectiveRegion is not { IsEmpty: false } region)
        {
            HideToolbar();
            return;
        }
        toolbar ??= CreateToolbar();
        var (physical, toolbarLayout) = CalculateToolbarPlacement(region, selectionState.Layout);
        toolbar.ApplyAdaptiveLayout(toolbarLayout);
        if (!toolbar.IsVisible)
        {
            toolbar.Show();
        }
        WindowsScreenshotDpi.ApplyPhysicalBounds(toolbar, physical);
    }

    private ScreenshotToolbarWindow CreateToolbar()
    {
        var value = new ScreenshotToolbarWindow();
        value.Invoked += OnToolbarInvoked;
        value.OverlayKeyPressed += OnKeyPressed;
        value.KeyboardNavigationActivated += OnToolbarKeyboardNavigationActivated;
        return value;
    }

    private void HideToolbar()
    {
        ExitToolbarKeyboardMode(restoreForeground: true);
        if (toolbar?.IsVisible == true)
        {
            toolbar.DismissStylePopover();
            toolbar.Hide();
        }
    }

    private bool EnterToolbarKeyboardMode(bool backward)
    {
        ShowOrPlaceToolbar();
        if (toolbar is null || !toolbar.IsVisible)
        {
            return false;
        }
        toolbarKeyboardMode = true;
        keyboardSession?.SetInputMode(ScreenshotKeyboardInputMode.Toolbar);
        return backward
            ? toolbar.FocusLastTool()
            : toolbar.FocusFirstTool();
    }

    private void ExitToolbarKeyboardMode(bool restoreForeground)
    {
        if (!toolbarKeyboardMode)
        {
            return;
        }
        toolbarKeyboardMode = false;
        keyboardSession?.SetInputMode(ScreenshotKeyboardInputMode.Overlay);
        if (restoreForeground)
        {
            _ = windowActivation.RestoreForegroundWindow(savedForegroundWindow);
        }
    }

    private void OnToolbarKeyboardNavigationActivated(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        toolbarKeyboardMode = true;
        keyboardSession?.SetInputMode(ScreenshotKeyboardInputMode.Toolbar);
    }

    private void OnTextEditingActivationChanged(bool isActive)
    {
        keyboardSession?.SetInputMode(isActive
            ? ScreenshotKeyboardInputMode.TextEditing
            : toolbarKeyboardMode
                ? ScreenshotKeyboardInputMode.Toolbar
                : ScreenshotKeyboardInputMode.Overlay);
    }

    internal static CapturePixelRect CalculateToolbarFrame(
        PixelRect selection,
        ScreenshotDesktopLayout layout) => CalculateToolbarPlacement(selection, layout).Frame;

    private static (CapturePixelRect Frame, ScreenshotToolbarLayout Layout) CalculateToolbarPlacement(
        PixelRect selection,
        ScreenshotDesktopLayout layout)
    {
        var center = new PixelPoint(
            selection.Left + (selection.Width / 2),
            selection.Top + (selection.Height / 2));
        var display = layout.DisplayAt(center)
            ?? layout.Displays
                .OrderByDescending(value => value.Bounds.Intersection(selection).Width
                    * (long)value.Bounds.Intersection(selection).Height)
                .First();
        var scaleX = display.DpiX / 96;
        var scaleY = display.DpiY / 96;
        var gap = Math.Max(1, checked((int)Math.Round(ScreenshotSelectionPresentation.ToolbarGap * scaleY)));
        var padding = Math.Max(1, checked((int)Math.Round(ScreenshotToolbarCatalog.ContentPadding * scaleX)));
        var availableWidth = Math.Max(1, display.Bounds.Width - (padding * 2));
        var availableHeight = Math.Max(1, display.Bounds.Height - (padding * 2));
        var toolbarLayout = ScreenshotToolbarCatalog.LayoutFor(
            itemCount: 22,
            availableWidth,
            display.DpiX,
            display.DpiY);
        if (toolbarLayout.PhysicalHeight > availableHeight)
        {
            toolbarLayout = toolbarLayout with
            {
                DipHeight = availableHeight * 96D / display.DpiY,
                PhysicalHeight = availableHeight,
            };
        }
        var width = toolbarLayout.PhysicalWidth;
        var height = toolbarLayout.PhysicalHeight;
        var minimumX = display.Bounds.Left + padding;
        var maximumX = display.Bounds.Right - width - padding;
        var proposedX = selection.Left + ((selection.Width - width) / 2);
        var x = maximumX < minimumX
            ? display.Bounds.Left
            : Math.Clamp(proposedX, minimumX, maximumX);
        var minimumY = display.Bounds.Top + padding;
        var maximumY = display.Bounds.Bottom - height - padding;
        var below = selection.Bottom + gap;
        var proposedY = below + height <= display.Bounds.Bottom - padding
            ? below
            : selection.Top - height - gap;
        var y = maximumY < minimumY
            ? display.Bounds.Top
            : Math.Clamp(proposedY, minimumY, maximumY);
        return (new CapturePixelRect(x, y, width, height), toolbarLayout);
    }

    private void CompleteSession(ScreenshotCompletionKind kind)
    {
        if (completion is null
            || desktop is null
            || selectionState?.EffectiveRegion is not { IsEmpty: false } region)
        {
            return;
        }
        foreach (var window in windows)
        {
            window.CommitTextEditing();
        }
        EnsureAnnotationEditor();
        var image = desktop.Crop(new CapturePixelRect(
            region.Left,
            region.Top,
            region.Width,
            region.Height));
        var result = new ScreenshotOverlayResult(
            runId,
            kind,
            region,
            image,
            annotationEditor!.Document,
            isInlineTranslationVisible ? inlineTranslationLines : [],
            sourceWindowTitle);
        var source = completion;
        CleanupWindows();
        ResetSession();
        source.TrySetResult(result);
    }

    private void CancelSession()
    {
        if (completion is null)
        {
            return;
        }
        var source = completion;
        CleanupWindows();
        ResetSession();
        source.TrySetResult(null);
    }

    private void CleanupWindows()
    {
        keyboardSession?.Dispose();
        keyboardSession = null;
        toolbarKeyboardMode = false;
        cancellationRegistration.Dispose();
        cancellationRegistration = default;
        inlineTranslationCancellation?.Cancel();
        inlineTranslationCancellation?.Dispose();
        inlineTranslationCancellation = null;
        if (toolbar is not null)
        {
            toolbar.Invoked -= OnToolbarInvoked;
            toolbar.OverlayKeyPressed -= OnKeyPressed;
            toolbar.KeyboardNavigationActivated -= OnToolbarKeyboardNavigationActivated;
            toolbar.Close();
            toolbar = null;
        }
        foreach (var window in windows)
        {
            window.PointerPressed -= OnPointerPressed;
            window.PointerMoved -= OnPointerMoved;
            window.PointerReleased -= OnPointerReleased;
            window.KeyPressed -= OnKeyPressed;
            window.TextCommitted -= OnTextCommitted;
            window.Close();
        }
        windows.Clear();
        _ = windowActivation.RestoreForegroundWindow(savedForegroundWindow);
    }

    private void ResetSession()
    {
        completion = null;
        desktop = null;
        selectionState = null;
        annotationEditor = null;
        windowTargets = [];
        pointerInteraction = PointerInteraction.None;
        pointerWindow = null;
        previewAnnotation = null;
        annotationTransformPreview = null;
        annotationPoints.Clear();
        annotationResizeHandle = null;
        observedAnnotationDocument = null;
        annotationGeneration = 0;
        annotationSourceImage = null;
        annotationSourceRegion = null;
        lastPointer = null;
        runId = Guid.Empty;
        sessionCancellation = default;
        inlineTranslationLines = [];
        isInlineTranslationVisible = false;
        inlineTranslationPresentation = ScreenshotInlineTranslationPresentationKind.None;
        inlineTranslationStatusText = null;
        sourceWindowTitle = null;
        savedForegroundWindow = nint.Zero;
        toolbarKeyboardMode = false;
    }

    private FrozenScreenshot? GetAnnotationSourceImage()
    {
        if (desktop is null
            || selectionState?.EffectiveRegion is not { IsEmpty: false } region
            || annotationEditor is null)
        {
            return null;
        }
        var annotations = annotationTransformPreview ?? annotationEditor.Document.Annotations;
        if (previewAnnotation is not MosaicAnnotation
            && !annotations.Any(static annotation => annotation.Kind == AnnotationKind.Mosaic))
        {
            return null;
        }
        if (annotationSourceImage is not null && annotationSourceRegion == region)
        {
            return annotationSourceImage;
        }
        annotationSourceImage = desktop.Crop(new CapturePixelRect(
            region.Left,
            region.Top,
            region.Width,
            region.Height));
        annotationSourceRegion = region;
        return annotationSourceImage;
    }

    private void ObserveAnnotationDocumentChanges()
    {
        var current = annotationEditor?.Document;
        if (current is null)
        {
            observedAnnotationDocument = null;
            return;
        }
        if (!RequiresInlineTranslationInvalidation(observedAnnotationDocument, current))
        {
            return;
        }
        observedAnnotationDocument = current;
        annotationGeneration = checked(annotationGeneration + 1);
        InvalidateInlineTranslation();
    }

    internal static bool RequiresInlineTranslationInvalidation(
        ScreenshotDocument? observed,
        ScreenshotDocument? current) =>
        current is not null && !ReferenceEquals(observed, current);

    internal static TextAnnotation? FindEditableText(
        IReadOnlyList<ScreenshotAnnotation> annotations,
        SourcePoint point)
    {
        ArgumentNullException.ThrowIfNull(annotations);
        var textAnnotations = annotations
            .OfType<TextAnnotation>()
            .Cast<ScreenshotAnnotation>()
            .ToArray();
        var hit = AnnotationHitTester.HitTest(textAnnotations, point);
        return hit is null
            ? null
            : textAnnotations
                .OfType<TextAnnotation>()
                .First(annotation => annotation.Id == hit.Value);
    }

    internal static FrozenScreenshot RenderInlineTranslationInput(
        FrozenScreenshot source,
        ScreenshotDocument document)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(document);
        if (document.Annotations.Count == 0)
        {
            return source;
        }
        var bitmap = new ScreenshotSourceRenderer().RenderBitmap(source, document);
        var stride = checked(source.Width * 4);
        var pixels = new byte[checked(stride * source.Height)];
        bitmap.CopyPixels(pixels, stride, 0);
        return new FrozenScreenshot(source.Width, source.Height, stride, pixels);
    }

    private void RememberWindowCandidate(WindowTargetCandidate? candidate)
    {
        if (candidate is null)
        {
            return;
        }

        sourceWindowTitle = windowTargets
            .FirstOrDefault(target => target.WindowHandle == candidate.WindowHandle)
            ?.Title;
    }

    private static ScreenshotDesktopLayout CreateLayout(FrozenDesktop desktop)
    {
        var primaryIndex = desktop.Frames
            .Select((frame, index) => (frame, index))
            .FirstOrDefault(value => value.frame.Bounds.Contains(new CapturePixelPoint(0, 0)))
            .index;
        var displays = desktop.Frames.Select((frame, index) =>
        {
            var dpi = WindowsScreenshotDpi.ReadMonitorDpi(frame.Bounds);
            return new ScreenshotDisplay(
                $"{frame.AdapterId}:{frame.DeviceName}",
                frame.DeviceName,
                ToDomainRect(frame.Bounds),
                dpi.DpiX,
                dpi.DpiY,
                frame.RotationDegrees switch
                {
                    0 => DisplayRotation.Degrees0,
                    90 => DisplayRotation.Degrees90,
                    180 => DisplayRotation.Degrees180,
                    270 => DisplayRotation.Degrees270,
                    _ => throw new ArgumentOutOfRangeException(nameof(frame)),
                },
                isPrimary: index == primaryIndex);
        }).ToArray();
        return new ScreenshotDesktopLayout(displays);
    }

    private static ScreenshotResizeHandle? FindSelectionHandle(PixelRect region, PixelPoint point)
    {
        const int hitSize = 14;
        var half = hitSize / 2;
        var middleX = region.Left + (region.Width / 2);
        var middleY = region.Top + (region.Height / 2);
        var values = new[]
        {
            (ScreenshotResizeHandle.TopLeft, region.Left, region.Top),
            (ScreenshotResizeHandle.Top, middleX, region.Top),
            (ScreenshotResizeHandle.TopRight, region.Right, region.Top),
            (ScreenshotResizeHandle.Left, region.Left, middleY),
            (ScreenshotResizeHandle.Right, region.Right, middleY),
            (ScreenshotResizeHandle.BottomLeft, region.Left, region.Bottom),
            (ScreenshotResizeHandle.Bottom, middleX, region.Bottom),
            (ScreenshotResizeHandle.BottomRight, region.Right, region.Bottom),
        };
        foreach (var (handle, x, y) in values)
        {
            if (new PixelRect(x - half, y - half, hitSize, hitSize).Contains(point))
            {
                return handle;
            }
        }
        return null;
    }

    private static AnnotationResizeHandle? FindAnnotationHandle(
        SourceRect? bounds,
        SourcePoint point)
    {
        if (bounds is not { IsEmpty: false } value)
        {
            return null;
        }
        var presentation = AnnotationSelectionPresentation.Calculate(value);
        foreach (var handle in presentation.Handles)
        {
            if (handle.Bounds.Inflate(3, 3).Contains(point))
            {
                return handle.Handle;
            }
        }
        return null;
    }

    private static Cursor CursorFor(ScreenshotResizeHandle handle) => handle switch
    {
        ScreenshotResizeHandle.Top or ScreenshotResizeHandle.Bottom => Cursors.SizeNS,
        ScreenshotResizeHandle.Left or ScreenshotResizeHandle.Right => Cursors.SizeWE,
        ScreenshotResizeHandle.TopLeft or ScreenshotResizeHandle.BottomRight => Cursors.SizeNWSE,
        ScreenshotResizeHandle.TopRight or ScreenshotResizeHandle.BottomLeft => Cursors.SizeNESW,
        _ => Cursors.Arrow,
    };

    private static Cursor CursorFor(AnnotationResizeHandle handle) => handle switch
    {
        AnnotationResizeHandle.Top or AnnotationResizeHandle.Bottom => Cursors.SizeNS,
        AnnotationResizeHandle.Left or AnnotationResizeHandle.Right => Cursors.SizeWE,
        AnnotationResizeHandle.TopLeft or AnnotationResizeHandle.BottomRight => Cursors.SizeNWSE,
        AnnotationResizeHandle.TopRight or AnnotationResizeHandle.BottomLeft => Cursors.SizeNESW,
        _ => Cursors.Arrow,
    };

    private static SourcePoint ToSource(PixelPoint point, PixelRect selection) => new(
        point.X - selection.Left,
        point.Y - selection.Top);

    private static SourcePoint ClampSource(SourcePoint point, PixelSize size) => new(
        Math.Clamp(point.X, 0, size.Width),
        Math.Clamp(point.Y, 0, size.Height));

    private static PixelRect ToDomainRect(CapturePixelRect rect) =>
        new(rect.Left, rect.Top, rect.Width, rect.Height);
}
