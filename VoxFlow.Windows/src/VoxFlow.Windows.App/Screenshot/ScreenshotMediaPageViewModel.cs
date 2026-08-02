using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotMediaFilter
{
    All,
    Screenshots,
    Favorites,
}

public sealed record ScreenshotMediaFilterOption(
    ScreenshotMediaFilter Value,
    string Label);

public sealed record ScreenshotMediaRowViewModel(
    IReadOnlyList<ScreenshotMediaCardViewModel> Cards);

public sealed class ScreenshotMediaCardViewModel
{
    internal ScreenshotMediaCardViewModel(
        ScreenshotRecord record,
        string originalAbsolutePath,
        string canonicalImageAbsolutePath,
        BitmapSource? thumbnail,
        ScreenshotAssetAvailability imageAvailability,
        string createdAtText,
        string resolutionText,
        string textPreview,
        string accessibleName,
        string assetStatusText)
    {
        Record = record ?? throw new ArgumentNullException(nameof(record));
        OriginalAbsolutePath = originalAbsolutePath;
        CanonicalImageAbsolutePath = canonicalImageAbsolutePath;
        Thumbnail = thumbnail;
        ImageAvailability = imageAvailability;
        CreatedAtText = createdAtText;
        ResolutionText = resolutionText;
        TextPreview = textPreview;
        AccessibleName = accessibleName;
        AssetStatusText = assetStatusText;
    }

    public ScreenshotMediaCardViewModel()
    {
        Record = null!;
        OriginalAbsolutePath = string.Empty;
        CanonicalImageAbsolutePath = string.Empty;
        CreatedAtText = string.Empty;
        ResolutionText = string.Empty;
        TextPreview = string.Empty;
        AccessibleName = string.Empty;
        AssetStatusText = string.Empty;
    }

    internal ScreenshotRecord Record { get; init; }

    internal string OriginalAbsolutePath { get; init; }

    internal string CanonicalImageAbsolutePath { get; init; }

    public string Id { get; init; } = string.Empty;

    public BitmapSource? Thumbnail { get; init; }

    public ScreenshotAssetAvailability ImageAvailability { get; init; } =
        ScreenshotAssetAvailability.Missing;

    public bool IsImageMissing => Thumbnail is null;

    public bool CanCopyImage =>
        ImageAvailability == ScreenshotAssetAvailability.Available;

    public string CreatedAtText { get; init; }

    public string ResolutionText { get; init; }

    public string TextPreview { get; init; }

    public string AccessibleName { get; init; }

    public string AssetStatusText { get; init; }

    public bool IsFavorite { get; init; }

    public string FavoriteGlyph => IsFavorite ? "\uE735" : "\uE734";

    public string FavoriteStatusText => IsFavorite
        ? L10n.ScreenshotFavorited
        : L10n.ScreenshotNotFavorited;

    public string AutomationId => $"screenshot-card-{Id}";

    public string CopyImageAutomationId => $"screenshot-card-{Id}-copy-image";

    public string CopyTextAutomationId => $"screenshot-card-{Id}-copy-text";

    public string FavoriteAutomationId => $"screenshot-card-{Id}-favorite";

    public string DeleteAutomationId => $"screenshot-card-{Id}-delete";
}

public sealed class ScreenshotMediaPageViewModel : INotifyPropertyChanged
{
    private readonly ObservableCollection<ScreenshotMediaRowViewModel> rows = [];
    private readonly List<ScreenshotMediaCardViewModel> pageCards = [];
    private readonly List<WeakReference<ScreenshotDetailViewModel>> openDetails = [];
    private readonly object refreshSynchronization = new();
    private readonly IScreenshotRecordRepository? records;
    private readonly IScreenshotAssetStore? assets;
    private readonly IScreenshotMediaPlatform? platform;
    private readonly TimeProvider timeProvider;
    private readonly TimeZoneInfo displayTimeZone;
    private readonly IScreenshotTransformCacheInvalidator? transformCacheInvalidator;
    private string searchText = string.Empty;
    private ScreenshotMediaFilterOption selectedFilter;
    private int pageSize = 20;
    private int page = 1;
    private int totalCount;
    private int todayCount;
    private int favoriteCount;
    private int allMediaCount;
    private int allTodayMediaCount;
    private int screenshotCount;
    private int columnCount = 3;
    private bool isLoading;
    private string? errorMessage;
    private string? statusMessage;
    private CancellationTokenSource? activeRefreshCancellation;
    private long refreshGeneration;

