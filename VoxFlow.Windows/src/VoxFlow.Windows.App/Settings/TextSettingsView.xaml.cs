using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Settings;

public partial class TextSettingsView : System.Windows.Controls.UserControl
{
    public TextSettingsView() => InitializeComponent();

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (DataContext is TextSettingsPageViewModel viewModel)
        {
            await viewModel.SaveAsync(CancellationToken.None);
        }
    }
}
