using System.Windows;

namespace VoxFlow.Windows.App.Home;

public partial class HomeDashboardView : System.Windows.Controls.UserControl
{
    public HomeDashboardView() => InitializeComponent();

    private HomeDashboardViewModel? ViewModel =>
        DataContext as HomeDashboardViewModel;

    private static string? ReadId(object sender) =>
        (sender as FrameworkElement)?.Tag as string;

    private void OnSelectionClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.ToggleSelection(id);
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.CopyEntry(id);
        }
    }

    private void OnDetailsClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.OpenDetail(id);
        }
    }

    private void OnDeleteClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.DeleteEntry(id);
        }
    }

    private void OnDeleteSelectedClick(object sender, RoutedEventArgs e) =>
        ViewModel?.DeleteSelected();

    private void OnClearAllClick(object sender, RoutedEventArgs e) =>
        ViewModel?.ClearAll();

    private void OnPreviousPageClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            viewModel.GoToPage(viewModel.CurrentPage - 1);
        }
    }

    private void OnNextPageClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            viewModel.GoToPage(viewModel.CurrentPage + 1);
        }
    }

    private void OnCloseDetailClick(object sender, RoutedEventArgs e) =>
        ViewModel?.CloseDetail();

    private void OnSaveEditClick(object sender, RoutedEventArgs e) =>
        ViewModel?.SaveSelectedEdit();

    private async void OnReprocessClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.ReprocessSelectedAsync(CancellationToken.None);
        }
    }

    private void OnCopyDiagnosticClick(object sender, RoutedEventArgs e) =>
        ViewModel?.CopySelectedDiagnostic();
}
