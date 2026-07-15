using System.Windows;
using System.Windows.Input;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;

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
        e.Handled = true;
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.ToggleSelection(id);
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.CopyEntry(id);
        }
    }

    private void OnDetailsClick(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.OpenDetail(id);
        }
    }

    private void OnAssetRowClick(object sender, MouseButtonEventArgs e)
    {
        // Let checkbox/button clicks handle themselves; open detail for row body.
        if (e.OriginalSource is DependencyObject source
            && (FindAncestor<System.Windows.Controls.Button>(source) is not null
                || FindAncestor<System.Windows.Controls.CheckBox>(source) is not null))
        {
            return;
        }

        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.OpenDetail(id);
            e.Handled = true;
        }
    }

    private void OnDeleteClick(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (ViewModel is { } viewModel
            && ReadId(sender) is { } id
            && Confirm("HistoryDeleteConfirmationMessage"))
        {
            viewModel.DeleteEntry(id);
        }
    }

    private void OnDeleteSelectedClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { CanDeleteSelected: true } viewModel
            && Confirm("HistoryDeleteSelectedConfirmationMessage"))
        {
            viewModel.DeleteSelected();
        }
    }

    private void OnSelectAllClick(object sender, RoutedEventArgs e) =>
        ViewModel?.SelectAllVisible();

    private void OnClearAllClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { CanClearAll: true } viewModel
            && Confirm("HistoryClearAllConfirmationMessage"))
        {
            viewModel.ClearAll();
        }
    }

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

    private void OnDetailBackdropClick(object sender, MouseButtonEventArgs e)
    {
        ViewModel?.CloseDetail();
        e.Handled = true;
    }

    private void OnDetailCardMouseDown(object sender, MouseButtonEventArgs e)
    {
        // Prevent backdrop close when interacting with the modal body.
        e.Handled = true;
    }

    private void OnDetailCopyClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel && ReadId(sender) is { } id)
        {
            viewModel.CopyEntry(id);
        }
    }

    private void OnDetailDeleteClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel
            && ReadId(sender) is { } id
            && Confirm("HistoryDeleteConfirmationMessage"))
        {
            viewModel.DeleteEntry(id);
        }
    }

    private void OnSaveEditClick(object sender, RoutedEventArgs e) =>
        ViewModel?.SaveSelectedEdit();

    private async void OnReprocessClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            try
            {
                await viewModel.ReprocessSelectedAsync(CancellationToken.None);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                viewModel.ReportActionFailure();
            }
        }
    }

    private void OnCopyDiagnosticClick(object sender, RoutedEventArgs e) =>
        ViewModel?.CopySelectedDiagnostic();

    private bool Confirm(string messageKey) => VoxFlowDialogWindow.ShowConfirm(
        Window.GetWindow(this),
        L10n.Localize("HistoryDeleteConfirmationTitle"),
        L10n.Localize(messageKey),
        L10n.Localize("HistoryDelete"));

    private static T? FindAncestor<T>(DependencyObject? current)
        where T : DependencyObject
    {
        while (current is not null)
        {
            if (current is T match)
            {
                return match;
            }

            current = System.Windows.Media.VisualTreeHelper.GetParent(current);
        }

        return null;
    }
}