    public ScreenshotMediaPageViewModel(string heading, string subtitle)
        : this(
            heading,
            subtitle,
            records: null,
            assets: null,
            platform: null,
            TimeProvider.System,
            TimeZoneInfo.Local,
            transformCacheInvalidator: null,
            presentationOnly: true)
    {
    }

    public ScreenshotMediaPageViewModel(
        string heading,
        string subtitle,
        IScreenshotRecordRepository records,
        IScreenshotAssetStore assets,
        IScreenshotMediaPlatform? platform = null,
        TimeProvider? timeProvider = null,
        TimeZoneInfo? displayTimeZone = null,
        IScreenshotTransformCacheInvalidator? transformCacheInvalidator = null)
        : this(
            heading,
            subtitle,
            records ?? throw new ArgumentNullException(nameof(records)),
            assets ?? throw new ArgumentNullException(nameof(assets)),
            platform ?? new WpfScreenshotMediaPlatform(),
            timeProvider ?? TimeProvider.System,
            displayTimeZone ?? TimeZoneInfo.Local,
            transformCacheInvalidator,
            presentationOnly: false)
    {
    }

    private ScreenshotMediaPageViewModel(
        string heading,
        string subtitle,
        IScreenshotRecordRepository? records,
        IScreenshotAssetStore? assets,
        IScreenshotMediaPlatform? platform,
        TimeProvider timeProvider,
        TimeZoneInfo displayTimeZone,
        IScreenshotTransformCacheInvalidator? transformCacheInvalidator,
        bool presentationOnly)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(heading);
        ArgumentException.ThrowIfNullOrWhiteSpace(subtitle);
        Heading = heading;
        Subtitle = subtitle;
        this.records = records;
        this.assets = assets;
        this.platform = platform;
        this.timeProvider = timeProvider;
        this.displayTimeZone = displayTimeZone;
        this.transformCacheInvalidator = transformCacheInvalidator;
        _ = presentationOnly;
        FilterOptions =
        [
            new ScreenshotMediaFilterOption(
                ScreenshotMediaFilter.All,
                L10n.Localize("ScreenshotFilterAll")),
            new ScreenshotMediaFilterOption(
                ScreenshotMediaFilter.Screenshots,
                L10n.Localize("ScreenshotFilterScreenshots")),
            new ScreenshotMediaFilterOption(
                ScreenshotMediaFilter.Favorites,
                L10n.Localize("ScreenshotFilterFavorites")),
        ];
        selectedFilter = FilterOptions[0];
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler<ScreenshotMediaCardViewModel>? DetailsRequested;

    public event EventHandler<(ScreenshotMediaCardViewModel Card, string Action)>?
        CardActionRequested;

    public event EventHandler<string>? ReprocessRequested;

    public event EventHandler? StartScreenshotRequested;

    public string Heading { get; }

    public string Subtitle { get; }

    public IReadOnlyList<ScreenshotMediaFilterOption> FilterOptions { get; }

    public IReadOnlyList<int> PageSizeOptions { get; } = [20, 50, 100];

    public IReadOnlyList<ScreenshotMediaRowViewModel> Rows => rows;

    public int TotalCount
    {
        get => totalCount;
        private set => SetField(ref totalCount, value);
    }

    public int TodayCount
    {
        get => todayCount;
        private set => SetField(ref todayCount, value);
    }

    public int FavoriteCount
    {
        get => favoriteCount;
        private set => SetField(ref favoriteCount, value);
    }

