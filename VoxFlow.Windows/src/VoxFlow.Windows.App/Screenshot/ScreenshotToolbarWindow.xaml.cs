using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain.Screenshots;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using VisualTreeHelper = System.Windows.Media.VisualTreeHelper;

namespace VoxFlow.Windows.App.Screenshot;

public sealed record ScreenshotToolbarCommandAvailability(
    bool CanCopy,
    bool CanPaste,
    bool CanDuplicate,
    bool CanUndo,
    bool CanRedo)
{
    public static ScreenshotToolbarCommandAvailability AllAvailable { get; } =
        new(true, true, true, true, true);
}

internal sealed class ScreenshotToolbarStyleOptionViewModel
{
    public required ScreenshotToolbarAction Action { get; init; }

    public required string Label { get; init; }

    public required string ShortLabel { get; init; }

    public required object Value { get; init; }

    public required bool IsSelected { get; init; }

    public required int Index { get; init; }

    public bool IsColor => Action == ScreenshotToolbarAction.Color;

    public bool IsLineWidth => Action == ScreenshotToolbarAction.LineWidth;

    public bool IsFontSize => Action == ScreenshotToolbarAction.FontSize;

    public bool UsesSelectionBackground => IsSelected && !IsColor;

    public bool ShowsSelectedColorRing => IsSelected && IsColor;

    public System.Windows.Media.Brush? ColorBrush => Value is AnnotationColor color
        ? ScreenshotDrawingPrimitives.Brush(color)
        : null;

    public double DotSize => Value is double width && IsLineWidth
        ? 8 + ((width - 6) * 2)
        : 0;

    public string AutomationId =>
        $"screenshot.toolbar.{Action.ToString().ToLowerInvariant()}.{Index}";

    public string AutomationItemStatus => IsSelected
        ? L10n.Localize("ScreenshotToolbarSelectedStatus")
        : string.Empty;
}

