using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using WpfComboBox = System.Windows.Controls.ComboBox;
using WpfTextBox = System.Windows.Controls.TextBox;

namespace VoxFlow.Windows.App.Screenshot;

public partial class ScreenshotMediaView : System.Windows.Controls.UserControl
{
    private CancellationTokenSource? searchRefresh;

    public ScreenshotMediaView() => InitializeComponent();

    public event EventHandler? StartScreenshotRequested;

    private ScreenshotMediaPageViewModel? ViewModel =>
        DataContext as ScreenshotMediaPageViewModel;

    private async void OnLoaded(object sender, RoutedEventArgs eventArgs)
    {
        UpdateResponsiveColumns(ActualWidth);
        if (ViewModel is { } viewModel)
        {
            await viewModel.RefreshAsync();
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs eventArgs)
    {
        searchRefresh?.Cancel();
        searchRefresh?.Dispose();
        searchRefresh = null;
    }

    private void OnStartScreenshot(object sender, RoutedEventArgs eventArgs)
    {
        ViewModel?.RequestStartScreenshot();
        StartScreenshotRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnPrevious(object sender, RoutedEventArgs eventArgs) =>
        _ = ViewModel?.GoToPreviousPageAsync();

    private void OnNext(object sender, RoutedEventArgs eventArgs) =>
        _ = ViewModel?.GoToNextPageAsync();

    private async void OnOpenCard(object sender, RoutedEventArgs eventArgs)
    {
        if (sender is not FrameworkElement
            { DataContext: ScreenshotMediaCardViewModel card }
            || ViewModel is not { } viewModel)
        {
            return;
        }

        var details = await viewModel.OpenDetailsAsync(card);
        if (details is null)
        {
            return;
        }
        var owner = Window.GetWindow(this);
        var window = new ScreenshotDetailWindow
        {
            DataContext = details,
        };
        window.PlaceOnOwnerScreen(owner);
        _ = window.ShowDialog();
        await viewModel.RefreshAsync();
    }

    private void OnCardAction(object sender, RoutedEventArgs eventArgs)
    {
        eventArgs.Handled = true;
        if (sender is not FrameworkElement
            {
                Tag: string action,
                DataContext: ScreenshotMediaCardViewModel card,
            })
        {
            return;
        }
        _ = ViewModel?.ExecuteCardActionAsync(card, action);
    }

    private void OnSearchTextChanged(object sender, TextChangedEventArgs eventArgs)
    {
        if (!IsLoaded
            || sender is not WpfTextBox textBox
            || ViewModel is not { } viewModel)
        {
            return;
        }
        viewModel.SearchText = textBox.Text;
        QueueQueryRefresh();
    }

    private void OnFilterChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        if (!IsLoaded
            || sender is not Selector
                { SelectedItem: ScreenshotMediaFilterOption option }
            || ViewModel is not { } viewModel)
        {
            return;
        }
        viewModel.SelectedFilter = option;
        QueueQueryRefresh(immediate: true);
    }

    private void OnPageSizeChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        if (!IsLoaded
            || sender is not WpfComboBox { SelectedItem: int size }
            || ViewModel is not { } viewModel)
        {
            return;
        }
        viewModel.PageSize = size;
        QueueQueryRefresh(immediate: true);
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs eventArgs) =>
        UpdateResponsiveColumns(eventArgs.NewSize.Width);

    private void UpdateResponsiveColumns(double width) =>
        ViewModel?.UpdateViewportWidth(Math.Max(0, width - 56));

    private async void QueueQueryRefresh(bool immediate = false)
    {
        searchRefresh?.Cancel();
        searchRefresh?.Dispose();
        searchRefresh = new CancellationTokenSource();
        var cancellationToken = searchRefresh.Token;
        try
        {
            if (!immediate)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(200), cancellationToken);
            }
            if (ViewModel is { } viewModel)
            {
                await viewModel.RefreshAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // A newer query superseded this refresh.
        }
    }
}