    public int AllMediaCount
    {
        get => allMediaCount;
        private set => SetField(ref allMediaCount, value);
    }

    public int AllTodayMediaCount
    {
        get => allTodayMediaCount;
        private set => SetField(ref allTodayMediaCount, value);
    }

    public int ScreenshotCount
    {
        get => screenshotCount;
        private set => SetField(ref screenshotCount, value);
    }

    public bool HasRecords => rows.Count > 0;

    public bool IsEmpty => !IsLoading && !HasError && !HasRecords;

    public bool HasQuery =>
        !string.IsNullOrWhiteSpace(SearchText)
        || SelectedFilter.Value == ScreenshotMediaFilter.Favorites;

    public string EmptyTitle => HasQuery
            ? L10n.Localize("ScreenshotMediaNoResultsTitle")
            : L10n.ScreenshotMediaEmptyTitle;

    public string EmptyHint => HasQuery
            ? L10n.Localize("ScreenshotMediaNoResultsHint")
            : L10n.ScreenshotMediaEmptyHint;

    public string SearchText
    {
        get => searchText;
        set
        {
            if (SetField(ref searchText, value ?? string.Empty))
            {
                ResetPageForQueryChange();
            }
        }
    }

    public ScreenshotMediaFilterOption SelectedFilter
    {
        get => selectedFilter;
        set
        {
            ArgumentNullException.ThrowIfNull(value);
            if (!FilterOptions.Contains(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }
            if (SetField(ref selectedFilter, value))
            {
                ResetPageForQueryChange();
            }
        }
    }

    public int PageSize
    {
        get => pageSize;
        set
        {
            if (!PageSizeOptions.Contains(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }
            if (SetField(ref pageSize, value))
            {
                page = 1;
                InvalidateActiveRefresh();
                NotifyPaginationChanged();
            }
        }
    }

    public int PageNumber => page;

    public int PageCount => Math.Max(1, (TotalCount + PageSize - 1) / PageSize);

    public string PageSummary => TotalCount == 0
        ? "0"
        : Format(
            "ScreenshotMediaPageSummaryFormat",
            ((page - 1) * PageSize) + 1,
            Math.Min(page * PageSize, TotalCount),
            TotalCount);

    public bool CanGoPrevious => page > 1;

    public bool CanGoNext => page < PageCount && TotalCount > 0;

    public int ColumnCount
    {
        get => columnCount;
        private set => SetField(ref columnCount, value);
    }

    public bool IsLoading
    {
        get => isLoading;
        private set
        {
            if (SetField(ref isLoading, value))
            {
                OnPropertyChanged(nameof(IsEmpty));
            }
        }
    }

    public bool HasError => !string.IsNullOrWhiteSpace(ErrorMessage);

    public string? ErrorMessage
    {
        get => errorMessage;
        private set
        {
            if (SetField(ref errorMessage, value))
            {
                OnPropertyChanged(nameof(HasError));
                OnPropertyChanged(nameof(IsEmpty));
            }
        }
    }

    public string? StatusMessage
    {
        get => statusMessage;
        private set => SetField(ref statusMessage, value);
    }

    public void RequestStartScreenshot() =>
        StartScreenshotRequested?.Invoke(this, EventArgs.Empty);

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (records is null || assets is null || platform is null)
        {
            return;
        }

        var operation = BeginRefresh(cancellationToken);
        var request = CreateRefreshRequest();
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var result = await Task.Run(
                () => LoadRefreshResult(request, operation.Cancellation.Token),
                operation.Cancellation.Token).ConfigureAwait(true);
            if (!IsCurrentRefresh(operation))
            {
                return;
            }

            page = result.PageNumber;
            ReplacePage(
                result.Cards,
                result.TotalCount,
                result.TodayCount,
                result.FavoriteCount,
                result.AllMediaCount,
                result.AllTodayMediaCount);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // A newer generation owns the page state and loading indicator.
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            if (IsCurrentRefresh(operation))
            {
                ErrorMessage = L10n.Localize("ScreenshotMediaLoadFailed");
            }
        }
        finally
        {
            if (OwnsRefresh(operation))
            {
                IsLoading = false;
            }
            FinishRefresh(operation);
        }
    }

