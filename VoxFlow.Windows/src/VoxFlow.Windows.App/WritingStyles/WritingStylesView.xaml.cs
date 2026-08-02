using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.WritingStyles;

public partial class WritingStylesView : System.Windows.Controls.UserControl
{
    private bool loaded;

    public WritingStylesView() => InitializeComponent();

    private WritingStylesPageViewModel? ViewModel => DataContext as WritingStylesPageViewModel;

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (loaded || ViewModel is null)
        {
            return;
        }
        loaded = true;
        await ViewModel.LoadAsync();
    }

    private void OnAddProfile(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }
        var dialog = new VoxFlowFormDialogWindow(
            Window.GetWindow(this),
            L10n.Localize("WritingStylesAddProfileTitle"),
            L10n.Localize("WritingStylesNameLabel"));
        if (dialog.ShowDialog() == true)
        {
            ViewModel.AddProfile(dialog.PrimaryText);
        }
    }

    private async void OnDeleteProfile(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.SelectedProfile is null)
        {
            return;
        }
        if (VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.Localize("WritingStylesDeleteTitle"),
            L10n.Localize("WritingStylesDeleteMessage")))
        {
            await ViewModel.DeleteSelectedAsync();
        }
    }

    private async void OnRestore(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null && VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.Localize("WritingStylesRestoreTitle"),
            L10n.Localize("WritingStylesRestoreMessage"),
            kind: VoxFlowDialogKind.Warning))
        {
            await ViewModel.RestoreDefaultsAsync();
        }
    }

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null)
        {
            await ViewModel.SaveAsync();
        }
    }
}