public sealed class ScreenshotToolbarViewModel : INotifyPropertyChanged
{
    public ScreenshotToolbarViewModel()
    {
        Items = new ObservableCollection<ScreenshotToolbarItemViewModel>(
            ScreenshotToolbarCatalog.Create());
        StyleOptions = [];
        RefreshStyleIndicators();
        UpdateCommandAvailability(ScreenshotToolbarCommandAvailability.AllAvailable);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ScreenshotToolbarItemViewModel> Items { get; }

    internal ObservableCollection<ScreenshotToolbarStyleOptionViewModel> StyleOptions { get; }

    public ScreenshotTool ActiveTool { get; private set; } = ScreenshotTool.Select;

    public AnnotationColor CurrentColor { get; private set; } = AnnotationStyle.Default.Color;

    public double CurrentLineWidth { get; private set; } = AnnotationStyle.Default.LineWidth;

    public double CurrentFontSize { get; private set; } = TextAnnotationStyle.Default.FontSize;

    public void SelectTool(ScreenshotTool tool)
    {
        if (!Enum.IsDefined(tool))
        {
            throw new ArgumentOutOfRangeException(nameof(tool));
        }
        ActiveTool = tool;
        foreach (var item in Items)
        {
            item.IsActive = ScreenshotToolbarCatalog.ToTool(item.Action) == tool;
        }
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Items)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ActiveTool)));
    }

    public void UpdateCommandAvailability(ScreenshotToolbarCommandAvailability availability)
    {
        ArgumentNullException.ThrowIfNull(availability);
        SetEnabled(ScreenshotToolbarAction.Copy, availability.CanCopy);
        SetEnabled(ScreenshotToolbarAction.Paste, availability.CanPaste);
        SetEnabled(ScreenshotToolbarAction.Duplicate, availability.CanDuplicate);
        SetEnabled(ScreenshotToolbarAction.Undo, availability.CanUndo);
        SetEnabled(ScreenshotToolbarAction.Redo, availability.CanRedo);
    }

    public void SynchronizeStyleState(
        AnnotationStyle style,
        TextAnnotationStyle textStyle)
    {
        ArgumentNullException.ThrowIfNull(style);
        ArgumentNullException.ThrowIfNull(textStyle);
        CurrentColor = textStyle.Color;
        CurrentLineWidth = style.LineWidth;
        CurrentFontSize = textStyle.FontSize;
        RefreshStyleIndicators();
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentColor)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentLineWidth)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentFontSize)));
    }

    internal void PrepareStyleOptions(ScreenshotToolbarAction action)
    {
        StyleOptions.Clear();
        var options = StyleOptionValues(action);
        for (var index = 0; index < options.Count; index++)
        {
            var option = options[index];
            StyleOptions.Add(new ScreenshotToolbarStyleOptionViewModel
            {
                Action = action,
                Label = option.Label,
                ShortLabel = option.ShortLabel,
                Value = option.Value,
                IsSelected = IsCurrentValue(action, option.Value),
                Index = index,
            });
        }
    }

    internal void ApplyStyleValue(ScreenshotToolbarAction action, object value)
    {
        switch (action)
        {
            case ScreenshotToolbarAction.Color
                when value is AnnotationColor color
                     && AnnotationPalette.Colors.Contains(color):
                CurrentColor = color;
                break;
            case ScreenshotToolbarAction.LineWidth
                when value is double lineWidth
                     && AnnotationPalette.LineWidths.Contains(lineWidth):
                CurrentLineWidth = lineWidth;
                break;
            case ScreenshotToolbarAction.FontSize
                when value is double fontSize
                     && AnnotationPalette.FontSizes.Contains(fontSize):
                CurrentFontSize = fontSize;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(value));
        }

        RefreshStyleIndicators();
        PrepareStyleOptions(action);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentColor)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentLineWidth)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentFontSize)));
    }

    internal static IReadOnlyList<(string Label, string ShortLabel, object Value)> StyleOptionValues(
        ScreenshotToolbarAction action) => action switch
    {
        ScreenshotToolbarAction.Color =>
        [
            (L10n.Localize("ScreenshotColorGreen"), string.Empty, AnnotationColor.VoxGreen),
            (L10n.Localize("ScreenshotColorRed"), string.Empty, AnnotationColor.Red),
            (L10n.Localize("ScreenshotColorWhite"), string.Empty, AnnotationColor.White),
            (L10n.Localize("ScreenshotColorBlack"), string.Empty, AnnotationColor.Black),
        ],
        ScreenshotToolbarAction.LineWidth =>
        [
            (L10n.Localize("ScreenshotLineWidthThin"), string.Empty, 6d),
            (L10n.Localize("ScreenshotLineWidthMedium"), string.Empty, 8d),
            (L10n.Localize("ScreenshotLineWidthThick"), string.Empty, 10d),
        ],
        ScreenshotToolbarAction.FontSize =>
        [
            (L10n.Localize("ScreenshotFontSizeSmall"), L10n.Localize("ScreenshotFontSizeSmallLabel"), 14d),
            (L10n.Localize("ScreenshotFontSizeMedium"), L10n.Localize("ScreenshotFontSizeMediumLabel"), 24d),
            (L10n.Localize("ScreenshotFontSizeLarge"), L10n.Localize("ScreenshotFontSizeLargeLabel"), 32d),
        ],
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    private void RefreshStyleIndicators()
    {
        var colorLabel = LabelFor(ScreenshotToolbarAction.Color, CurrentColor);
        var lineWidthLabel = LabelFor(ScreenshotToolbarAction.LineWidth, CurrentLineWidth);
        var fontSizeOption = StyleOptionValues(ScreenshotToolbarAction.FontSize)
            .FirstOrDefault(option => Equals(option.Value, CurrentFontSize));
        var fontSizeLabel = fontSizeOption == default
            ? CurrentFontSize.ToString("0.#", System.Globalization.CultureInfo.CurrentCulture)
            : fontSizeOption.ShortLabel;
        var accessibleFontSizeLabel = fontSizeOption == default
            ? fontSizeLabel
            : fontSizeOption.Label;

        foreach (var item in Items)
        {
            var accessibleValue = item.Action switch
            {
                ScreenshotToolbarAction.Color => colorLabel,
                ScreenshotToolbarAction.LineWidth => lineWidthLabel,
                ScreenshotToolbarAction.FontSize => accessibleFontSizeLabel,
                _ => null,
            };
            item.UpdateStyleState(
                CurrentColor,
                CurrentLineWidth,
                fontSizeLabel,
                accessibleValue);
        }
    }

    private bool IsCurrentValue(ScreenshotToolbarAction action, object value) => action switch
    {
        ScreenshotToolbarAction.Color when value is AnnotationColor color => color == CurrentColor,
        ScreenshotToolbarAction.LineWidth when value is double lineWidth =>
            Math.Abs(lineWidth - CurrentLineWidth) < 0.01,
        ScreenshotToolbarAction.FontSize when value is double fontSize =>
            Math.Abs(fontSize - CurrentFontSize) < 0.01,
        _ => false,
    };

    private static string LabelFor(ScreenshotToolbarAction action, object value) =>
        StyleOptionValues(action).Single(option => Equals(option.Value, value)).Label;

    private void SetEnabled(ScreenshotToolbarAction action, bool isEnabled) =>
        Items.Single(item => item.Action == action).IsEnabled = isEnabled;
}

