using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Settings;

public partial class GeneralSettingsView : System.Windows.Controls.UserControl
{
    public GeneralSettingsView() => InitializeComponent();

    private void OnOpenMicrophonePrivacy(object sender, RoutedEventArgs e)
    {
        try
        {
            _ = Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone")
            {
                UseShellExecute = true,
            });
        }
        catch
        {
            ShowActionFailure();
        }
    }

    private async void OnCopyDiagnostics(object sender, RoutedEventArgs e)
    {
        if (DataContext is GeneralSettingsPageViewModel viewModel)
        {
            _ = await viewModel.CopyDiagnosticsAsync(CancellationToken.None);
        }
    }

    private async void OnResetSettings(object sender, RoutedEventArgs e)
    {
        if (DataContext is not GeneralSettingsPageViewModel viewModel)
        {
            return;
        }
        var confirmed = VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.Localize("SettingsResetConfirmationTitle"),
            L10n.Localize("SettingsResetConfirmationMessage"),
            L10n.Localize("DialogConfirm"),
            VoxFlowDialogKind.Warning);
        _ = await viewModel.ResetAsync(confirmed, CancellationToken.None);
    }

    private async void OnRunDebugTranscript(object sender, RoutedEventArgs e)
    {
#if DEBUG
        if (DataContext is GeneralSettingsPageViewModel
            {
                DebugTranscript: { } debug,
            })
        {
            _ = await debug.RunAsync(CancellationToken.None);
        }
#else
        await Task.CompletedTask;
#endif
    }

    private void ShowActionFailure() => VoxFlowDialogWindow.ShowMessage(
        Window.GetWindow(this),
        L10n.Localize("SettingsGeneralHeading"),
        L10n.Localize("SettingsGeneralActionFailed"),
        VoxFlowDialogKind.Warning);
}
