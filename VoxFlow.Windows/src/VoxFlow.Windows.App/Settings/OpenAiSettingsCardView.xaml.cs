using System.Windows.Controls;
using System.Windows;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Settings;

public partial class OpenAiSettingsCardView : System.Windows.Controls.UserControl
{
    public OpenAiSettingsCardView() => InitializeComponent();

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (DataContext is not OpenAiSettingsCardViewModel viewModel)
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(ApiKeyBox.Password))
        {
            viewModel.ReportUiFailure();
            return;
        }

        var saved = await viewModel.SaveAsync(
            ApiKeyBox.Password,
            BaseUrlBox.Text,
            viewModel.Model,
            viewModel.Enabled,
            CancellationToken.None);
        if (saved)
        {
            ApiKeyBox.Clear();
        }
    }

    private async void OnTest(object sender, RoutedEventArgs e)
    {
        if (DataContext is OpenAiSettingsCardViewModel viewModel)
        {
            _ = await viewModel.TestConnectionAsync(CancellationToken.None);
        }
    }

    private async void OnDelete(object sender, RoutedEventArgs e)
    {
        if (DataContext is not OpenAiSettingsCardViewModel viewModel)
        {
            return;
        }

        var confirmed = VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.Localize("SettingsDeleteConfirmationTitle"),
            L10n.Localize("SettingsDeleteConfirmationMessage"),
            L10n.Localize("SettingsActionDelete"));
        var deleted = await viewModel.DeleteAsync(confirmed, CancellationToken.None);
        if (deleted)
        {
            ApiKeyBox.Clear();
        }
    }
}
