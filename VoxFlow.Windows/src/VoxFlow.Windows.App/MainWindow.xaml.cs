using System.Windows;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App;

public partial class MainWindow : Window
{
    public MainWindow()
        : this(null)
    {
    }

    public MainWindow(
        HomeDashboardViewModel? homeDashboard,
        SettingsPageViewModel? settingsPage = null,
        FileTranscriptionPageViewModel? fileTranscriptionPage = null)
    {
        InitializeComponent();
        ViewModel = new MainShellViewModel(homeDashboard, settingsPage, fileTranscriptionPage);
        DataContext = ViewModel;
    }

    public MainShellViewModel ViewModel { get; }

    private void OnToggleSidebar(object sender, RoutedEventArgs e) =>
        ViewModel.ToggleSidebar();
}