public sealed record ScreenshotToolbarInvokedEventArgs(
    ScreenshotToolbarAction Action,
    object? Value = null);

public partial class ScreenshotToolbarWindow : Window
{
    private ScreenshotToolbarAction? openStyleAction;
    private Button? stylePopoverAnchor;
    private bool stylePopoverClosing;
    private PendingStylePopoverOpen? pendingStyleOpen;
    private DispatcherOperation? stylePopoverCloseCompletion;
    private DispatcherOperation? stylePopoverFocusOperation;

    public ScreenshotToolbarWindow()
    {
        InitializeComponent();
        ViewModel = new ScreenshotToolbarViewModel();
        DataContext = ViewModel;
        StyleOptionItems.ItemsSource = ViewModel.StyleOptions;
        Width = ScreenshotToolbarCatalog.WidthFor(ViewModel.Items.Count);
        PreviewKeyDown += OnPreviewKeyDown;
    }

    public event EventHandler<ScreenshotToolbarInvokedEventArgs>? Invoked;

    internal event EventHandler<ScreenshotKeyEventArgs>? OverlayKeyPressed;

    internal event EventHandler? KeyboardNavigationActivated;

    public ScreenshotToolbarViewModel ViewModel { get; }

    internal IReadOnlyList<Button> ToolButtons =>
        FindVisualChildren<Button>(ToolbarItems).ToArray();

    internal IReadOnlyList<Button> StyleOptionButtons =>
        FindVisualChildren<Button>(StyleOptionItems).ToArray();

    internal bool IsStylePopoverOpen => StylePopover.IsOpen;

    internal bool FocusFirstTool()
    {
        if (!IsVisible)
        {
            return false;
        }

        KeyboardNavigationActivated?.Invoke(this, EventArgs.Empty);
        _ = Activate();
        ToolbarItems.UpdateLayout();
        var button = ToolButtons.FirstOrDefault(static button => button.IsEnabled);
        button?.BringIntoView();
        return button?.Focus() == true;
    }

    internal bool FocusLastTool()
    {
        if (!IsVisible)
        {
            return false;
        }
        KeyboardNavigationActivated?.Invoke(this, EventArgs.Empty);
        _ = Activate();
        ToolbarItems.UpdateLayout();
        var button = ToolButtons.LastOrDefault(static button => button.IsEnabled);
        button?.BringIntoView();
        return button?.Focus() == true;
    }

    internal void ApplyAdaptiveLayout(ScreenshotToolbarLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        Width = layout.DipWidth;
        Height = layout.DipHeight;
        ToolbarItems.Width = Math.Max(
            0,
            layout.DipWidth
            - (ScreenshotToolbarCatalog.ContentPadding * 2)
            + ScreenshotToolbarCatalog.ItemSpacing);
        ToolbarItems.UpdateLayout();
    }

    internal bool MoveToolbarFocus(int offset)
    {
        var buttons = ToolButtons.Where(static button => button.IsEnabled).ToArray();
        return MoveFocus(buttons, offset);
    }

    internal bool MoveKeyboardFocus(int offset)
    {
        KeyboardNavigationActivated?.Invoke(this, EventArgs.Empty);
        return IsStylePopoverOpen
            ? MoveFocus(StyleOptionButtons, offset)
            : MoveToolbarFocus(offset);
    }

