using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Shell;

public sealed record NavigationItemViewModel(
    ShellRoute Route,
    string Label,
    string Glyph);

public sealed record HomePageViewModel(
    string Heading,
    string Subtitle,
    HomeDashboardViewModel Dashboard);

public sealed class MainShellViewModel : INotifyPropertyChanged
{
    private readonly HomePageViewModel homePage;
    private readonly FileTranscriptionPageViewModel fileTranscriptionPage;
    private readonly SettingsPageViewModel settingsPage;
    private ShellRoute currentRoute = ShellRoute.Home;
    private bool isSidebarCollapsed;

    public MainShellViewModel(
        HomeDashboardViewModel? homeDashboard = null,
        SettingsPageViewModel? settingsPage = null,
        FileTranscriptionPageViewModel? fileTranscriptionPage = null)
    {
        this.settingsPage = settingsPage ?? new SettingsPageViewModel(
            L10n.Localize("SettingsHeading"),
            L10n.Localize("SettingsSubtitle"));
        homeDashboard ??= new HomeDashboardViewModel(
            new EmptyHistoryStore(),
            new WpfTextClipboardWriter(),
            TimeProvider.System);
        homeDashboard.Reload();
        homePage = new HomePageViewModel(
            L10n.Localize("HomeHeading"),
            L10n.Localize("HomeSubtitle"),
            homeDashboard);
        this.fileTranscriptionPage = fileTranscriptionPage
            ?? new FileTranscriptionPageViewModel(
                L10n.Localize("FileTranscriptionHeading"),
                L10n.Localize("FileTranscriptionSubtitle"));

        NavigationItems = new ReadOnlyCollection<NavigationItemViewModel>(
        [
            new(ShellRoute.Home, L10n.Localize("NavigationHome"), "⌂"),
            new(ShellRoute.FileTranscription, L10n.Localize("NavigationFileTranscription"), "≋"),
            new(ShellRoute.Settings, L10n.Localize("NavigationSettings"), "⚙"),
        ]);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<NavigationItemViewModel> NavigationItems { get; }

    public ShellRoute CurrentRoute
    {
        get => currentRoute;
        set
        {
            if (!Enum.IsDefined(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value), value, null);
            }

            if (currentRoute == value)
            {
                return;
            }

            currentRoute = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CurrentPage));
        }
    }

    public object CurrentPage => currentRoute switch
    {
        ShellRoute.Home => homePage,
        ShellRoute.FileTranscription => fileTranscriptionPage,
        ShellRoute.Settings => settingsPage,
        _ => throw new InvalidOperationException("The shell route is not available in Windows v1."),
    };

    public bool IsSidebarCollapsed
    {
        get => isSidebarCollapsed;
        private set
        {
            if (isSidebarCollapsed == value)
            {
                return;
            }

            isSidebarCollapsed = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(SidebarWidth));
        }
    }

    public GridLength SidebarWidth => new(IsSidebarCollapsed ? 56D : 220D);

    public void ToggleSidebar() => IsSidebarCollapsed = !IsSidebarCollapsed;

    public bool TryNavigate(string route)
    {
        var destination = route.Trim().ToLowerInvariant() switch
        {
            "home" => ShellRoute.Home,
            "file-transcription" => ShellRoute.FileTranscription,
            "settings" => ShellRoute.Settings,
            _ => (ShellRoute?)null,
        };

        if (destination is null)
        {
            return false;
        }

        CurrentRoute = destination.Value;
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