    public async Task GoToPreviousPageAsync(CancellationToken cancellationToken = default)
    {
        if (!CanGoPrevious)
        {
            return;
        }
        page--;
        NotifyPaginationChanged();
        await RefreshAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task GoToNextPageAsync(CancellationToken cancellationToken = default)
    {
        if (!CanGoNext)
        {
            return;
        }
        page++;
        NotifyPaginationChanged();
        await RefreshAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task<ScreenshotDetailViewModel?> OpenDetailsAsync(
        ScreenshotMediaCardViewModel card,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(card);
        DetailsRequested?.Invoke(this, card);
        if (records is null || assets is null || platform is null)
        {
            return null;
        }

        var record = await Task.Run(
            () => records.Get(card.Id),
            cancellationToken).ConfigureAwait(true);
        if (record is null)
        {
            StatusMessage = L10n.Localize("ScreenshotRecordUnavailable");
            return null;
        }

        var details = new ScreenshotDetailViewModel(
            record.Id,
            records,
            assets,
            platform,
            timeProvider,
            displayTimeZone,
            transformCacheInvalidator);
        details.ReprocessRequested += OnDetailReprocessRequested;
        openDetails.Add(new WeakReference<ScreenshotDetailViewModel>(details));
        await details.RefreshAsync(cancellationToken).ConfigureAwait(true);
        return details;
    }

    public async Task ExecuteCardActionAsync(
        ScreenshotMediaCardViewModel card,
        string action,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(card);
        ArgumentException.ThrowIfNullOrWhiteSpace(action);
        CardActionRequested?.Invoke(this, (card, action));
        if (records is null || platform is null)
        {
            return;
        }

        try
        {
            switch (action)
            {
                case ScreenshotMediaActions.CopyImage:
                    if (!card.CanCopyImage)
                    {
                        StatusMessage = L10n.Localize("ScreenshotAssetUnavailableAction");
                        return;
                    }
                    await platform.CopyImageAsync(
                        card.CanonicalImageAbsolutePath,
                        cancellationToken).ConfigureAwait(true);
                    StatusMessage = L10n.Localize("ScreenshotCopyImageSucceeded");
                    break;
                case ScreenshotMediaActions.CopyText:
                    if (string.IsNullOrWhiteSpace(card.Record.OcrText))
                    {
                        StatusMessage = L10n.Localize("ScreenshotTextUnavailable");
                        return;
                    }
                    await platform.CopyTextAsync(
                        card.Record.OcrText,
                        cancellationToken).ConfigureAwait(true);
                    StatusMessage = L10n.Localize("ScreenshotCopyTextSucceeded");
                    break;
                case ScreenshotMediaActions.Favorite:
                    if (!records.SetFavorite(
                            card.Id,
                            !card.IsFavorite,
                            timeProvider.GetUtcNow()))
                    {
                        StatusMessage = L10n.Localize("ScreenshotRecordUnavailable");
                        return;
                    }
                    StatusMessage = card.IsFavorite
                        ? L10n.Localize("ScreenshotFavoriteRemoved")
                        : L10n.Localize("ScreenshotFavoriteAdded");
                    await RefreshAsync(cancellationToken).ConfigureAwait(true);
                    break;
                case ScreenshotMediaActions.Delete:
                    if (!await platform.ConfirmDeleteAsync(
                            L10n.Localize("ScreenshotDeleteConfirmationTitle"),
                            Format("ScreenshotDeleteConfirmationMessage", card.CreatedAtText),
                            cancellationToken).ConfigureAwait(true))
                    {
                        return;
                    }
                    if (!records.SoftDelete(
                            card.Id,
                            timeProvider.GetUtcNow()))
                    {
                        StatusMessage = L10n.Localize("ScreenshotRecordUnavailable");
                        return;
                    }
                    transformCacheInvalidator?.Invalidate(card.Id);
                    StatusMessage = L10n.Localize("ScreenshotDeleteSucceeded");
                    await RefreshAsync(cancellationToken).ConfigureAwait(true);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(action));
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            StatusMessage = L10n.Localize("ScreenshotActionFailed");
        }
    }

    public async Task NotifyRecordUpdatedAsync(
        string screenshotId,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(screenshotId);
        await RefreshAsync(cancellationToken).ConfigureAwait(true);
        for (var index = openDetails.Count - 1; index >= 0; index--)
        {
            if (!openDetails[index].TryGetTarget(out var detail))
            {
                openDetails.RemoveAt(index);
                continue;
            }
            await detail.NotifyRecordUpdatedAsync(
                screenshotId,
                cancellationToken).ConfigureAwait(true);
        }
    }

    public void UpdateViewportWidth(double width)
    {
        if (!double.IsFinite(width) || width < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }
        var columns = width switch
        {
            >= 900 => 3,
            >= 620 => 2,
            _ => 1,
        };
        if (ColumnCount == columns)
        {
            return;
        }
        ColumnCount = columns;
        RebuildRows();
    }

    public void ReplacePage(
        IReadOnlyList<ScreenshotMediaCardViewModel> cards,
        int totalCount,
        int todayCount,
        int favoriteCount,
        int? allMediaCount = null,
        int? allTodayMediaCount = null)
    {
        ArgumentNullException.ThrowIfNull(cards);
        ArgumentOutOfRangeException.ThrowIfNegative(totalCount);
        ArgumentOutOfRangeException.ThrowIfNegative(todayCount);
        ArgumentOutOfRangeException.ThrowIfNegative(favoriteCount);

        pageCards.Clear();
        pageCards.AddRange(cards);
        RebuildRows();
        TotalCount = totalCount;
        TodayCount = todayCount;
        FavoriteCount = favoriteCount;
        AllMediaCount = allMediaCount ?? totalCount;
        AllTodayMediaCount = allTodayMediaCount ?? todayCount;
        ScreenshotCount = AllMediaCount;
        NotifyCollectionStateChanged();
        NotifyPaginationChanged();
    }

    private RefreshRequest CreateRefreshRequest()
    {
        var localToday = TimeZoneInfo.ConvertTime(
            timeProvider.GetUtcNow(),
            displayTimeZone).Date;
        var localTomorrow = localToday.AddDays(1);
        return new RefreshRequest(
            SearchText,
            SelectedFilter.Value == ScreenshotMediaFilter.Favorites,
            page,
            PageSize,
            new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(localToday, displayTimeZone)),
            new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(localTomorrow, displayTimeZone)));
    }

