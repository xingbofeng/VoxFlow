using System.Windows.Controls;
using System.Windows;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Settings;

public partial class OpenAiSettingsCardView : System.Windows.Controls.UserControl
{
    public OpenAiSettingsCardView() => InitializeComponent();

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (DataContext is not OpenAiSettingsCardViewModel viewModel
            || string.IsNullOrWhiteSpace(ApiKeyBox.Password))
        {
            return;
        }

        await viewModel.SaveAsync(
            ApiKeyBox.Password,
            viewModel.Model,
            viewModel.Enabled,
            CancellationToken.None);
        ApiKeyBox.Clear();
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

        var confirmed = System.Windows.MessageBox.Show(
            L10n.Localize("SettingsDeleteConfirmationMessage"),
            L10n.Localize("SettingsDeleteConfirmationTitle"),
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning) == MessageBoxResult.OK;
        _ = await viewModel.DeleteAsync(confirmed, CancellationToken.None);
        if (confirmed)
        {
            ApiKeyBox.Clear();
        }
    }
}
