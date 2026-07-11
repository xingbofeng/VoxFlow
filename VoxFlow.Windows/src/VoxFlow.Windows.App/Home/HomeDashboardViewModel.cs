using System.ComponentModel;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Output;

namespace VoxFlow.Windows.App.Home;

public sealed class HomeDashboardViewModel : INotifyPropertyChanged
{
    private static readonly IReadOnlyList<HomeTextSourceFilter> AllSourceFilters =
    [
        HomeTextSourceFilter.All,
        HomeTextSourceFilter.Qwen,
        HomeTextSourceFilter.TencentCloud,
        HomeTextSourceFilter.AliyunDashScope,
        HomeTextSourceFilter.Volcengine,
    ];

    private readonly IHistoryStore store;
    private readonly ITextClipboardWriter clipboard;
    private readonly TimeProvider timeProvider;
    private readonly IHistoryReprocessor? reprocessor;
    private readonly int pageSize;
    private readonly HashSet<string> selectedEntryIds = new(StringComparer.Ordinal);
    private IReadOnlyList<HistoryEntry> allTextEntries = [];
    private IReadOnlyList<HomeHistoryItem> visibleEntries = [];
    private IReadOnlyList<HomeActivityWeek> activityWeeks = [];
    private HomeDashboardStatistics statistics = HomeDashboardStatistics.Empty;
    private HomeTextSourceFilter sourceFilter;
    private string searchText = string.Empty;
    private int currentPage = 1;
    private int totalPages = 1;
    private int totalFilteredCount;
    private HistoryDetailViewModel? selectedDetail;
    private bool isReprocessing;

    public HomeDashboardViewModel(
        IHistoryStore store,
        ITextClipboardWriter clipboard,
        TimeProvider timeProvider,
        IHistoryReprocessor? reprocessor = null,
        int pageSize = 20)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        this.reprocessor = reprocessor;
        ArgumentOutOfRangeException.ThrowIfLessThan(pageSize, 1);
        this.pageSize = pageSize;

        SourceFilters = AllSourceFilters;
        SourceFilterOptions =
        [
            new(HomeTextSourceFilter.All, L10n.Localize("HistorySourceAll")),
            new(HomeTextSourceFilter.Qwen, L10n.Localize("HistorySourceQwen")),
            new(HomeTextSourceFilter.TencentCloud, L10n.Localize("HistorySourceTencent")),
            new(HomeTextSourceFilter.AliyunDashScope, L10n.Localize("HistorySourceAliyun")),
            new(HomeTextSourceFilter.Volcengine, L10n.Localize("HistorySourceVolcengine")),
        ];
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<HomeTextSourceFilter> SourceFilters { get; }

    public IReadOnlyList<HomeTextSourceFilterOption> SourceFilterOptions { get; }

    public HomeDashboardStatistics Statistics
    {
        get => statistics;
        private set => SetField(ref statistics, value);
    }

    public IReadOnlyList<HomeActivityWeek> ActivityWeeks
    {
        get => activityWeeks;
        private set => SetField(ref activityWeeks, value);
    }

    public IReadOnlyList<HomeHistoryItem> VisibleEntries
    {
        get => visibleEntries;
        private set => SetField(ref visibleEntries, value);
    }

