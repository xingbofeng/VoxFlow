using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Settings;

public partial class GeneralSettingsView : System.Windows.Controls.UserControl
{
    public GeneralSettingsView() => InitializeComponent();

    private void OnOpenMicrophonePrivacy(object sender, RoutedEventArgs e) =>
        _ = Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone")
        {
            UseShellExecute = true,
        });

    private void OnResetSettings(object sender, RoutedEventArgs e) =>
        _ = System.Windows.MessageBox.Show(
            L10n.Localize("SettingsResetConfirmationMessage"),
            L10n.Localize("SettingsResetConfirmationTitle"),
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
}
