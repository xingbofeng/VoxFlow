using System.Windows.Controls;
using System.Windows;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Settings;

public partial class ModelsSettingsView : System.Windows.Controls.UserControl
{
    public ModelsSettingsView() => InitializeComponent();

    private ModelsSettingsPageViewModel? ViewModel =>
        DataContext as ModelsSettingsPageViewModel;

    private async void OnQwenPrimary(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is QwenModelSettingsCardViewModel card)
        {
            try
            {
                _ = await card.ExecutePrimaryAsync(CancellationToken.None);
            }
            catch
            {
                card.ReportUnexpectedFailure();
            }
        }
    }

    private async void OnQwenDelete(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is QwenModelSettingsCardViewModel card)
        {
            try
            {
                var confirmed = VoxFlowDialogWindow.ShowConfirm(
                    Window.GetWindow(this),
                    L10n.Localize("SettingsModelDeleteConfirmationTitle"),
                    L10n.Localize("SettingsModelDeleteConfirmationMessage"),
                    L10n.Localize("SettingsActionDelete"));
                _ = await card.DeleteAsync(confirmed, CancellationToken.None);
            }
            catch
            {
                card.ReportUnexpectedFailure();
            }
        }
    }

    private async void OnSaveTencent(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        var saved = await ViewModel.SaveTencentAsync(
            ReadSecret(TencentAppId, TencentAppIdVisible),
            ReadSecret(TencentSecretId, TencentSecretIdVisible),
            ReadSecret(TencentSecretKey, TencentSecretKeyVisible),
            CancellationToken.None);
        if (saved)
        {
            HideSecrets(
                ViewModel.Tencent,
                (TencentAppId, TencentAppIdVisible),
                (TencentSecretId, TencentSecretIdVisible),
                (TencentSecretKey, TencentSecretKeyVisible));
        }
    }

    private async void OnSaveAliyun(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        var saved = await ViewModel.SaveAliyunAsync(
            ReadSecret(AliyunApiKey, AliyunApiKeyVisible),
            CancellationToken.None);
        if (saved)
        {
            HideSecrets(ViewModel.Aliyun, (AliyunApiKey, AliyunApiKeyVisible));
        }
    }

    private async void OnSaveVolcengine(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        var saved = await ViewModel.SaveVolcengineAsync(
            ReadSecret(VolcengineAppId, VolcengineAppIdVisible),
            ReadSecret(VolcengineAccessToken, VolcengineAccessTokenVisible),
            ReadSecret(VolcengineSecretKey, VolcengineSecretKeyVisible),
            CancellationToken.None);
        if (saved)
        {
            HideSecrets(
                ViewModel.Volcengine,
                (VolcengineAppId, VolcengineAppIdVisible),
                (VolcengineAccessToken, VolcengineAccessTokenVisible),
                (VolcengineSecretKey, VolcengineSecretKeyVisible));
        }
    }

    private async void OnTestTencent(object sender, RoutedEventArgs e) =>
        await TestAsync(AsrProviderId.TencentCloud);

    private async void OnTestAliyun(object sender, RoutedEventArgs e) =>
        await TestAsync(AsrProviderId.AliyunDashScope);

    private async void OnTestVolcengine(object sender, RoutedEventArgs e) =>
        await TestAsync(AsrProviderId.Volcengine);

    private async void OnTestBuiltinAgent(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null)
        {
            _ = await ViewModel.BuiltinAgent.TestAsync(CancellationToken.None);
        }
    }

    private void OnSelectTencent(object sender, RoutedEventArgs e) =>
        ViewModel?.SelectCloud(AsrProviderId.TencentCloud);

    private void OnSelectAliyun(object sender, RoutedEventArgs e) =>
        ViewModel?.SelectCloud(AsrProviderId.AliyunDashScope);

    private void OnSelectVolcengine(object sender, RoutedEventArgs e) =>
        ViewModel?.SelectCloud(AsrProviderId.Volcengine);

    private async void OnToggleTencentSecrets(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        if (ViewModel.Tencent.SecretsVisible)
        {
            HideSecrets(
                ViewModel.Tencent,
                (TencentAppId, TencentAppIdVisible),
                (TencentSecretId, TencentSecretIdVisible),
                (TencentSecretKey, TencentSecretKeyVisible));
            return;
        }

        try
        {
            var credentials = await ViewModel.RevealTencentAsync(CancellationToken.None);
            if (credentials is null)
            {
                return;
            }

            ShowSecrets(
                ViewModel.Tencent,
                (TencentAppId, TencentAppIdVisible, credentials.AppId),
                (TencentSecretId, TencentSecretIdVisible, credentials.SecretId),
                (TencentSecretKey, TencentSecretKeyVisible, credentials.SecretKey));
        }
        catch
        {
            // Keep the masked presentation if reveal fails.
        }
    }

    private async void OnToggleAliyunSecrets(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        if (ViewModel.Aliyun.SecretsVisible)
        {
            HideSecrets(ViewModel.Aliyun, (AliyunApiKey, AliyunApiKeyVisible));
            return;
        }

        try
        {
            var apiKey = await ViewModel.RevealAliyunApiKeyAsync(CancellationToken.None);
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                return;
            }

            ShowSecrets(ViewModel.Aliyun, (AliyunApiKey, AliyunApiKeyVisible, apiKey));
        }
        catch
        {
            // Keep the masked presentation if reveal fails.
        }
    }

    private async void OnToggleVolcengineSecrets(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        if (ViewModel.Volcengine.SecretsVisible)
        {
            HideSecrets(
                ViewModel.Volcengine,
                (VolcengineAppId, VolcengineAppIdVisible),
                (VolcengineAccessToken, VolcengineAccessTokenVisible),
                (VolcengineSecretKey, VolcengineSecretKeyVisible));
            return;
        }

        try
        {
            var credentials = await ViewModel.RevealVolcengineAsync(CancellationToken.None);
            if (credentials is null)
            {
                return;
            }

            ShowSecrets(
                ViewModel.Volcengine,
                (VolcengineAppId, VolcengineAppIdVisible, credentials.AppId),
                (VolcengineAccessToken, VolcengineAccessTokenVisible, credentials.AccessToken),
                (VolcengineSecretKey, VolcengineSecretKeyVisible, credentials.SecretKey));
        }
        catch
        {
            // Keep the masked presentation if reveal fails.
        }
    }

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

        var confirmed = VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.Localize("SettingsCloudDeleteConfirmationTitle"),
            L10n.Localize("SettingsCloudDeleteConfirmationMessage"),
            L10n.Localize("SettingsActionDelete"));
        var deleted = await ViewModel.DeleteCloudAsync(
            provider,
            confirmed,
            CancellationToken.None);
        if (!deleted)
        {
            return;
        }

        switch (provider)
        {
            case AsrProviderId.TencentCloud:
                HideSecrets(
                    ViewModel.Tencent,
                    (TencentAppId, TencentAppIdVisible),
                    (TencentSecretId, TencentSecretIdVisible),
                    (TencentSecretKey, TencentSecretKeyVisible));
                break;
            case AsrProviderId.AliyunDashScope:
                HideSecrets(ViewModel.Aliyun, (AliyunApiKey, AliyunApiKeyVisible));
                break;
            case AsrProviderId.Volcengine:
                HideSecrets(
                    ViewModel.Volcengine,
                    (VolcengineAppId, VolcengineAppIdVisible),
                    (VolcengineAccessToken, VolcengineAccessTokenVisible),
                    (VolcengineSecretKey, VolcengineSecretKeyVisible));
                break;
        }
    }

    private static string ReadSecret(PasswordBox hidden, System.Windows.Controls.TextBox visible) =>
        visible.Visibility == Visibility.Visible
            ? visible.Text
            : hidden.Password;

    private static void ShowSecrets(
        CloudProviderSettingsCardViewModel card,
        params (PasswordBox Hidden, System.Windows.Controls.TextBox Visible, string Value)[] fields)
    {
        foreach (var (hidden, visible, value) in fields)
        {
            visible.Text = value;
            visible.Visibility = Visibility.Visible;
            hidden.Visibility = Visibility.Collapsed;
            hidden.Clear();
        }

        card.SetSecretsVisible(true);
    }

    private static void HideSecrets(
        CloudProviderSettingsCardViewModel card,
        params (PasswordBox Hidden, System.Windows.Controls.TextBox Visible)[] fields)
    {
        foreach (var (hidden, visible) in fields)
        {
            visible.Clear();
            visible.Visibility = Visibility.Collapsed;
            hidden.Clear();
            hidden.Visibility = Visibility.Visible;
        }

        card.SetSecretsVisible(false);
    }
}