    private RefreshResult LoadRefreshResult(
        RefreshRequest request,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var allMediaAggregate = records!.GetAggregate(new ScreenshotRecordAggregateQuery(
            null,
            false,
            request.LocalDayStartUtc,
            request.LocalDayEndUtcExclusive));
        cancellationToken.ThrowIfCancellationRequested();
        var aggregate = string.IsNullOrWhiteSpace(request.SearchText)
            && !request.FavoritesOnly
                ? allMediaAggregate
                : records.GetAggregate(new ScreenshotRecordAggregateQuery(
            request.SearchText,
            request.FavoritesOnly,
            request.LocalDayStartUtc,
            request.LocalDayEndUtcExclusive));
        cancellationToken.ThrowIfCancellationRequested();
        var validPage = Math.Max(
            1,
            (aggregate.TotalCount + request.PageSize - 1) / request.PageSize);
        var resolvedPage = Math.Min(request.PageNumber, validPage);
        var result = records.Search(new ScreenshotRecordQuery(
            request.SearchText,
            request.FavoritesOnly,
            (resolvedPage - 1) * request.PageSize,
            request.PageSize));
        cancellationToken.ThrowIfCancellationRequested();
        var cards = result.Items
            .Select(record => CreateCard(record, request.SearchText))
            .ToArray();
        cancellationToken.ThrowIfCancellationRequested();
        return new RefreshResult(
            cards,
            result.TotalCount,
            aggregate.TodayCount,
            aggregate.FavoriteCount,
            allMediaAggregate.TotalCount,
            allMediaAggregate.TodayCount,
            resolvedPage);
    }

