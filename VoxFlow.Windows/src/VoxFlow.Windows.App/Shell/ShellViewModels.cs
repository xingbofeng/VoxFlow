using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Text;

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
    private readonly ScreenshotMediaPageViewModel mediaPage;
    private readonly SettingsPageViewModel settingsPage;
    private readonly AgentWorkspacePageViewModel agentWorkspacePage;
    private readonly GlossaryPageViewModel glossaryPage;
    private readonly WritingStylesPageViewModel writingStylesPage;
    private readonly NotesPageViewModel notesPage;
    private readonly HelpPageViewModel helpPage;
    private ShellRoute currentRoute = ShellRoute.Home;
    private bool isSidebarCollapsed;

    public MainShellViewModel(
        HomeDashboardViewModel? homeDashboard = null,
        SettingsPageViewModel? settingsPage = null,
        FileTranscriptionPageViewModel? fileTranscriptionPage = null,
        ScreenshotMediaPageViewModel? mediaPage = null,
        IGlossaryStore? glossaryStore = null,
        IWritingStyleStore? writingStyleStore = null,
        IGlossarySuggestionSource? glossarySuggestionSource = null)
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
        agentWorkspacePage = new AgentWorkspacePageViewModel(homeDashboard);
        glossaryPage = new GlossaryPageViewModel(
            glossaryStore ?? new MemoryGlossaryStore(),
            glossarySuggestionSource);
        writingStylesPage = new WritingStylesPageViewModel(
            writingStyleStore ?? new MemoryWritingStyleStore());
        notesPage = new NotesPageViewModel(homeDashboard);
        helpPage = new HelpPageViewModel();
        this.fileTranscriptionPage = fileTranscriptionPage
            ?? new FileTranscriptionPageViewModel(
                L10n.Localize("FileTranscriptionHeading"),
                L10n.Localize("FileTranscriptionSubtitle"));
        this.mediaPage = mediaPage ?? new ScreenshotMediaPageViewModel(
            L10n.Localize("ScreenshotMediaHeading"),
            L10n.Localize("ScreenshotMediaSubtitle"));

        PrimaryNavigationItems = new ReadOnlyCollection<NavigationItemViewModel>(
        [
            new(ShellRoute.Home, L10n.Localize("NavigationHome"), "\uE80F"),
            new(ShellRoute.Media, L10n.Localize("NavigationMedia"), "\uE91B"),
            new(ShellRoute.AgentWorkspace, L10n.Localize("NavigationAgentWorkspace"), "\uE756"),
            new(ShellRoute.Glossary, L10n.Localize("NavigationGlossary"), "\uE82D"),
            new(ShellRoute.WritingStyles, L10n.Localize("NavigationWritingStyles"), "\uE8D2"),
            new(ShellRoute.FileTranscription, L10n.Localize("NavigationFileTranscription"), "\uE8D2"),
            new(ShellRoute.Notes, L10n.Localize("NavigationNotes"), "\uE70B"),
        ]);
        FooterNavigationItems = new ReadOnlyCollection<NavigationItemViewModel>(
        [
            new(ShellRoute.Settings, L10n.Localize("NavigationSettings"), "\uE713"),
            new(ShellRoute.Help, L10n.Localize("NavigationHelp"), "\uE897"),
        ]);
        NavigationItems = new ReadOnlyCollection<NavigationItemViewModel>(
            [.. PrimaryNavigationItems, .. FooterNavigationItems]);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<NavigationItemViewModel> NavigationItems { get; }

    public IReadOnlyList<NavigationItemViewModel> PrimaryNavigationItems { get; }

    public IReadOnlyList<NavigationItemViewModel> FooterNavigationItems { get; }

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
            if (value == ShellRoute.AgentWorkspace)
            {
                agentWorkspacePage.Refresh();
            }
            else if (value == ShellRoute.Notes)
            {
                notesPage.Refresh();
            }
            OnPropertyChanged();
            OnPropertyChanged(nameof(CurrentPage));
        }
    }

    public object CurrentPage => currentRoute switch
    {
        ShellRoute.Home => homePage,
        ShellRoute.Media => mediaPage,
        ShellRoute.AgentWorkspace => agentWorkspacePage,
        ShellRoute.Glossary => glossaryPage,
        ShellRoute.WritingStyles => writingStylesPage,
        ShellRoute.FileTranscription => fileTranscriptionPage,
        ShellRoute.Notes => notesPage,
        ShellRoute.Settings => settingsPage,
        ShellRoute.Help => helpPage,
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
            "media" or "screenshot" or "screenshots" => ShellRoute.Media,
            "agent" or "ai-coding" or "agent-workspace" => ShellRoute.AgentWorkspace,
            "glossary" or "vocabulary" => ShellRoute.Glossary,
            "styles" or "writing-styles" => ShellRoute.WritingStyles,
            "file-transcription" => ShellRoute.FileTranscription,
            "notes" => ShellRoute.Notes,
            "settings" => ShellRoute.Settings,
            "help" => ShellRoute.Help,
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

    private sealed class MemoryGlossaryStore : IGlossaryStore
    {
        private GlossaryDocument document = GlossaryDocument.Default;

        public ValueTask<GlossaryDocument> LoadAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult(document);

        public ValueTask SaveAsync(GlossaryDocument value, CancellationToken cancellationToken)
        {
            document = value;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class MemoryWritingStyleStore : IWritingStyleStore
    {
        private WritingStyleDocument document = WritingStyleDocument.Default;

        public ValueTask<WritingStyleDocument> LoadAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult(document);

        public ValueTask SaveAsync(WritingStyleDocument value, CancellationToken cancellationToken)
        {
            document = value;
            return ValueTask.CompletedTask;
        }
    }
}
