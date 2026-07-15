using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Shell;
using CheckBox = System.Windows.Controls.CheckBox;
using UserControl = System.Windows.Controls.UserControl;

namespace VoxFlow.Windows.App.Settings;

public partial class LlmProviderSettingsView : UserControl
{
    private bool loaded;

    public LlmProviderSettingsView() => InitializeComponent();

    private LlmProviderSettingsViewModel? ViewModel =>
        DataContext as LlmProviderSettingsViewModel;

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (loaded || ViewModel is null)
        {
            return;
        }
        loaded = true;
        await RunAsync(() => ViewModel.LoadAsync(CancellationToken.None));
    }

    private void OnAddProvider(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        // Default template chip is Custom (mac sheet opens with a blank custom form).
        ViewModel.BeginAdd("custom");
        _ = LlmProviderEditorDialogWindow.Show(Window.GetWindow(this), ViewModel);
    }

    private async void OnEditProvider(object sender, RoutedEventArgs e)
    {
        var providerId = Id(sender);
        if (providerId is null || ViewModel is null)
        {
            return;
        }

        await RunAsync(async () =>
        {
            await ViewModel.BeginEditAsync(providerId, CancellationToken.None);
            if (ViewModel.Editor is not null)
            {
                _ = LlmProviderEditorDialogWindow.Show(
                    Window.GetWindow(this),
                    ViewModel);
            }
        });
    }

    private void OnSetDefault(object sender, RoutedEventArgs e)
    {
        var providerId = Id(sender);
        if (providerId is null || ViewModel is null)
        {
            return;
        }
        try
        {
            _ = ViewModel.SetDefault(providerId);
        }
        catch
        {
            ViewModel.ReportUiFailure();
        }
    }

    private void OnToggleProvider(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox
            { Tag: string providerId, IsChecked: bool enabled }
            || ViewModel is null)
        {
            return;
        }
        try
        {
            _ = ViewModel.SetEnabled(providerId, enabled);
        }
        catch
        {
            ViewModel.ReportUiFailure();
        }
    }

    private async void OnTestConnection(object sender, RoutedEventArgs e)
    {
        var providerId = Id(sender);
        if (providerId is not null && ViewModel is not null)
        {
            await RunAsync(async () =>
            {
                _ = await ViewModel.TestConnectionAsync(
                    providerId,
                    CancellationToken.None);
            });
        }
    }

    private async void OnTestAgent(object sender, RoutedEventArgs e)
    {
        var providerId = Id(sender);
        if (providerId is not null && ViewModel is not null)
        {
            await RunAsync(async () =>
            {
                _ = await ViewModel.TestAgentAsync(
                    providerId,
                    CancellationToken.None);
            });
        }
    }

    private async void OnDeleteProvider(object sender, RoutedEventArgs e)
    {
        var providerId = Id(sender);
        if (providerId is null || ViewModel is null)
        {
            return;
        }
        var confirmed = VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.LlmProviderDeleteConfirmationTitle,
            L10n.LlmProviderDeleteConfirmationMessage,
            L10n.LlmProviderDelete);
        await RunAsync(async () =>
        {
            _ = await ViewModel.DeleteAsync(
                providerId,
                confirmed,
                CancellationToken.None);
        });
    }

    private async Task RunAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            ViewModel?.ReportUiFailure();
        }
    }

    private static string? Id(object sender) =>
        (sender as FrameworkElement)?.Tag as string;
}
