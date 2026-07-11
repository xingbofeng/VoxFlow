using System.Windows.Controls;
using System.Windows;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Settings;

public partial class ModelsSettingsView : System.Windows.Controls.UserControl
{
    public ModelsSettingsView() => InitializeComponent();

    private ModelsSettingsPageViewModel? ViewModel =>
        DataContext as ModelsSettingsPageViewModel;

    private async void OnSaveTencent(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.SaveTencentAsync(
            TencentAppId.Password,
            TencentSecretId.Password,
            TencentSecretKey.Password,
            CancellationToken.None);
        Clear(TencentAppId, TencentSecretId, TencentSecretKey);
    }

    private async void OnSaveAliyun(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.SaveAliyunAsync(AliyunApiKey.Password, CancellationToken.None);
        Clear(AliyunApiKey);
    }

    private async void OnSaveVolcengine(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.SaveVolcengineAsync(
            VolcengineAppId.Password,
            VolcengineAccessToken.Password,
            VolcengineSecretKey.Password,
            CancellationToken.None);
        Clear(VolcengineAppId, VolcengineAccessToken, VolcengineSecretKey);
    }

    private async void OnTestTencent(object sender, RoutedEventArgs e) =>
        await TestAsync(AsrProviderId.TencentCloud);

    private async void OnTestAliyun(object sender, RoutedEventArgs e) =>
        await TestAsync(AsrProviderId.AliyunDashScope);

    private async void OnTestVolcengine(object sender, RoutedEventArgs e) =>
        await TestAsync(AsrProviderId.Volcengine);

    private async Task TestAsync(AsrProviderId provider)
    {
        if (ViewModel is not null)
        {
            _ = await ViewModel.TestCloudAsync(provider, CancellationToken.None);
        }
    }

    private async void OnDeleteTencent(object sender, RoutedEventArgs e) =>
        await DeleteAsync(AsrProviderId.TencentCloud);

    private async void OnDeleteAliyun(object sender, RoutedEventArgs e) =>
        await DeleteAsync(AsrProviderId.AliyunDashScope);

    private async void OnDeleteVolcengine(object sender, RoutedEventArgs e) =>
        await DeleteAsync(AsrProviderId.Volcengine);

    private async Task DeleteAsync(AsrProviderId provider)
    {
        if (ViewModel is null)
        {
            return;
        }

        var confirmed = System.Windows.MessageBox.Show(
            L10n.Localize("SettingsCloudDeleteConfirmationMessage"),
            L10n.Localize("SettingsCloudDeleteConfirmationTitle"),
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning) == MessageBoxResult.OK;
        _ = await ViewModel.DeleteCloudAsync(
            provider,
            confirmed,
            CancellationToken.None);
    }

    private static void Clear(params PasswordBox[] fields)
    {
        foreach (var field in fields)
        {
            field.Clear();
        }
    }
}
