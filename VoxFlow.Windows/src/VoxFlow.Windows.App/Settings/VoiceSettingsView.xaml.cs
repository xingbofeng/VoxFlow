using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Settings;

public partial class VoiceSettingsView : System.Windows.Controls.UserControl
{
    private bool refreshed;

    public VoiceSettingsView() => InitializeComponent();

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (refreshed)
        {
            return;
        }

        refreshed = true;
        if (DataContext is VoiceSettingsPageViewModel voice)
        {
            voice.RefreshAvailableDevices();
        }
    }
}
