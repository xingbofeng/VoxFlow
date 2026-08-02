using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace VoxFlow.Windows.App.Screenshot;

public partial class ScreenshotResultWindow : Window
{
    private bool loaded;

    public ScreenshotResultWindow()
    {
        InitializeComponent();
        Closed += OnClosed;
    }

    public ScreenshotResultViewModel? ViewModel => DataContext as ScreenshotResultViewModel;

    public void ApplyResponsiveBounds(Rect workArea, double margin = 28)
    {
        var bounds = ScreenshotResponsiveWindowLayout.BottomTrailing(
            workArea,
            ScreenshotResultPresentationPolicy.ExpandedWidth,
            ScreenshotResultPresentationPolicy.ExpandedHeight,
            margin);
        MinWidth = Math.Min(340, bounds.Width);
        MinHeight = Math.Min(320, bounds.Height);
        Width = bounds.Width;
        Height = bounds.Height;
        Left = bounds.Left;
        Top = bounds.Top;
    }

    private async void OnLoaded(object sender, RoutedEventArgs eventArgs)
    {
        loaded = true;
        ResultTabs.Focus();
        if (ViewModel is { } viewModel)
        {
            await viewModel.LoadCurrentImageAsync();
        }
    }

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (eventArgs.Key != Key.Escape)
        {
            return;
        }
        eventArgs.Handled = true;
        Close();
    }

    private void OnTitleBarMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs)
    {
        if (eventArgs.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void OnClose(object sender, RoutedEventArgs eventArgs) => Close();

    private async void OnTabSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        if (!loaded || ViewModel is null)
        {
            return;
        }
        await ViewModel.ActivateSelectedTabAsync();
        await ViewModel.LoadCurrentImageAsync();
    }

    private async void OnTranslate(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is not { } viewModel)
        {
            return;
        }
        if (viewModel.TranslationActionState == ScreenshotResultActionState.Running)
        {
            viewModel.CancelTranslation();
            return;
        }
        await viewModel.StartTranslationAsync();
    }

    private async void OnRefine(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is not { } viewModel)
        {
            return;
        }
        if (viewModel.RefinementActionState == ScreenshotResultActionState.Running)
        {
            viewModel.CancelRefinement();
            return;
        }
        await viewModel.StartRefinementAsync();
    }

    private async void OnSpeak(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is { } viewModel)
        {
            try
            {
                await viewModel.ToggleSpeechAsync();
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                viewModel.ReportSpeechFailure();
            }
        }
    }

    private async void OnRetryTransform(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.RetryCurrentTransformAsync();
        }
    }

    private void OnStopSpeech(object sender, RoutedEventArgs eventArgs) =>
        ViewModel?.StopSpeech();

    private void OnCopyText(object sender, RoutedEventArgs eventArgs) =>
        _ = ViewModel?.CopyCurrentText();

    private async void OnCopyImage(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.CopyCurrentImageAsync();
        }
    }

    private void OnClosed(object? sender, EventArgs eventArgs) => ViewModel?.Close();
}
