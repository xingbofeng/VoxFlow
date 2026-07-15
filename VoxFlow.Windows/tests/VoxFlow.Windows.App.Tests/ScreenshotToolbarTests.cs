using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotToolbarTests
{
    [Fact]
    public void Catalog_matches_the_complete_macOS_order_minus_scrolling_and_recording()
    {
        var items = ScreenshotToolbarCatalog.Create();

        Assert.Equal(
            [
                ScreenshotToolbarAction.Select,
                ScreenshotToolbarAction.Pen,
                ScreenshotToolbarAction.Ellipse,
                ScreenshotToolbarAction.Rectangle,
                ScreenshotToolbarAction.Arrow,
                ScreenshotToolbarAction.DotMarker,
                ScreenshotToolbarAction.NumberedMarker,
                ScreenshotToolbarAction.Text,
                ScreenshotToolbarAction.Mosaic,
                ScreenshotToolbarAction.TextRecognition,
                ScreenshotToolbarAction.Translate,
                ScreenshotToolbarAction.Color,
                ScreenshotToolbarAction.LineWidth,
                ScreenshotToolbarAction.FontSize,
                ScreenshotToolbarAction.Copy,
                ScreenshotToolbarAction.Paste,
                ScreenshotToolbarAction.Duplicate,
                ScreenshotToolbarAction.Undo,
                ScreenshotToolbarAction.Redo,
                ScreenshotToolbarAction.Download,
                ScreenshotToolbarAction.Cancel,
                ScreenshotToolbarAction.Complete,
            ],
            items.Select(item => item.Action));
        Assert.DoesNotContain(items, item =>
            item.Label.Contains("scroll", StringComparison.OrdinalIgnoreCase)
            || item.Label.Contains("record", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Toolbar_measurements_are_the_macOS_values_for_twenty_two_items()
    {
        Assert.Equal(28D, ScreenshotToolbarCatalog.ItemSize);
        Assert.Equal(4D, ScreenshotToolbarCatalog.ItemSpacing);
        Assert.Equal(8D, ScreenshotToolbarCatalog.ContentPadding);
        Assert.Equal(44D, ScreenshotToolbarCatalog.Height);
        Assert.Equal(716D, ScreenshotToolbarCatalog.WidthFor(22));
        Assert.Equal(28D, ScreenshotToolbarCatalog.PopoverOptionSize);
        Assert.Equal(8D, ScreenshotToolbarCatalog.PopoverOptionSpacing);
        Assert.Equal(8D, ScreenshotToolbarCatalog.PopoverPadding);
        Assert.Equal(9D, ScreenshotToolbarCatalog.PopoverCornerRadius);

        var portrait200Percent = ScreenshotToolbarCatalog.LayoutFor(
            itemCount: 22,
            availablePhysicalWidth: 1048,
            dpiX: 192,
            dpiY: 192);
        Assert.Equal(16, portrait200Percent.Columns);
        Assert.Equal(2, portrait200Percent.Rows);
        Assert.Equal(524D, portrait200Percent.DipWidth);
        Assert.Equal(76D, portrait200Percent.DipHeight);
        Assert.Equal(1048, portrait200Percent.PhysicalWidth);
        Assert.Equal(152, portrait200Percent.PhysicalHeight);
    }

    [Fact]
    public void Every_tool_has_localized_accessibility_metadata()
    {
        foreach (var item in ScreenshotToolbarCatalog.Create())
        {
            Assert.False(string.IsNullOrWhiteSpace(item.Label));
            Assert.DoesNotContain("ScreenshotTool", item.Label, StringComparison.Ordinal);
            Assert.StartsWith("screenshot.toolbar.", item.AutomationId, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void View_model_exposes_current_style_and_command_availability()
    {
        var viewModel = new ScreenshotToolbarViewModel();

        Assert.Equal(AnnotationColor.VoxGreen, viewModel.CurrentColor);
        Assert.Equal(6, viewModel.CurrentLineWidth);
        Assert.Equal(14, viewModel.CurrentFontSize);
        var colorItem = viewModel.Items.Single(item => item.Action == ScreenshotToolbarAction.Color);
        Assert.NotEqual(colorItem.Label, colorItem.HelpText);

        viewModel.ApplyStyleValue(ScreenshotToolbarAction.Color, AnnotationColor.Red);
        viewModel.ApplyStyleValue(ScreenshotToolbarAction.LineWidth, 10d);
        viewModel.ApplyStyleValue(ScreenshotToolbarAction.FontSize, 32d);
        viewModel.PrepareStyleOptions(ScreenshotToolbarAction.FontSize);

        Assert.Equal(AnnotationColor.Red, viewModel.CurrentColor);
        Assert.Equal(10, viewModel.CurrentLineWidth);
        Assert.Equal(32, viewModel.CurrentFontSize);
        Assert.Single(viewModel.StyleOptions, option => option.IsSelected && Equals(option.Value, 32d));

        viewModel.UpdateCommandAvailability(new ScreenshotToolbarCommandAvailability(
            CanCopy: false,
            CanPaste: false,
            CanDuplicate: false,
            CanUndo: true,
            CanRedo: false));

        Assert.False(Item(ScreenshotToolbarAction.Copy).IsEnabled);
        Assert.False(Item(ScreenshotToolbarAction.Paste).IsEnabled);
        Assert.False(Item(ScreenshotToolbarAction.Duplicate).IsEnabled);
        Assert.True(Item(ScreenshotToolbarAction.Undo).IsEnabled);
        Assert.False(Item(ScreenshotToolbarAction.Redo).IsEnabled);

        viewModel.SynchronizeStyleState(
            AnnotationStyle.Default.WithColor(AnnotationColor.White).WithLineWidth(8),
            TextAnnotationStyle.Default.WithColor(AnnotationColor.White).WithFontSize(24));
        Assert.Equal(AnnotationColor.White, viewModel.CurrentColor);
        Assert.Equal(8, viewModel.CurrentLineWidth);
        Assert.Equal(24, viewModel.CurrentFontSize);

        ScreenshotToolbarItemViewModel Item(ScreenshotToolbarAction action) =>
            viewModel.Items.Single(item => item.Action == action);
    }

    [Fact]
    public async Task Wpf_toolbar_wraps_on_a_200_percent_portrait_display_and_every_command_remains_focusable()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new ScreenshotToolbarWindow();
            var layout = ScreenshotToolbarCatalog.LayoutFor(22, 1048, 192, 192);
            window.ApplyAdaptiveLayout(layout);
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);

            Assert.Equal(524, window.ActualWidth);
            Assert.Equal(76, window.ActualHeight);
            var buttons = window.ToolButtons;
            Assert.Equal(22, buttons.Count);
            var rowOffsets = buttons
                .Select(button => Math.Round(button.TranslatePoint(new Point(), window).Y))
                .Distinct()
                .Order()
                .ToArray();
            Assert.Equal(2, rowOffsets.Length);
            Assert.True(window.FocusFirstTool());
            for (var index = 1; index < buttons.Count; index++)
            {
                Assert.True(window.MoveToolbarFocus(1));
                Assert.True(buttons[index].IsKeyboardFocused);
            }

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Wpf_toolbar_cycles_focus_activates_with_space_and_opens_horizontal_popover()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new ScreenshotToolbarWindow();
            ScreenshotToolbarInvokedEventArgs? invoked = null;
            window.Invoked += (_, eventArgs) => invoked = eventArgs;
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);

            var buttons = window.ToolButtons;
            Assert.Equal(22, buttons.Count);
            Assert.All(buttons, button =>
            {
                Assert.Equal(28, button.ActualWidth);
                Assert.Equal(28, button.ActualHeight);
                Assert.True(button.IsTabStop);
                Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(button)));
                Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetHelpText(button)));
                Assert.StartsWith(
                    "screenshot.toolbar.",
                    AutomationProperties.GetAutomationId(button),
                    StringComparison.Ordinal);
            });

            Assert.True(window.FocusFirstTool());
            Assert.True(buttons[0].IsKeyboardFocused);
            Assert.False(string.IsNullOrWhiteSpace(
                AutomationProperties.GetItemStatus(buttons[0])));
            PressPreviewKey(buttons[0], window, Key.Right);
            Assert.True(buttons[1].IsKeyboardFocused);
            Assert.True(window.MoveToolbarFocus(-1));
            Assert.True(buttons[0].IsKeyboardFocused);
            Assert.True(window.MoveToolbarFocus(-1));
            Assert.True(buttons[^1].IsKeyboardFocused);
            Assert.True(buttons[^1].MoveFocus(new TraversalRequest(
                FocusNavigationDirection.Next)));
            Assert.True(buttons[0].IsKeyboardFocused);

            PressSpace(buttons[1], window);
            Assert.Equal(ScreenshotToolbarAction.Pen, invoked?.Action);

            var colorButton = buttons.Single(button =>
                button.DataContext is ScreenshotToolbarItemViewModel
                {
                    Action: ScreenshotToolbarAction.Color,
                });
            PressSpace(colorButton, window);
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);

            Assert.True(window.StylePopover.IsOpen);
            Assert.Equal(152, window.StylePopoverBorder.ActualWidth);
            Assert.Equal(44, window.StylePopoverBorder.ActualHeight);
            var options = window.StyleOptionButtons;
            Assert.Equal(4, options.Count);
            Assert.All(options, option =>
            {
                Assert.Equal(28, option.ActualWidth);
                Assert.Equal(28, option.ActualHeight);
                Assert.True(option.IsTabStop);
                Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(option)));
                Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetHelpText(option)));
            });
            Assert.True(
                options[0].IsKeyboardFocused,
                $"WindowActive={window.IsActive}; PopupOpen={window.StylePopover.IsOpen}; "
                + $"PopupFocusable={window.StylePopover.Focusable}; "
                + $"OptionVisible={options[0].IsVisible}; OptionLoaded={options[0].IsLoaded}; "
                + $"OptionSource={PresentationSource.FromVisual(options[0]) is not null}; "
                + $"KeyboardFocused={Keyboard.FocusedElement?.GetType().Name ?? "<null>"}");
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetItemStatus(options[0])));

            PressPreviewKey(options[0], window, Key.Right);
            Assert.True(options[1].IsKeyboardFocused);
            PressPreviewKey(options[1], window, Key.Escape);
            Assert.False(window.StylePopover.IsOpen);
            Assert.True(colorButton.IsKeyboardFocused);

            PressSpace(colorButton, window);
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);
            Assert.True(window.StylePopover.IsOpen);
            window.DismissStylePopover();
            Assert.False(window.StylePopover.IsOpen);

            PressSpace(colorButton, window);
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);
            options = window.StyleOptionButtons;

            options[1].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));

            Assert.Equal(ScreenshotToolbarAction.Color, invoked?.Action);
            Assert.Equal(AnnotationColor.Red, invoked?.Value);
            Assert.Equal(AnnotationColor.Red, window.ViewModel.CurrentColor);
            Assert.False(window.StylePopover.IsOpen);
            Assert.True(colorButton.IsKeyboardFocused);
            Assert.NotEqual(
                AutomationProperties.GetName(colorButton),
                AutomationProperties.GetHelpText(colorButton));

            window.ViewModel.UpdateCommandAvailability(new ScreenshotToolbarCommandAvailability(
                CanCopy: false,
                CanPaste: false,
                CanDuplicate: false,
                CanUndo: false,
                CanRedo: false));
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.DataBind);
            Assert.False(buttons.Single(button =>
                button.DataContext is ScreenshotToolbarItemViewModel
                {
                    Action: ScreenshotToolbarAction.Undo,
                }).IsEnabled);

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Hook_navigation_methods_keep_tab_shift_tab_space_and_popover_reachable()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new ScreenshotToolbarWindow();
            ScreenshotToolbarInvokedEventArgs? invoked = null;
            window.Invoked += (_, eventArgs) => invoked = eventArgs;
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);

            Assert.True(window.FocusFirstTool());
            Assert.True(window.MoveKeyboardFocus(1));
            Assert.True(window.InvokeKeyboardFocusedButton());
            Assert.Equal(ScreenshotToolbarAction.Pen, invoked?.Action);
            Assert.True(window.MoveKeyboardFocus(-1));
            Assert.True(window.ToolButtons[0].IsKeyboardFocused);

            var colorButton = ToolButton(window, ScreenshotToolbarAction.Color);
            Assert.True(colorButton.Focus());
            Assert.True(window.InvokeKeyboardFocusedButton());
            DrainPopoverTransitions(window);
            Assert.True(window.StylePopover.IsOpen);
            Assert.True(window.StyleOptionButtons[0].IsKeyboardFocused);
            Assert.True(window.MoveKeyboardFocus(1));
            Assert.True(window.InvokeKeyboardFocusedButton());
            Assert.Equal(ScreenshotToolbarAction.Color, invoked?.Action);
            Assert.Equal(AnnotationColor.Red, invoked?.Value);
            Assert.False(window.StylePopover.IsOpen);

            Assert.True(window.FocusLastTool());
            Assert.True(window.ToolButtons[^1].IsKeyboardFocused);
            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Style_popover_reopens_after_escape_and_immediate_space_without_an_idle_gap()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new ScreenshotToolbarWindow();
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.Background);
            var colorButton = window.ToolButtons.Single(button =>
                button.DataContext is ScreenshotToolbarItemViewModel
                {
                    Action: ScreenshotToolbarAction.Color,
                });

            PressSpace(colorButton, window);
            DrainPopoverTransitions(window);

            for (var iteration = 0; iteration < 100; iteration++)
            {
                Assert.True(window.StylePopover.IsOpen);
                var firstOption = Assert.IsType<Button>(window.StyleOptionButtons.First());
                Assert.True(firstOption.IsKeyboardFocused);

                PressPreviewKey(firstOption, window, Key.Escape);
                Assert.False(window.StylePopover.IsOpen);
                Assert.True(colorButton.IsKeyboardFocused);

                PressSpace(colorButton, window);
                DrainPopoverTransitions(window);

                Assert.True(window.StylePopover.IsOpen);
                Assert.Equal(4, window.StyleOptionButtons.Count);
                Assert.True(window.StyleOptionButtons[0].IsKeyboardFocused);
            }

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Style_popover_switches_actions_in_place_and_focuses_the_replaced_options()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new ScreenshotToolbarWindow();
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.Background);
            var colorButton = ToolButton(window, ScreenshotToolbarAction.Color);
            var lineWidthButton = ToolButton(window, ScreenshotToolbarAction.LineWidth);
            var fontSizeButton = ToolButton(window, ScreenshotToolbarAction.FontSize);

            PressSpace(colorButton, window);
            DrainPopoverTransitions(window);
            Assert.Equal(4, window.StyleOptionButtons.Count);

            PressSpace(lineWidthButton, window);
            PressSpace(fontSizeButton, window);
            DrainPopoverTransitions(window);

            Assert.True(window.StylePopover.IsOpen);
            Assert.Equal(fontSizeButton, window.StylePopover.PlacementTarget);
            Assert.Equal(3, window.StyleOptionButtons.Count);
            Assert.All(
                window.StyleOptionButtons,
                option => Assert.Equal(
                    ScreenshotToolbarAction.FontSize,
                    Assert.IsType<ScreenshotToolbarStyleOptionViewModel>(
                        option.DataContext).Action));
            Assert.True(window.StyleOptionButtons[0].IsKeyboardFocused);

            window.Close();
            return Task.CompletedTask;
        });
    }

    private static Button ToolButton(
        ScreenshotToolbarWindow window,
        ScreenshotToolbarAction action) =>
        window.ToolButtons.Single(button =>
            button.DataContext is ScreenshotToolbarItemViewModel item
            && item.Action == action);

    private static void PressSpace(Button button, Window window)
    {
        Assert.True(button.Focus());
        Assert.True(button.IsKeyboardFocused);
        var source = PresentationSource.FromVisual(window);
        Assert.NotNull(source);
        button.RaiseEvent(new KeyEventArgs(
            Keyboard.PrimaryDevice,
            source,
            Environment.TickCount,
            Key.Space)
        {
            RoutedEvent = Keyboard.PreviewKeyDownEvent,
        });
    }

    private static void PressPreviewKey(Button button, Window window, Key key)
    {
        var source = PresentationSource.FromVisual(window);
        Assert.NotNull(source);
        button.RaiseEvent(new KeyEventArgs(
            Keyboard.PrimaryDevice,
            source,
            Environment.TickCount,
            key)
        {
            RoutedEvent = Keyboard.PreviewKeyDownEvent,
        });
    }

    private static void DrainPopoverTransitions(Window window) =>
        window.Dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);
}
