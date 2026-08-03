using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Home;

public sealed class HomeDashboardViewModel : INotifyPropertyChanged
{
    private static readonly IReadOnlyList<HomeTextSourceFilter> AllSourceFilters =
    [
        HomeTextSourceFilter.All,
        HomeTextSourceFilter.Dictation,
        HomeTextSourceFilter.Screenshot,
        HomeTextSourceFilter.Qwen,
        HomeTextSourceFilter.TencentCloud,
        HomeTextSourceFilter.AliyunDashScope,
        HomeTextSourceFilter.Volcengine,
        HomeTextSourceFilter.SelectionTranslation,
        HomeTextSourceFilter.SelectionSummary,
        HomeTextSourceFilter.AgentCompose,
        HomeTextSourceFilter.FileTranscription,
    ];

    private readonly IHistoryStore store;
    private readonly ITextClipboardWriter clipboard;
    private readonly TimeProvider timeProvider;
    private readonly IHistoryReprocessor? reprocessor;
    private readonly IUnifiedHistoryService unifiedHistory;
    private readonly IScreenshotAssetStore? screenshotAssets;
    private readonly int pageSize;
    private readonly HashSet<string> selectedEntryIds = new(StringComparer.Ordinal);
    private IReadOnlyList<HistoryEntry> allTextEntries = [];
    private IReadOnlyList<UnifiedHistoryEntry> allEntries = [];
    private IReadOnlyList<HomeHistoryItem> visibleEntries = [];
    private IReadOnlyList<HomeActivityWeek> activityWeeks = [];
    private HomeDashboardStatistics statistics = HomeDashboardStatistics.Empty;
    private HomeTextSourceFilter sourceFilter;
    private string searchText = string.Empty;
    private int currentPage = 1;
    private int totalPages = 1;
    private int totalFilteredCount;
    private IHomeHistoryDetail? selectedDetail;
    private bool isReprocessing;
    private string? actionFeedback;

    public HomeDashboardViewModel(
        IHistoryStore store,
        ITextClipboardWriter clipboard,
        TimeProvider timeProvider,
        IHistoryReprocessor? reprocessor = null,
        int pageSize = 20,
        IUnifiedHistoryService? unifiedHistory = null,
        IScreenshotAssetStore? screenshotAssets = null)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        this.reprocessor = reprocessor;
        this.unifiedHistory = unifiedHistory ?? new UnifiedHistoryQueryService(store);
        this.screenshotAssets = screenshotAssets;
        ArgumentOutOfRangeException.ThrowIfLessThan(pageSize, 1);
        this.pageSize = pageSize;

        SourceFilters = AllSourceFilters;
        var weekdayNames = CultureInfo.CurrentCulture.DateTimeFormat.AbbreviatedDayNames;
        ActivityWeekdayLabels =
        [
            weekdayNames[(int)DayOfWeek.Monday],
            weekdayNames[(int)DayOfWeek.Tuesday],
            weekdayNames[(int)DayOfWeek.Wednesday],
            weekdayNames[(int)DayOfWeek.Thursday],
            weekdayNames[(int)DayOfWeek.Friday],
            weekdayNames[(int)DayOfWeek.Saturday],
            weekdayNames[(int)DayOfWeek.Sunday],
        ];
        SourceFilterOptions =
        [
            new(HomeTextSourceFilter.All, L10n.Localize("HistorySourceAll")),
            new(HomeTextSourceFilter.Dictation, L10n.Localize("HistorySourceDictation")),
            new(HomeTextSourceFilter.Screenshot, L10n.Localize("HistorySourceScreenshot")),
            new(HomeTextSourceFilter.Qwen, L10n.Localize("HistorySourceQwen")),
            new(HomeTextSourceFilter.TencentCloud, L10n.Localize("HistorySourceTencent")),
            new(HomeTextSourceFilter.AliyunDashScope, L10n.Localize("HistorySourceAliyun")),
            new(HomeTextSourceFilter.Volcengine, L10n.Localize("HistorySourceVolcengine")),
            new(HomeTextSourceFilter.SelectionTranslation, L10n.Localize("HistorySourceSelectionTranslation")),
            new(HomeTextSourceFilter.SelectionSummary, L10n.Localize("HistorySourceSelectionSummary")),
            new(HomeTextSourceFilter.AgentCompose, L10n.Localize("HistorySourceAgentCompose")),
            new(HomeTextSourceFilter.FileTranscription, L10n.Localize("HistorySourceFileTranscription")),
        ];
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<HomeTextSourceFilter> SourceFilters { get; }

    public IReadOnlyList<HomeTextSourceFilterOption> SourceFilterOptions { get; }

    public IReadOnlyList<string> ActivityWeekdayLabels { get; }

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