    internal bool InvokeKeyboardFocusedButton()
    {
        var focused = ToolButtons
            .Concat(StyleOptionButtons)
            .FirstOrDefault(static button => button.IsKeyboardFocused && button.IsEnabled);
        if (focused is null)
        {
            return false;
        }
        focused.RaiseEvent(new RoutedEventArgs(Button.ClickEvent, focused));
        return true;
    }

    internal void DismissStylePopover(bool restoreFocus = false) =>
        CloseStylePopover(restoreFocus);

    internal void OpenStylePopover(ScreenshotToolbarAction action, Button anchor)
    {
        if (action is not ScreenshotToolbarAction.Color
            and not ScreenshotToolbarAction.LineWidth
            and not ScreenshotToolbarAction.FontSize)
        {
            throw new ArgumentOutOfRangeException(nameof(action));
        }

        if (StylePopover.IsOpen && openStyleAction == action)
        {
            CloseStylePopover(restoreFocus: true);
            return;
        }

        if (stylePopoverClosing)
        {
            pendingStyleOpen = new PendingStylePopoverOpen(action, anchor);
            return;
        }

        pendingStyleOpen = null;
        OpenStylePopoverCore(action, anchor);
    }

    private void OpenStylePopoverCore(ScreenshotToolbarAction action, Button anchor)
    {
        var wasOpen = StylePopover.IsOpen;
        ViewModel.PrepareStyleOptions(action);
        openStyleAction = action;
        stylePopoverAnchor = anchor;
        StylePopover.PlacementTarget = anchor;
        StylePopover.Placement = PlacementMode.Top;
        StylePopover.IsOpen = true;
        if (wasOpen)
        {
            ScheduleFirstStyleOptionFocus();
        }
    }

    private void OnStylePopoverOpened(object? sender, EventArgs eventArgs)
    {
        // The popup content has its own presentation source. Waiting for Opened
        // ensures the option buttons are connected to that source before trying
        // to transfer keyboard focus from the toolbar.
        ScheduleFirstStyleOptionFocus();
    }