    private ScreenshotMediaCardViewModel CreateCard(
        ScreenshotRecord record,
        string searchText)
    {
        var originalPath = assets!.ResolveAbsolutePath(record.OriginalImagePath);
        var renderedPath = assets.ResolveAbsolutePath(record.RenderedImagePath);
        var translatedPath = record.TranslatedImagePath is null
            ? null
            : assets.ResolveAbsolutePath(record.TranslatedImagePath);
        var canonicalImage = SelectCanonicalImage(
            translatedPath,
            renderedPath,
            originalPath);
        var thumbnailPath = assets.ResolveAbsolutePath(record.ThumbnailPath);
        var thumbnail = SafeLoadImage(thumbnailPath);
        if (thumbnail.Image is null
            && canonicalImage.Availability == ScreenshotAssetAvailability.Available)
        {
            thumbnail = SafeLoadImage(canonicalImage.Path);
        }
        var createdAt = TimeZoneInfo.ConvertTime(record.CreatedAtUtc, displayTimeZone);
        var createdAtText = createdAt.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
        var resolution = $"{record.WidthPixels} × {record.HeightPixels}";
        var preview = SelectPreview(record, searchText);
        var assetStatus = canonicalImage.Availability switch
        {
            ScreenshotAssetAvailability.Available => string.Empty,
            ScreenshotAssetAvailability.Missing =>
                L10n.Localize("ScreenshotAssetMissing"),
            ScreenshotAssetAvailability.Unreadable =>
                L10n.Localize("ScreenshotAssetUnreadable"),
            _ => throw new ArgumentOutOfRangeException(),
        };
        return new ScreenshotMediaCardViewModel(
            record,
            originalPath,
            canonicalImage.Path,
            thumbnail.Image,
            canonicalImage.Availability,
            createdAtText,
            resolution,
            preview,
            Format("ScreenshotCardAccessibleNameFormat", createdAtText, resolution),
            assetStatus)
        {
            Id = record.Id,
            IsFavorite = record.IsFavorite,
        };
    }

    private CanonicalImageSelection SelectCanonicalImage(
        string? translatedPath,
        string renderedPath,
        string originalPath)
    {
        CanonicalImageSelection? firstUnreadable = null;
        var candidates = new[] { translatedPath, renderedPath, originalPath }
            .Where(static path => !string.IsNullOrWhiteSpace(path))
            .Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var candidate in candidates)
        {
            var availability = SafeGetAssetAvailability(candidate!);
            var selection = new CanonicalImageSelection(candidate!, availability);
            if (availability == ScreenshotAssetAvailability.Available)
            {
                return selection;
            }
            if (availability == ScreenshotAssetAvailability.Unreadable)
            {
                firstUnreadable ??= selection;
            }
        }

