using System.Diagnostics;
using System.Windows;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Help;

public partial class HelpView : System.Windows.Controls.UserControl
{
    public HelpView() => InitializeComponent();

    private HelpPageViewModel? ViewModel => DataContext as HelpPageViewModel;

    private async void OnOpenLink(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not HelpLinkViewModel link)
        {
            // Backward-compatible: raw URL tag.
            if ((sender as FrameworkElement)?.Tag is string url)
            {
                OpenUrl(url);
            }

            return;
        }

        if (link.IsUpdateAction && ViewModel is not null)
        {
            var result = await ViewModel.CheckForUpdatesAsync().ConfigureAwait(true);
            if (result.Availability == Application.Update.AppUpdateAvailability.UpdateAvailable
                && result.CanOpenReleasePage)
            {
                OpenUrl(result.ReleaseUrl!);
            }

            return;
        }

        OpenUrl(link.Url);
    }

    private static void OpenUrl(string url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            return;
        }

        try
        {
            _ = Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
            // Link failures remain local and do not take down the settings window.
        }
    }
}