    private void ScheduleFirstStyleOptionFocus()
    {
        stylePopoverFocusOperation ??= Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            () =>
            {
                stylePopoverFocusOperation = null;
                FocusFirstStyleOption();
            });
    }

    private void FocusFirstStyleOption()
    {
        if (!StylePopover.IsOpen)
        {
            return;
        }

        // Creating the popup HWND can momentarily deactivate this no-activate
        // toolbar, leaving WPF with no keyboard-focused element. Re-activate the
        // already-interactive toolbar before moving focus into the popup source.
        KeyboardNavigationActivated?.Invoke(this, EventArgs.Empty);
        _ = Activate();
        StyleOptionItems.UpdateLayout();
        var firstOption = StyleOptionButtons.FirstOrDefault();
        firstOption?.BringIntoView();
        _ = firstOption is not null && Keyboard.Focus(firstOption) == firstOption;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.Space
            && eventArgs.OriginalSource is Button { IsEnabled: true } button)
        {
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent, button));
            eventArgs.Handled = true;
            return;
        }

        if (StylePopover.IsOpen)
        {
            if (eventArgs.Key == Key.Escape)
            {
                CloseStylePopover(restoreFocus: true);
                eventArgs.Handled = true;
                return;
            }
            if (eventArgs.Key is Key.Left or Key.Up)
            {
                eventArgs.Handled = MoveFocus(StyleOptionButtons, -1);
                return;
            }
            if (eventArgs.Key is Key.Right or Key.Down)
            {
                eventArgs.Handled = MoveFocus(StyleOptionButtons, 1);
                return;
            }
        }
        else if ((eventArgs.Key is Key.Left or Key.Up)
                 && ToolbarItems.IsKeyboardFocusWithin)
        {
            eventArgs.Handled = MoveToolbarFocus(-1);
            return;
        }
        else if ((eventArgs.Key is Key.Right or Key.Down)
                 && ToolbarItems.IsKeyboardFocusWithin)
        {
            eventArgs.Handled = MoveToolbarFocus(1);
            return;
        }

        if (eventArgs.Key is not Key.Escape and not Key.F6)
        {
            return;
        }

        if (StylePopover.IsOpen)
        {
            CloseStylePopover(restoreFocus: false);
        }
        var forwarded = new ScreenshotKeyEventArgs(eventArgs.Key, Keyboard.Modifiers);
        OverlayKeyPressed?.Invoke(this, forwarded);
        eventArgs.Handled = forwarded.Handled;
    }

    private void OnToolbarClick(object sender, RoutedEventArgs eventArgs)
    {
        if (sender is not Button
            {
                DataContext: ScreenshotToolbarItemViewModel item,
            } button)
        {
            return;
        }
        KeyboardNavigationActivated?.Invoke(this, EventArgs.Empty);

        if (ScreenshotToolbarCatalog.ToTool(item.Action) is { } tool)
        {
            ViewModel.SelectTool(tool);
        }

        if (item.Action is ScreenshotToolbarAction.Color
            or ScreenshotToolbarAction.LineWidth
            or ScreenshotToolbarAction.FontSize)
        {
            OpenStylePopover(item.Action, button);
            return;
        }

        CloseStylePopover(restoreFocus: false);
        Invoked?.Invoke(this, new ScreenshotToolbarInvokedEventArgs(item.Action));
    }

    private void OnStyleOptionClick(object sender, RoutedEventArgs eventArgs)
    {
        if (sender is not Button
            {
                DataContext: ScreenshotToolbarStyleOptionViewModel option,
            })
        {
            return;
        }
        KeyboardNavigationActivated?.Invoke(this, EventArgs.Empty);

        ViewModel.ApplyStyleValue(option.Action, option.Value);
        Invoked?.Invoke(
            this,
            new ScreenshotToolbarInvokedEventArgs(option.Action, option.Value));
        CloseStylePopover(restoreFocus: true);
    }

    private void OnStylePopoverClosed(object? sender, EventArgs eventArgs)
    {
        openStyleAction = null;
        stylePopoverAnchor = null;
        if (!stylePopoverClosing)
        {
            return;
        }

        // Popup.Closed can be raised synchronously while IsOpen is being set to
        // false. Keep the close barrier through the next dispatcher turn so a
        // keyboard/click intent arriving immediately after Escape cannot reopen
        // the same native popup window while WPF is still tearing it down.
        stylePopoverCloseCompletion ??= Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            CompleteStylePopoverClose);
    }

    private void CloseStylePopover(bool restoreFocus)
    {
        var anchor = stylePopoverAnchor;
        pendingStyleOpen = null;
        if (StylePopover.IsOpen)
        {
            stylePopoverClosing = true;
            StylePopover.IsOpen = false;
        }
        else if (!stylePopoverClosing)
        {
            openStyleAction = null;
            stylePopoverAnchor = null;
        }
        if (restoreFocus)
        {
            _ = anchor?.Focus();
        }
    }

    private void DrainPendingStyleOpen()
    {
        if (stylePopoverClosing || pendingStyleOpen is not { } pending)
        {
            return;
        }

        pendingStyleOpen = null;
        if (IsVisible)
        {
            OpenStylePopoverCore(pending.Action, pending.Anchor);
        }
    }

    private void CompleteStylePopoverClose()
    {
        stylePopoverCloseCompletion = null;
        stylePopoverClosing = false;
        DrainPendingStyleOpen();
    }

    private sealed record PendingStylePopoverOpen(
        ScreenshotToolbarAction Action,
        Button Anchor);

    private static bool MoveFocus(IReadOnlyList<Button> buttons, int offset)
    {
        if (buttons.Count == 0)
        {
            return false;
        }
        var current = buttons
            .Select((button, index) => (button, index))
            .FirstOrDefault(pair => pair.button.IsKeyboardFocused);
        var currentIndex = current.button is null ? 0 : current.index;
        var nextIndex = (currentIndex + offset + buttons.Count) % buttons.Count;
        buttons[nextIndex].BringIntoView();
        return buttons[nextIndex].Focus();
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject parent)
        where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T match)
            {
                yield return match;
            }

            foreach (var descendant in FindVisualChildren<T>(child))
            {
                yield return descendant;
            }
        }
    }
}