    public HomeTextSourceFilter SourceFilter
    {
        get => sourceFilter;
        set
        {
            if (!Enum.IsDefined(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value), value, null);
            }

            if (sourceFilter == value)
            {
                return;
            }

            sourceFilter = value;
            OnPropertyChanged();
            currentPage = 1;
            OnPropertyChanged(nameof(CurrentPage));
            ApplyFilterAndPage();
        }
    }

    public string SearchText
    {
        get => searchText;
        set
        {
            ArgumentNullException.ThrowIfNull(value);
            if (searchText == value)
            {
                return;
            }

            searchText = value;
            OnPropertyChanged();
            currentPage = 1;
            OnPropertyChanged(nameof(CurrentPage));
            ApplyFilterAndPage();
        }
    }

    public int CurrentPage
    {
        get => currentPage;
        private set => SetField(ref currentPage, value);
    }

    public int TotalPages
    {
        get => totalPages;
        private set => SetField(ref totalPages, value);
    }

    public int TotalFilteredCount
    {
        get => totalFilteredCount;
        private set => SetField(ref totalFilteredCount, value);
    }

    public bool CanGoPrevious => CurrentPage > 1;

    public bool CanGoNext => CurrentPage < TotalPages;

    public IReadOnlyCollection<string> SelectedEntryIds =>
        selectedEntryIds.Order(StringComparer.Ordinal).ToArray();

    public HistoryDetailViewModel? SelectedDetail
    {
        get => selectedDetail;
        private set => SetField(ref selectedDetail, value);
    }

    public bool CanReprocess => reprocessor is not null;

    public bool IsReprocessing
    {
        get => isReprocessing;
        private set => SetField(ref isReprocessing, value);
    }

    public void Reload()
    {
        allTextEntries = store
            .ReadAll()
            .Where(entry => HomeTextSource.TryClassify(entry, out _))
            .OrderByDescending(entry => entry.CreatedAtUtc)
            .ThenBy(entry => entry.Id, StringComparer.Ordinal)
            .ToArray();

        selectedEntryIds.IntersectWith(
            allTextEntries.Select(entry => entry.Id));
        OnPropertyChanged(nameof(SelectedEntryIds));
        if (SelectedDetail is { } detail)
        {
            var refreshedEntry = FindEntry(detail.Id);
            SelectedDetail = refreshedEntry is null
                ? null
                : new HistoryDetailViewModel(refreshedEntry);
        }

        BuildStatisticsAndActivity();
        ApplyFilterAndPage();
    }

    public void GoToPage(int page)
    {
        var clamped = Math.Clamp(page, 1, TotalPages);
        if (CurrentPage == clamped)
        {
            return;
        }

        CurrentPage = clamped;
        ApplyFilterAndPage();
    }

    public void SetSourceFilter(HomeTextSourceFilter filter) =>
        SourceFilter = filter;

    public bool CopyEntry(string id)
    {
        var entry = FindEntry(id);
        if (entry is null)
        {
            return false;
        }

        clipboard.WriteText(entry.FinalText);
        return true;
    }

    public bool DeleteEntry(string id)
    {
        if (FindEntry(id) is null || store.Delete([id]) != 1)
        {
            return false;
        }

        selectedEntryIds.Remove(id);
        if (SelectedDetail?.Id == id)
        {
            SelectedDetail = null;
        }

        Reload();
        return true;
    }

    public void ToggleSelection(string id)
    {
        if (FindEntry(id) is null)
        {
            return;
        }

        if (!selectedEntryIds.Add(id))
        {
            selectedEntryIds.Remove(id);
        }

        OnPropertyChanged(nameof(SelectedEntryIds));
        ApplyFilterAndPage();
    }

    public int DeleteSelected()
    {
        var ids = selectedEntryIds.ToArray();
        if (ids.Length == 0)
        {
            return 0;
        }

        var deleted = store.Delete(ids);
        selectedEntryIds.Clear();
        if (SelectedDetail is not null && ids.Contains(SelectedDetail.Id, StringComparer.Ordinal))
        {
            SelectedDetail = null;
        }

        Reload();
        return deleted;
    }

    public int ClearAll()
    {
        var deleted = store.Clear();
        selectedEntryIds.Clear();
        SelectedDetail = null;
        CurrentPage = 1;
        Reload();
        return deleted;
    }

    public bool OpenDetail(string id)
    {
        var entry = FindEntry(id);
        if (entry is null)
        {
            return false;
        }

        SelectedDetail = new HistoryDetailViewModel(entry);
        return true;
    }

    public void CloseDetail() => SelectedDetail = null;

    public void CopySelectedDiagnostic()
    {
        if (SelectedDetail is { } detail)
        {
            clipboard.WriteText(detail.SanitizedDiagnostic);
        }
    }

    public bool SaveSelectedEdit()
    {
        if (SelectedDetail is not { } detail
            || string.IsNullOrWhiteSpace(detail.EditedFinalText)
            || !store.UpdateFinalText(detail.Id, detail.EditedFinalText))
        {
            return false;
        }

        detail.ApplyFinalText(detail.EditedFinalText);
        ReplaceCachedFinalText(detail.Id, detail.FinalText);
        BuildStatisticsAndActivity();
        ApplyFilterAndPage();
        return true;
    }

    public async ValueTask<bool> ReprocessSelectedAsync(
        CancellationToken cancellationToken)
    {
        if (SelectedDetail is not { } detail || reprocessor is null || IsReprocessing)
        {
            return false;
        }

        var id = detail.Id;
        var rawText = detail.RawText;
        IsReprocessing = true;
        try
        {
            var result = await reprocessor
                .ReprocessAsync(rawText, cancellationToken)
                .ConfigureAwait(true);
            cancellationToken.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(result)
                || !store.UpdateFinalText(id, result))
            {
                return false;
            }

            ReplaceCachedFinalText(id, result);
            if (SelectedDetail?.Id == id)
            {
                SelectedDetail.ApplyFinalText(result);
            }

            BuildStatisticsAndActivity();
            ApplyFilterAndPage();
            return true;
        }
        finally
        {
            IsReprocessing = false;
        }
    }

    private void BuildStatisticsAndActivity()
    {
        var today = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime.Date);
        Statistics = new HomeDashboardStatistics(
            allTextEntries.Count,
            allTextEntries.Count(entry =>
                DateOnly.FromDateTime(entry.CreatedAtUtc.UtcDateTime.Date) == today),
            allTextEntries.Sum(entry => entry.FinalText.Length),
            allTextEntries.Sum(entry => entry.Metadata.DurationMilliseconds ?? 0));

        var countsByDate = allTextEntries
            .GroupBy(entry => DateOnly.FromDateTime(entry.CreatedAtUtc.UtcDateTime.Date))
            .ToDictionary(group => group.Key, group => group.Count());
        var firstDate = today.AddDays(-363);
        ActivityWeeks = Enumerable
            .Range(0, 52)
            .Select(weekIndex => new HomeActivityWeek(
                Enumerable
                    .Range(0, 7)
                    .Select(dayIndex =>
                    {
                        var date = firstDate.AddDays((weekIndex * 7) + dayIndex);
                        return new HomeActivityDay(
                            date,
                            countsByDate.GetValueOrDefault(date));
                    })
                    .ToArray()))
            .ToArray();
    }

    private void ApplyFilterAndPage()
    {
        var query = allTextEntries.AsEnumerable();
        if (SourceFilter != HomeTextSourceFilter.All)
        {
            query = query.Where(entry =>
                HomeTextSource.TryClassify(entry, out var source)
                && source == SourceFilter);
        }

        var term = SearchText.Trim();
        if (term.Length > 0)
        {
            query = query.Where(entry =>
                entry.RawText.Contains(term, StringComparison.OrdinalIgnoreCase)
                || entry.FinalText.Contains(term, StringComparison.OrdinalIgnoreCase));
        }

        var filtered = query.ToArray();
        TotalFilteredCount = filtered.Length;
        TotalPages = Math.Max(1, (filtered.Length + pageSize - 1) / pageSize);
        CurrentPage = Math.Clamp(CurrentPage, 1, TotalPages);
        VisibleEntries = filtered
            .Skip((CurrentPage - 1) * pageSize)
            .Take(pageSize)
            .Select(entry => new HomeHistoryItem(
                entry,
                selectedEntryIds.Contains(entry.Id)))
            .ToArray();
        OnPropertyChanged(nameof(CanGoPrevious));
        OnPropertyChanged(nameof(CanGoNext));
    }

    private HistoryEntry? FindEntry(string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        return allTextEntries.FirstOrDefault(entry =>
            string.Equals(entry.Id, id, StringComparison.Ordinal));
    }

    private void ReplaceCachedFinalText(string id, string finalText)
    {
        allTextEntries = allTextEntries
            .Select(entry => entry.Id == id
                ? entry with { FinalText = finalText }
                : entry)
            .ToArray();
    }

    private bool SetField<T>(
        ref T field,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
