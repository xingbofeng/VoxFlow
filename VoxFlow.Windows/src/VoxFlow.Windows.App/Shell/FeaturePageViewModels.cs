using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Update;

namespace VoxFlow.Windows.App.Shell;

public sealed class AgentWorkspacePageViewModel : INotifyPropertyChanged
{
    private readonly HomeDashboardViewModel dashboard;
    private IReadOnlyList<HomeHistoryItem> entries = [];

    public AgentWorkspacePageViewModel(HomeDashboardViewModel dashboard)
    {
        this.dashboard = dashboard ?? throw new ArgumentNullException(nameof(dashboard));
        Refresh();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Heading => L10n.Localize("AgentWorkspaceHeading");

    public string Subtitle => L10n.Localize("AgentWorkspaceSubtitle");

    public string RuntimeHeading => L10n.Localize("AgentWorkspaceRuntimeHeading");

    public string RuntimeDescription => L10n.Localize("AgentWorkspaceRuntimeDescription");

    public string HotkeyHeading => L10n.Localize("AgentWorkspaceHotkeyHeading");

    public string HotkeyDescription => L10n.Localize("AgentWorkspaceHotkeyDescription");

    public string HistoryHeading => L10n.Localize("AgentWorkspaceHistoryHeading");

    public string EmptyText => L10n.Localize("AgentWorkspaceEmpty");

    public string RefreshLabel => L10n.Localize("CommonRefresh");

    public string CopyLabel => L10n.Localize("HistoryCopy");

    public IReadOnlyList<HomeHistoryItem> Entries
    {
        get => entries;
        private set
        {
            entries = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsEmpty));
        }
    }

    public bool IsEmpty => Entries.Count == 0;

    public void Refresh()
    {
        dashboard.Reload();
        Entries = dashboard.AllEntries
            .Where(static item => item.Kind == UnifiedHistoryKind.AgentCompose)
            .OrderByDescending(static item => item.CreatedAtUtc)
            .ToArray();
    }

    public bool Copy(string id)
    {
        var entry = Entries.FirstOrDefault(item => item.Id == id);
        if (entry is null || string.IsNullOrWhiteSpace(entry.FinalText))
        {
            return false;
        }
        System.Windows.Clipboard.SetText(entry.FinalText);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class NotesPageViewModel : INotifyPropertyChanged
{
    private readonly HomeDashboardViewModel dashboard;
    private string searchText = string.Empty;
    private IReadOnlyList<HomeHistoryItem> entries = [];

    public NotesPageViewModel(HomeDashboardViewModel dashboard)
    {
        this.dashboard = dashboard ?? throw new ArgumentNullException(nameof(dashboard));
        Refresh();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Heading => L10n.Localize("NotesHeading");

    public string Subtitle => L10n.Localize("NotesHistoryOnlySubtitle");

    public string SearchPlaceholder => L10n.Localize("NotesSearchPlaceholder");

    public string EmptyText => L10n.Localize("NotesEmpty");

    public string RefreshLabel => L10n.Localize("CommonRefresh");

    public string CopyLabel => L10n.Localize("HistoryCopy");

    public string SearchText
    {
        get => searchText;
        set
        {
            if (searchText == value)
            {
                return;
            }
            searchText = value ?? string.Empty;
            OnPropertyChanged();
            Rebuild();
        }
    }

    public IReadOnlyList<HomeHistoryItem> Entries
    {
        get => entries;
        private set
        {
            entries = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsEmpty));
        }
    }

    public bool IsEmpty => Entries.Count == 0;

    public void Refresh()
    {
        dashboard.Reload();
        Rebuild();
    }

    public bool Copy(string id)
    {
        var entry = dashboard.AllEntries.FirstOrDefault(item => item.Id == id);
        if (entry is null || string.IsNullOrWhiteSpace(entry.FinalText))
        {
            return false;
        }
        System.Windows.Clipboard.SetText(entry.FinalText);
        return true;
    }

    private void Rebuild()
    {
        var query = SearchText.Trim();
        Entries = dashboard.AllEntries
            .Where(static item => !string.IsNullOrWhiteSpace(item.FinalText))
            .Where(item => query.Length == 0
                || item.DisplayTitle.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                || item.FinalText.Contains(query, StringComparison.CurrentCultureIgnoreCase))
            .OrderByDescending(static item => item.CreatedAtUtc)
            .ToArray();
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed record HelpFeatureCardViewModel(
    string Glyph,
    string Heading,
    string Description);

public sealed record HelpLinkViewModel(
    string Glyph,
    string Heading,
    string Description,
    string Url,
    bool IsUpdateAction = false);

public sealed class HelpPageViewModel : INotifyPropertyChanged
{
    private readonly IAppUpdateChecker updateChecker;
    private string updateStatusMessage = string.Empty;
    private bool isCheckingUpdate;
    private string? lastReleaseUrl;
    private bool updateAvailable;

    public HelpPageViewModel(IAppUpdateChecker? updateChecker = null)
    {
        this.updateChecker = updateChecker ?? AppUpdateChecker.CreateHttp();
        FeatureCards =
        [
            Card("\uE765", "HelpFeatureDictationHeading", "HelpFeatureDictationDescription"),
            Card("\uE91B", "HelpFeatureScreenshotHeading", "HelpFeatureScreenshotDescription"),
            Card("\uE950", "HelpFeatureAgentHeading", "HelpFeatureAgentDescription"),
            Card("\uE70B", "HelpFeatureNotesHeading", "HelpFeatureNotesDescription"),
            Card("\uE8D2", "HelpFeatureGlossaryHeading", "HelpFeatureGlossaryDescription"),
            Card("\uE777", "HelpFeatureFallbackHeading", "HelpFeatureFallbackDescription"),
            Card("\uE72E", "HelpFeaturePrivacyHeading", "HelpFeaturePrivacyDescription"),
        ];
        Links =
        [
            Link("\uE80F", "HelpLinkProjectHeading", "HelpLinkProjectDescription", "https://github.com/xingbofeng/VoxFlow"),
            Link("\uE943", "HelpLinkGithubHeading", "HelpLinkGithubDescription", "https://github.com/xingbofeng/VoxFlow"),
            Link("\uE734", "HelpLinkCommunityHeading", "HelpLinkCommunityDescription", "https://github.com/xingbofeng/VoxFlow/issues"),
            new(
                "\uE895",
                L10n.Localize("HelpLinkUpdateHeading"),
                L10n.Localize("HelpLinkUpdateDescription"),
                AppUpdateChecker.DefaultReleasePage,
                IsUpdateAction: true),
            Link("\uE7B8", "HelpLinkChangelogHeading", "HelpLinkChangelogDescription", "https://github.com/xingbofeng/VoxFlow/releases"),
        ];
        updateStatusMessage = L10n.Localize("HelpUpdateIdle");
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Heading => L10n.Localize("HelpHeading");

    public string Subtitle => L10n.Localize("HelpSubtitle");

    public string LinksHeading => L10n.Localize("HelpLinksHeading");

    public string Version => $"v{CurrentVersionCore}";

    public string CurrentVersionCore =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";

    public IReadOnlyList<HelpFeatureCardViewModel> FeatureCards { get; }

    public IReadOnlyList<HelpLinkViewModel> Links { get; }

    public string UpdateStatusMessage
    {
        get => updateStatusMessage;
        private set
        {
            if (updateStatusMessage == value)
            {
                return;
            }

            updateStatusMessage = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasUpdateStatus));
        }
    }

    public bool HasUpdateStatus => !string.IsNullOrWhiteSpace(updateStatusMessage);

    public bool IsCheckingUpdate
    {
        get => isCheckingUpdate;
        private set
        {
            if (isCheckingUpdate == value)
            {
                return;
            }

            isCheckingUpdate = value;
            OnPropertyChanged();
        }
    }

    public bool UpdateAvailable
    {
        get => updateAvailable;
        private set
        {
            if (updateAvailable == value)
            {
                return;
            }

            updateAvailable = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanOpenReleasePage));
        }
    }

    public string? LastReleaseUrl
    {
        get => lastReleaseUrl;
        private set
        {
            lastReleaseUrl = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanOpenReleasePage));
        }
    }

    public bool CanOpenReleasePage =>
        UpdateAvailable
        && !string.IsNullOrWhiteSpace(LastReleaseUrl)
        && Uri.TryCreate(LastReleaseUrl, UriKind.Absolute, out _);

    public async Task<AppUpdateCheckResult> CheckForUpdatesAsync(
        CancellationToken cancellationToken = default)
    {
        IsCheckingUpdate = true;
        try
        {
            var result = await updateChecker
                .CheckAsync(CurrentVersionCore, cancellationToken)
                .ConfigureAwait(true);
            LastReleaseUrl = result.ReleaseUrl;
            UpdateAvailable = result.Availability == AppUpdateAvailability.UpdateAvailable;
            UpdateStatusMessage = result.Availability switch
            {
                AppUpdateAvailability.UpdateAvailable => string.Format(
                    System.Globalization.CultureInfo.CurrentUICulture,
                    L10n.Localize("HelpUpdateAvailable"),
                    result.LatestVersion ?? string.Empty),
                AppUpdateAvailability.UpToDate => string.Format(
                    System.Globalization.CultureInfo.CurrentUICulture,
                    L10n.Localize("HelpUpdateUpToDate"),
                    result.LatestVersion ?? result.CurrentVersion),
                _ => L10n.Localize("HelpUpdateFailed"),
            };
            return result;
        }
        finally
        {
            IsCheckingUpdate = false;
        }
    }

    private static HelpFeatureCardViewModel Card(string glyph, string heading, string description) =>
        new(glyph, L10n.Localize(heading), L10n.Localize(description));

    private static HelpLinkViewModel Link(string glyph, string heading, string description, string url) =>
        new(glyph, L10n.Localize(heading), L10n.Localize(description), url);

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
