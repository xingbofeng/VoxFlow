using System.Windows;
using System.Windows.Interop;
using System.Windows.Controls;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.App;

public partial class MainWindow : Window
{
    private readonly Func<int, bool>? windowMessageHandler;
    private HwndSource? windowSource;

    public MainWindow()
        : this(null)
    {
    }

    public MainWindow(
        HomeDashboardViewModel? homeDashboard,
        SettingsPageViewModel? settingsPage = null,
        FileTranscriptionPageViewModel? fileTranscriptionPage = null,
        ScreenshotMediaPageViewModel? screenshotMediaPage = null,
        Func<int, bool>? windowMessageHandler = null,
        IGlossaryStore? glossaryStore = null,
        IWritingStyleStore? writingStyleStore = null,
        IGlossarySuggestionSource? glossarySuggestionSource = null)
    {
        this.windowMessageHandler = windowMessageHandler;
        InitializeComponent();
        ViewModel = new MainShellViewModel(
            homeDashboard,
            settingsPage,
            fileTranscriptionPage,
            screenshotMediaPage,
            glossaryStore,
            writingStyleStore,
            glossarySuggestionSource);
        DataContext = ViewModel;
        SourceInitialized += OnSourceInitialized;
        Closed += OnClosed;
    }

    public MainShellViewModel ViewModel { get; }

    private void OnToggleSidebar(object sender, RoutedEventArgs e) =>
        ViewModel.ToggleSidebar();

    private void OnNavigationSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as System.Windows.Controls.ListBox)?.SelectedItem is NavigationItemViewModel item
            && ViewModel.CurrentRoute != item.Route)
        {
            ViewModel.CurrentRoute = item.Route;
        }
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        windowSource = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
        windowSource?.AddHook(HandleWindowMessage);
    }

    private void OnClosed(object? sender, EventArgs eventArgs)
    {
        windowSource?.RemoveHook(HandleWindowMessage);
        windowSource = null;
        SourceInitialized -= OnSourceInitialized;
        Closed -= OnClosed;
    }

    private nint HandleWindowMessage(
        nint windowHandle,
        int message,
        nint wordParameter,
        nint longParameter,
        ref bool handled)
    {
        _ = windowHandle;
        _ = wordParameter;
        _ = longParameter;
        _ = windowMessageHandler?.Invoke(message);
        // Capture invalidation observes topology messages; WPF must still see them.
        handled = false;
        return nint.Zero;
    }
}