        return firstUnreadable
            ?? new CanonicalImageSelection(
                translatedPath ?? renderedPath,
                ScreenshotAssetAvailability.Missing);
    }

    private ScreenshotAssetAvailability SafeGetAssetAvailability(string path)
    {
        try
        {
            return platform!.GetAssetAvailability(path);
        }
        catch
        {
            return ScreenshotAssetAvailability.Unreadable;
        }
    }

    private ScreenshotImageLoadResult SafeLoadImage(string path)
    {
        try
        {
            return platform!.LoadImage(path);
        }
        catch
        {
            return new ScreenshotImageLoadResult(
                null,
                ScreenshotAssetAvailability.Unreadable);
        }
    }

    private RefreshOperation BeginRefresh(CancellationToken cancellationToken)
    {
        var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        lock (refreshSynchronization)
        {
            activeRefreshCancellation?.Cancel();
            activeRefreshCancellation = linked;
            return new RefreshOperation(++refreshGeneration, linked);
        }
    }

    private bool IsCurrentRefresh(RefreshOperation operation)
    {
        return OwnsRefresh(operation)
            && !operation.Cancellation.IsCancellationRequested;
    }

    private bool OwnsRefresh(RefreshOperation operation)
    {
        lock (refreshSynchronization)
        {
            return refreshGeneration == operation.Generation
                && ReferenceEquals(activeRefreshCancellation, operation.Cancellation);
        }
    }

    private void FinishRefresh(RefreshOperation operation)
    {
        lock (refreshSynchronization)
        {
            if (ReferenceEquals(activeRefreshCancellation, operation.Cancellation))
            {
                activeRefreshCancellation = null;
            }
        }
        operation.Cancellation.Dispose();
    }

    private void InvalidateActiveRefresh()
    {
        lock (refreshSynchronization)
        {
            refreshGeneration++;
            activeRefreshCancellation?.Cancel();
            activeRefreshCancellation = null;
        }
        IsLoading = false;
    }

    private void RebuildRows()
    {
        rows.Clear();
        foreach (var group in pageCards.Chunk(ColumnCount))
        {
            rows.Add(new ScreenshotMediaRowViewModel(group));
        }
        OnPropertyChanged(nameof(Rows));
        NotifyCollectionStateChanged();
    }

    private void ResetPageForQueryChange()
    {
        page = 1;
        InvalidateActiveRefresh();
        OnPropertyChanged(nameof(HasQuery));
        OnPropertyChanged(nameof(EmptyTitle));
        OnPropertyChanged(nameof(EmptyHint));
        NotifyPaginationChanged();
    }

    private void NotifyCollectionStateChanged()
    {
        OnPropertyChanged(nameof(HasRecords));
        OnPropertyChanged(nameof(IsEmpty));
    }

    private void NotifyPaginationChanged()
    {
        OnPropertyChanged(nameof(PageNumber));
        OnPropertyChanged(nameof(PageCount));
        OnPropertyChanged(nameof(PageSummary));
        OnPropertyChanged(nameof(CanGoPrevious));
        OnPropertyChanged(nameof(CanGoNext));
    }

    private void OnDetailReprocessRequested(object? sender, string screenshotId) =>
        ReprocessRequested?.Invoke(this, screenshotId);

    private static string SelectPreview(ScreenshotRecord record, string query)
    {
        var candidates = new[]
        {
            record.OcrText,
            record.RefinedText,
            record.TranslatedText,
            record.SummaryText,
        };
        var normalizedQuery = ScreenshotSearchNormalizer.Normalize(query);
        if (normalizedQuery.Length > 0)
        {
            var match = candidates.FirstOrDefault(candidate =>
                !string.IsNullOrWhiteSpace(candidate)
                && ScreenshotSearchNormalizer.Normalize(candidate)
                    .Contains(normalizedQuery, StringComparison.Ordinal));
            if (match is not null)
            {
                return match;
            }
        }
        return candidates.FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate))
            ?? L10n.Localize("ScreenshotTextUnavailable");
    }

    private static string Format(string key, params object[] values) =>
        string.Format(
            CultureInfo.CurrentUICulture,
            L10n.Localize(key),
            values);

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

    private sealed record RefreshRequest(
        string SearchText,
        bool FavoritesOnly,
        int PageNumber,
        int PageSize,
        DateTimeOffset LocalDayStartUtc,
        DateTimeOffset LocalDayEndUtcExclusive);

    private sealed record RefreshResult(
        IReadOnlyList<ScreenshotMediaCardViewModel> Cards,
        int TotalCount,
        int TodayCount,
        int FavoriteCount,
        int AllMediaCount,
        int AllTodayMediaCount,
        int PageNumber);

    private sealed record CanonicalImageSelection(
        string Path,
        ScreenshotAssetAvailability Availability);

    private sealed record RefreshOperation(
        long Generation,
        CancellationTokenSource Cancellation);
}