    public IReadOnlyList<HomeHistoryItem> AllEntries => allEntries
        .Select(entry => new HomeHistoryItem(entry, selectedEntryIds.Contains(entry.Id)))
        .ToArray();

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
        private set
        {
            if (SetField(ref totalFilteredCount, value))
            {
                OnPropertyChanged(nameof(HistoryCountLabel));
            }
        }
    }

    public string HistoryCountLabel => string.Format(
        CultureInfo.CurrentCulture,
        L10n.Localize("HistoryCountFormat"),
        TotalFilteredCount);

    public string ActivityThisWeekLabel => string.Format(
        CultureInfo.CurrentCulture,
        L10n.Localize("HomeActivityThisWeekFormat"),
        ActivityWeeks.LastOrDefault()?.Days.Sum(day => day.Count) ?? 0);

    public bool CanGoPrevious => CurrentPage > 1;

    public bool CanGoNext => CurrentPage < TotalPages;

    public IReadOnlyCollection<string> SelectedEntryIds =>
        selectedEntryIds.Order(StringComparer.Ordinal).ToArray();

    public IHomeHistoryDetail? SelectedDetail
    {
        get => selectedDetail;
        private set
        {
            if (ReferenceEquals(selectedDetail, value))
            {
                return;
            }
            if (selectedDetail is INotifyPropertyChanged previous)
            {
                previous.PropertyChanged -= OnSelectedDetailPropertyChanged;
            }
            selectedDetail = value;
            if (selectedDetail is INotifyPropertyChanged current)
            {
                current.PropertyChanged += OnSelectedDetailPropertyChanged;
            }
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsDetailOpen));
            NotifyDetailActionAvailabilityChanged();
        }
    }

    /// <summary>
    /// True while a Mac-style detail modal should cover the dashboard.
    /// </summary>
    public bool IsDetailOpen => SelectedDetail is not null;

    public bool CanReprocess => reprocessor is not null;

    public bool CanDeleteSelected => selectedEntryIds.Count > 0;

    public bool CanClearAll => allEntries.Count > 0;

    public bool CanSaveSelectedEdit =>
        SelectedDetail is HistoryDetailViewModel detail
        && !string.IsNullOrWhiteSpace(detail.EditedFinalText)
        && !IsReprocessing;

    public bool CanReprocessSelected =>
        CanReprocess
        && SelectedDetail is HistoryDetailViewModel
        && !IsReprocessing;

    public string DeleteSelectedUnavailableReason =>
        L10n.Localize("HistoryDeleteSelectedUnavailable");

    public string ClearAllUnavailableReason =>
        L10n.Localize("HistoryClearAllUnavailable");

    public string SaveUnavailableReason =>
        L10n.Localize("HistorySaveUnavailable");

    public string ReprocessUnavailableReason =>
        L10n.Localize("HistoryReprocessUnavailable");

    public string? ActionFeedback
    {
        get => actionFeedback;
        private set => SetField(ref actionFeedback, value);
    }

    public bool IsReprocessing
    {
        get => isReprocessing;
        private set
        {
            if (SetField(ref isReprocessing, value))
            {
                OnPropertyChanged(nameof(CanSaveSelectedEdit));
                OnPropertyChanged(nameof(CanReprocessSelected));
            }
        }
    }

    public void Reload()
    {
        // macOS home shows every asset (dictation/screenshot/workflow); do not drop
        // unconfigured ASR rows or require provider classification.
        allTextEntries = store
            .ReadAll()
            .OrderByDescending(entry => entry.CreatedAtUtc)
            .ThenBy(entry => entry.Id, StringComparer.Ordinal)
            .ToArray();
        allEntries = unifiedHistory.ReadAll()
            .OrderByDescending(entry => entry.CreatedAtUtc)
            .ThenBy(entry => entry.Id, StringComparer.Ordinal)
            .ToArray();

        selectedEntryIds.IntersectWith(
            allEntries.Select(entry => entry.Id));
        OnPropertyChanged(nameof(SelectedEntryIds));
        if (SelectedDetail is { } detail)
        {
            SelectedDetail = CreateDetail(FindUnifiedEntry(detail.Id));
        }

        BuildStatisticsAndActivity();
        ApplyFilterAndPage();
        NotifyCollectionActionAvailabilityChanged();
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
        try
        {
            var entry = FindUnifiedEntry(id);
            if (entry is null)
            {
                SetActionFeedback("HistoryCopyFailed");
                return false;
            }

            clipboard.WriteText(entry.CopyText);
            SetActionFeedback("HistoryCopySucceeded");
            return true;
        }
        catch
        {
            SetActionFeedback("HistoryCopyFailed");
            return false;
        }
    }

    public bool DeleteEntry(string id)
    {
        try
        {
            if (FindUnifiedEntry(id) is null || unifiedHistory.Delete([id]) != 1)
            {
                SetActionFeedback("HistoryDeleteFailed");
                return false;
            }

            selectedEntryIds.Remove(id);
            if (SelectedDetail?.Id == id)
            {
                SelectedDetail = null;
            }

            Reload();
            SetActionFeedback("HistoryDeleteSucceeded");
            return true;
        }
        catch
        {
            SetActionFeedback("HistoryDeleteFailed");
            return false;
        }
    }

    public void ToggleSelection(string id)
    {
        if (FindUnifiedEntry(id) is null)
        {
            return;
        }

        if (!selectedEntryIds.Add(id))
        {
            selectedEntryIds.Remove(id);
        }

        OnPropertyChanged(nameof(SelectedEntryIds));
        OnPropertyChanged(nameof(CanDeleteSelected));
        ApplyFilterAndPage();
    }

    public void SelectAllVisible()
    {
        foreach (var entry in VisibleEntries)
        {
            selectedEntryIds.Add(entry.Id);
        }

        OnPropertyChanged(nameof(SelectedEntryIds));
        OnPropertyChanged(nameof(CanDeleteSelected));
        ApplyFilterAndPage();
    }

    public int DeleteSelected()
    {
        var ids = selectedEntryIds.ToArray();
        if (ids.Length == 0)
        {
            return 0;
        }

        try
        {
            var deleted = unifiedHistory.Delete(ids);
            selectedEntryIds.Clear();
            if (SelectedDetail is not null
                && ids.Contains(SelectedDetail.Id, StringComparer.Ordinal))
            {
                SelectedDetail = null;
            }

            Reload();
            SetActionFeedback(deleted > 0
                ? "HistoryDeleteSucceeded"
                : "HistoryDeleteFailed");
            return deleted;
        }
        catch
        {
            SetActionFeedback("HistoryDeleteFailed");
            return 0;
        }
    }

    public int ClearAll()
    {
        if (!CanClearAll)
        {
            return 0;
        }
        try
        {
            var deleted = unifiedHistory.Clear();
            selectedEntryIds.Clear();
            SelectedDetail = null;
            CurrentPage = 1;
            Reload();
            SetActionFeedback(deleted > 0
                ? "HistoryDeleteSucceeded"
                : "HistoryDeleteFailed");
            return deleted;
        }
        catch
        {
            SetActionFeedback("HistoryDeleteFailed");
            return 0;
        }
    }

    public bool OpenDetail(string id)
    {
        var detail = CreateDetail(FindUnifiedEntry(id));
        if (detail is null)
        {
            return false;
        }

        SelectedDetail = detail;
        return true;
    }

    public void CloseDetail() => SelectedDetail = null;

    public bool CopySelectedDiagnostic()
    {
        try
        {
            if (SelectedDetail is not { } detail)
            {
                SetActionFeedback("HistoryCopyFailed");
                return false;
            }
            clipboard.WriteText(detail.SanitizedDiagnostic);
            SetActionFeedback("HistoryCopySucceeded");
            return true;
        }
        catch
        {
            SetActionFeedback("HistoryCopyFailed");
            return false;
        }
    }

    public bool SaveSelectedEdit()
    {
        try
        {
            if (SelectedDetail is not HistoryDetailViewModel detail
                || string.IsNullOrWhiteSpace(detail.EditedFinalText)
                || !store.UpdateFinalText(detail.Id, detail.EditedFinalText))
            {
                SetActionFeedback("HistorySaveFailed");
                return false;
            }

            detail.ApplyFinalText(detail.EditedFinalText);
            Reload();
            SetActionFeedback("HistorySaveSucceeded");
            return true;
        }
        catch
        {
            SetActionFeedback("HistorySaveFailed");
            return false;
        }
    }

    public async ValueTask<bool> ReprocessSelectedAsync(
        CancellationToken cancellationToken)
    {
        if (SelectedDetail is not HistoryDetailViewModel detail
            || reprocessor is null
            || IsReprocessing)
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
                SetActionFeedback("HistoryReprocessFailed");
                return false;
            }

            Reload();
            SetActionFeedback("HistoryReprocessSucceeded");
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            SetActionFeedback("HistoryReprocessFailed");
            return false;
        }
        finally
        {
            IsReprocessing = false;
        }
    }

    public void ReportActionFailure() =>
        SetActionFeedback("HistoryActionFailed");

    private void OnSelectedDetailPropertyChanged(
        object? sender,
        PropertyChangedEventArgs eventArgs)
    {
        if (eventArgs.PropertyName == nameof(IHomeHistoryDetail.EditedFinalText))
        {
            OnPropertyChanged(nameof(CanSaveSelectedEdit));
        }
    }

    private void NotifyDetailActionAvailabilityChanged()
    {
        OnPropertyChanged(nameof(CanSaveSelectedEdit));
        OnPropertyChanged(nameof(CanReprocessSelected));
    }

    private void NotifyCollectionActionAvailabilityChanged()
    {
        OnPropertyChanged(nameof(CanDeleteSelected));
        OnPropertyChanged(nameof(CanClearAll));
    }

    private void SetActionFeedback(string key) =>
        ActionFeedback = L10n.Localize(key);

    private void BuildStatisticsAndActivity()
    {
        var today = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime.Date);
        var dictationCount = allEntries.Count(entry =>
            entry.Kind == UnifiedHistoryKind.Dictation);
        var screenshotCount = allEntries.Count(entry =>
            entry.Kind == UnifiedHistoryKind.Screenshot);
        var clipboardCount = allEntries.Count(entry =>
            entry.Kind is UnifiedHistoryKind.SelectionTranslation
                or UnifiedHistoryKind.SelectionSummary);
        var reusableCount = allEntries.Count(entry =>
            !string.IsNullOrWhiteSpace(entry.CopyText));
        Statistics = new HomeDashboardStatistics(
            allEntries.Count,
            allEntries.Count(entry =>
                DateOnly.FromDateTime(entry.CreatedAtUtc.UtcDateTime.Date) == today),
            dictationCount,
            screenshotCount,
            clipboardCount,
            reusableCount);

        // Activity heatmap counts all home assets (macOS HomeActivityDay.assetCount).
        var countsByDate = allEntries
            .GroupBy(entry => DateOnly.FromDateTime(entry.CreatedAtUtc.UtcDateTime.Date))
            .ToDictionary(group => group.Key, group => group.Count());
        var mondayOffset = ((int)today.DayOfWeek + 6) % 7;
        var currentWeekMonday = today.AddDays(-mondayOffset);
        var firstDate = currentWeekMonday.AddDays(-51 * 7);
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
        OnPropertyChanged(nameof(ActivityThisWeekLabel));
    }

    private void ApplyFilterAndPage()
    {
        var query = allEntries.AsEnumerable();
        if (SourceFilter != HomeTextSourceFilter.All)
        {
            query = query.Where(entry => MatchesSourceFilter(entry, SourceFilter));
        }

        var term = SearchText.Trim();
        if (term.Length > 0)
        {
            query = query.Where(entry =>
                entry.Matches(term));
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

    private UnifiedHistoryEntry? FindUnifiedEntry(string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        return allEntries.FirstOrDefault(entry =>
            string.Equals(entry.Id, id, StringComparison.Ordinal));
    }

    private IHomeHistoryDetail? CreateDetail(UnifiedHistoryEntry? entry) =>
        entry switch
        {
            { DictationEntry: { } dictation } => new HistoryDetailViewModel(dictation),
            { WorkflowTask: not null } => new WorkflowHistoryDetailViewModel(entry),
            { Kind: UnifiedHistoryKind.Screenshot, ScreenshotRecord: not null } =>
                new ScreenshotHistoryDetailViewModel(entry, screenshotAssets),
            { FileTranscriptionJob: not null } => new GenericAssetHistoryDetailViewModel(entry),
            not null => new GenericAssetHistoryDetailViewModel(entry),
            _ => null,
        };

    private static bool MatchesSourceFilter(
        UnifiedHistoryEntry entry,
        HomeTextSourceFilter filter) => filter switch
    {
        HomeTextSourceFilter.All => true,
        HomeTextSourceFilter.Dictation =>
            entry.Kind == UnifiedHistoryKind.Dictation,
        HomeTextSourceFilter.Screenshot =>
            entry.Kind == UnifiedHistoryKind.Screenshot,
        HomeTextSourceFilter.Qwen
            or HomeTextSourceFilter.TencentCloud
            or HomeTextSourceFilter.AliyunDashScope
            or HomeTextSourceFilter.Volcengine =>
            entry.DictationEntry is { } dictation
            && HomeTextSource.TryClassify(dictation, out var source)
            && source == filter,
        HomeTextSourceFilter.SelectionTranslation =>
            entry.Kind == UnifiedHistoryKind.SelectionTranslation,
        HomeTextSourceFilter.SelectionSummary =>
            entry.Kind == UnifiedHistoryKind.SelectionSummary,
        HomeTextSourceFilter.AgentCompose =>
            entry.Kind == UnifiedHistoryKind.AgentCompose,
        HomeTextSourceFilter.FileTranscription =>
            entry.Kind == UnifiedHistoryKind.FileTranscription,
        _ => false,
    };

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
