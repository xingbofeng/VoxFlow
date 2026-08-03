using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotMediaPageViewModelTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 8, 30, 0, TimeSpan.Zero);

    [Fact]
    public async Task Wpf_asset_probe_distinguishes_valid_missing_and_corrupt_images()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var root = Path.Combine(
                Path.GetTempPath(),
                $"voxflow-media-probe-{Guid.NewGuid():N}");
            Directory.CreateDirectory(root);
            try
            {
                var validPath = Path.Combine(root, "valid.png");
                var corruptPath = Path.Combine(root, "corrupt.png");
                var missingPath = Path.Combine(root, "missing.png");
                var bitmap = BitmapSource.Create(
                    1,
                    1,
                    96,
                    96,
                    PixelFormats.Bgra32,
                    null,
                    new byte[] { 12, 34, 56, 255 },
                    4);
                bitmap.Freeze();
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using (var stream = File.Create(validPath))
                {
                    encoder.Save(stream);
                }
                File.WriteAllBytes(corruptPath, "not a PNG"u8.ToArray());
                var platform = new WpfScreenshotMediaPlatform();

                Assert.Equal(
                    ScreenshotAssetAvailability.Available,
                    platform.GetAssetAvailability(validPath));
                Assert.Equal(
                    ScreenshotAssetAvailability.Unreadable,
                    platform.GetAssetAvailability(corruptPath));
                Assert.Equal(
                    ScreenshotAssetAvailability.Missing,
                    platform.GetAssetAvailability(missingPath));
            }
            finally
            {
                Directory.Delete(root, recursive: true);
            }
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Loads_only_the_requested_page_and_groups_cards_into_three_virtualized_columns()
    {
        var records = Enumerable.Range(1, 65)
            .Select(index => Record(index, Now.AddMinutes(-index)))
            .ToArray();
        var repository = new MemoryScreenshotRepository(records);
        var platform = new CapturingScreenshotMediaPlatform();
        var viewModel = CreateViewModel(repository, platform);

        await viewModel.RefreshAsync();

        Assert.Equal([3, 3, 3, 3, 3, 3, 2], viewModel.Rows.Select(row => row.Cards.Count));
        Assert.Equal(65, viewModel.TotalCount);
        Assert.Equal(4, viewModel.PageCount);
        Assert.Equal(20, platform.LoadedPaths.Count);
        Assert.True(viewModel.CanGoNext);
        Assert.False(viewModel.IsLoading);
        Assert.False(viewModel.HasError);
        Assert.Equal(
            "2026-07-14 08:29",
            viewModel.Rows[0].Cards[0].CreatedAtText);
        Assert.Equal(1, repository.SearchCallCount);
        Assert.Equal(1, repository.AggregateCallCount);
    }

    [Fact]
    public async Task Thousands_of_records_use_one_page_query_and_one_aggregate_query()
    {
        var repository = new MemoryScreenshotRepository(
            Enumerable.Range(1, 3_000)
                .Select(index => Record(index, Now.AddMinutes(-index)))
                .ToArray());
        var platform = new CapturingScreenshotMediaPlatform();
        var viewModel = CreateViewModel(repository, platform);

        await viewModel.RefreshAsync();

        Assert.Equal(3_000, viewModel.TotalCount);
        Assert.Equal(20, viewModel.Rows.Sum(row => row.Cards.Count));
        Assert.Equal(20, platform.LoadedPaths.Count);
        Assert.Equal(1, repository.SearchCallCount);
        Assert.Equal(1, repository.AggregateCallCount);
    }

    [Fact]
    public async Task Late_refresh_is_dropped_after_a_new_query_generation_completes()
    {
        var repository = new DelayedAggregateScreenshotRepository(
        [
            Record(1, Now, ocrText: "old query result"),
            Record(2, Now.AddMinutes(-1), ocrText: "new query result"),
        ]);
        var viewModel = CreateViewModel(repository);
        viewModel.SearchText = "old";
        var oldRefresh = viewModel.RefreshAsync();
        await repository.FirstAggregateStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

        viewModel.SearchText = "new";
        var newRefresh = viewModel.RefreshAsync();
        try
        {
            await newRefresh.WaitAsync(TimeSpan.FromSeconds(2));
            var current = Assert.Single(Assert.Single(viewModel.Rows).Cards);
            Assert.Contains("new query result", current.TextPreview, StringComparison.Ordinal);
        }
        finally
        {
            repository.ReleaseFirstAggregate.TrySetResult();
        }

        await oldRefresh.WaitAsync(TimeSpan.FromSeconds(2));
        var retained = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        Assert.Contains("new query result", retained.TextPreview, StringComparison.Ordinal);
        Assert.Equal(1, repository.SearchCallCount);
        Assert.Equal(4, repository.AggregateCallCount);
        Assert.False(viewModel.IsLoading);
    }

    [Fact]
    public async Task Cancelled_refresh_clears_loading_without_querying_or_replacing_the_page()
    {
        var repository = new MemoryScreenshotRepository([Record(1, Now)]);
        var viewModel = CreateViewModel(repository);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => viewModel.RefreshAsync(cancellation.Token));

        Assert.False(viewModel.IsLoading);
        Assert.Empty(viewModel.Rows);
        Assert.Equal(0, repository.SearchCallCount);
        Assert.Equal(0, repository.AggregateCallCount);
    }

    [Fact]
    public async Task Aggregate_receives_the_current_local_day_as_half_open_utc_bounds()
    {
        var repository = new MemoryScreenshotRepository([Record(1, Now)]);
        var localTimeZone = TimeZoneInfo.CreateCustomTimeZone(
            "Screenshot-test-UTC-plus-8",
            TimeSpan.FromHours(8),
            "Screenshot test UTC+8",
            "Screenshot test UTC+8");
        var viewModel = new ScreenshotMediaPageViewModel(
            "Screenshots",
            "Capture and revisit screenshots",
            repository,
            new FakeScreenshotAssetStore(),
            new CapturingScreenshotMediaPlatform(),
            new FixedTimeProvider(Now),
            localTimeZone);

        await viewModel.RefreshAsync();

        Assert.Equal(
            new DateTimeOffset(2026, 7, 13, 16, 0, 0, TimeSpan.Zero),
            repository.LastAggregateQuery?.LocalDayStartUtc);
        Assert.Equal(
            new DateTimeOffset(2026, 7, 14, 16, 0, 0, TimeSpan.Zero),
            repository.LastAggregateQuery?.LocalDayEndUtcExclusive);
    }

    [Fact]
    public void Repository_and_frozen_image_decode_run_off_the_refresh_caller_thread()
    {
        var repository = new MemoryScreenshotRepository([Record(1, Now)]);
        var platform = new CapturingScreenshotMediaPlatform();
        var viewModel = CreateViewModel(repository, platform);
        var callerThreadId = 0;
        Exception? failure = null;
        var caller = new Thread(() =>
        {
            callerThreadId = Environment.CurrentManagedThreadId;
            try
            {
                viewModel.RefreshAsync().GetAwaiter().GetResult();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        });

        caller.Start();

        Assert.True(caller.Join(TimeSpan.FromSeconds(5)));
        Assert.Null(failure);
        Assert.NotEqual(callerThreadId, repository.LastAggregateThreadId);
        Assert.NotEqual(callerThreadId, repository.LastSearchThreadId);
        Assert.NotEmpty(platform.ImageLoadThreadIds);
        Assert.All(
            platform.ImageLoadThreadIds,
            threadId => Assert.NotEqual(callerThreadId, threadId));
    }

    [Fact]
    public async Task Opening_details_reads_the_record_resolves_paths_and_decodes_off_the_caller_thread()
    {
        var repository = new MemoryScreenshotRepository([Record(1, Now)]);
        var assets = new FakeScreenshotAssetStore();
        var platform = new CapturingScreenshotMediaPlatform();
        var viewModel = CreateViewModel(repository, platform, assets);
        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        assets.ResolveThreadIds.Clear();
        platform.ImageLoadThreadIds.Clear();
        var callerThreadId = 0;
        ScreenshotDetailViewModel? details = null;
        Exception? failure = null;
        var caller = new Thread(() =>
        {
            callerThreadId = Environment.CurrentManagedThreadId;
            try
            {
                details = viewModel.OpenDetailsAsync(card).GetAwaiter().GetResult();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        });

        caller.Start();

        Assert.True(caller.Join(TimeSpan.FromSeconds(5)));
        Assert.Null(failure);
        Assert.NotNull(details);
        Assert.NotEqual(callerThreadId, repository.LastGetThreadId);
        Assert.NotEmpty(assets.ResolveThreadIds);
        Assert.All(
            assets.ResolveThreadIds,
            threadId => Assert.NotEqual(callerThreadId, threadId));
        Assert.NotEmpty(platform.ImageLoadThreadIds);
        Assert.All(
            platform.ImageLoadThreadIds,
            threadId => Assert.NotEqual(callerThreadId, threadId));
        Assert.True(details.OriginalImage?.IsFrozen);
    }

    [Fact]
    public async Task Search_projects_the_matching_translation_and_favorites_filter_is_forwarded()
    {
        var matching = Record(
            1,
            Now,
            ocrText: "unrelated OCR",
            translatedText: "A translated needle appears here",
            isFavorite: true);
        var repository = new MemoryScreenshotRepository(
        [
            matching,
            Record(2, Now.AddMinutes(-1), ocrText: "another record"),
        ]);
        var viewModel = CreateViewModel(repository);
        viewModel.SearchText = "ＮＥＥＤＬＥ";
        viewModel.SelectedFilter = viewModel.FilterOptions.Single(
            option => option.Value == ScreenshotMediaFilter.Favorites);

        await viewModel.RefreshAsync();

        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        Assert.Contains("translated needle", card.TextPreview, StringComparison.OrdinalIgnoreCase);
        Assert.True(repository.LastQuery?.FavoritesOnly);
        Assert.Equal("ＮＥＥＤＬＥ", repository.LastQuery?.SearchText);
        Assert.Equal(1, viewModel.FavoriteCount);
    }

    [Fact]
    public async Task Favorite_state_is_exposed_as_localized_assistive_status()
    {
        var repository = new MemoryScreenshotRepository(
        [
            Record(1, Now, isFavorite: true),
            Record(2, Now.AddMinutes(-1), isFavorite: false),
        ]);
        var viewModel = CreateViewModel(repository);

        await viewModel.RefreshAsync();

        var cards = viewModel.Rows.SelectMany(row => row.Cards).ToArray();
        Assert.Equal(L10n.ScreenshotFavorited, cards[0].FavoriteStatusText);
        Assert.Equal(L10n.ScreenshotNotFavorited, cards[1].FavoriteStatusText);
    }

    [Fact]
    public async Task Deleting_the_only_item_on_the_last_page_returns_to_the_last_valid_page()
    {
        var repository = new MemoryScreenshotRepository(
            Enumerable.Range(1, 21)
                .Select(index => Record(index, Now.AddMinutes(-index)))
                .ToArray());
        var platform = new CapturingScreenshotMediaPlatform { ConfirmDelete = true };
        var cache = new ScreenshotTransformCache();
        var viewModel = CreateViewModel(
            repository,
            platform,
            transformCacheInvalidator: cache);
        await viewModel.RefreshAsync();
        await viewModel.GoToNextPageAsync();
        var lastCard = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        var cachedRequest = TransformRequest(lastCard.Id);
        cache.Store(cachedRequest, "cached transform");

        await viewModel.ExecuteCardActionAsync(lastCard, ScreenshotMediaActions.Delete);

        Assert.Equal(1, viewModel.PageNumber);
        Assert.Equal(1, viewModel.PageCount);
        Assert.Equal(20, viewModel.TotalCount);
        Assert.Equal(20, viewModel.Rows.Sum(row => row.Cards.Count));
        Assert.DoesNotContain(lastCard.Id, repository.VisibleRecords.Select(record => record.Id));
        Assert.False(cache.TryGet(cachedRequest, out _));
    }

    [Fact]
    public async Task Cancelled_delete_leaves_repository_page_and_assets_unchanged()
    {
        var record = Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        var assets = new FakeScreenshotAssetStore();
        var platform = new CapturingScreenshotMediaPlatform { ConfirmDelete = false };
        var cache = new ScreenshotTransformCache();
        var viewModel = CreateViewModel(
            repository,
            platform,
            assets,
            cache);
        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        var cachedRequest = TransformRequest(card.Id);
        cache.Store(cachedRequest, "cached transform");

        await viewModel.ExecuteCardActionAsync(card, ScreenshotMediaActions.Delete);

        Assert.NotNull(repository.Get(record.Id));
        Assert.Empty(assets.DeletedAssets);
        Assert.Equal(1, viewModel.TotalCount);
        Assert.True(cache.TryGet(cachedRequest, out _));
    }

    [Fact]
    public async Task Opened_detail_reprocess_uses_the_media_cache_invalidator()
    {
        var record = Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        var cache = new ScreenshotTransformCache();
        var viewModel = CreateViewModel(
            repository,
            transformCacheInvalidator: cache);
        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        var details = Assert.IsType<ScreenshotDetailViewModel>(
            await viewModel.OpenDetailsAsync(card));
        var cachedRequest = TransformRequest(card.Id);
        cache.Store(cachedRequest, "cached transform");
        var reprocessedId = string.Empty;
        viewModel.ReprocessRequested += (_, id) => reprocessedId = id;

        await details.ExecuteAsync(ScreenshotMediaActions.Reprocess);

        Assert.Equal(card.Id, reprocessedId);
        Assert.False(cache.TryGet(cachedRequest, out _));
    }

    [Fact]
    public async Task Missing_image_keeps_text_available_and_reports_copy_image_failure_without_throwing()
    {
        var record = Record(1, Now, ocrText: "可复制的识别文本");
        var repository = new MemoryScreenshotRepository([record]);
        var platform = new CapturingScreenshotMediaPlatform
        {
            ImageAvailability = ScreenshotAssetAvailability.Missing,
        };
        var viewModel = CreateViewModel(repository, platform);
        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);

        await viewModel.ExecuteCardActionAsync(card, ScreenshotMediaActions.CopyImage);
        await viewModel.ExecuteCardActionAsync(card, ScreenshotMediaActions.CopyText);

        Assert.True(card.IsImageMissing);
        Assert.False(card.CanCopyImage);
        Assert.NotNull(viewModel.StatusMessage);
        Assert.Empty(platform.CopiedImagePaths);
        Assert.Equal(["可复制的识别文本"], platform.CopiedTexts);
    }

    [Fact]
    public async Task Translated_image_is_the_card_preview_fallback_and_copy_source()
    {
        var record = new ScreenshotRecord(
            "shot-translated-card",
            "Screenshots/shot-translated-card-original.png",
            "Screenshots/shot-translated-card.png",
            "Screenshots/shot-translated-card-thumbnail.png",
            1200,
            800,
            240_000,
            "OCR",
            Now,
            translatedImagePath: "Screenshots/shot-translated-card-translated.png");
        var repository = new MemoryScreenshotRepository([record]);
        var assets = new FakeScreenshotAssetStore();
        var thumbnailPath = assets.ResolveAbsolutePath(record.ThumbnailPath);
        var renderedPath = assets.ResolveAbsolutePath(record.RenderedImagePath);
        var translatedPath = assets.ResolveAbsolutePath(record.TranslatedImagePath!);
        var platform = new CapturingScreenshotMediaPlatform();
        platform.AssetAvailabilityByPath[thumbnailPath] = ScreenshotAssetAvailability.Missing;
        platform.AssetAvailabilityByPath[renderedPath] = ScreenshotAssetAvailability.Missing;
        platform.AssetAvailabilityByPath[translatedPath] = ScreenshotAssetAvailability.Available;
        var viewModel = CreateViewModel(repository, platform, assets);

        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        await viewModel.ExecuteCardActionAsync(card, ScreenshotMediaActions.CopyImage);

        Assert.True(card.CanCopyImage);
        Assert.False(card.IsImageMissing);
        Assert.Equal([translatedPath], platform.AvailabilityCheckedPaths);
        Assert.Equal([thumbnailPath, translatedPath], platform.LoadedPaths);
        Assert.Equal([translatedPath], platform.CopiedImagePaths);
    }

    [Theory]
    [InlineData(ScreenshotAssetAvailability.Missing)]
    [InlineData(ScreenshotAssetAvailability.Unreadable)]
    public async Task Unavailable_translated_image_falls_back_to_the_rendered_image(
        ScreenshotAssetAvailability translatedAvailability)
    {
        var record = new ScreenshotRecord(
            "shot-translated-fallback",
            "Screenshots/shot-translated-fallback-original.png",
            "Screenshots/shot-translated-fallback-rendered.png",
            "Screenshots/shot-translated-fallback-thumbnail.png",
            1200,
            800,
            240_000,
            "OCR",
            Now,
            translatedImagePath: "Screenshots/shot-translated-fallback-translated.png");
        var repository = new MemoryScreenshotRepository([record]);
        var assets = new FakeScreenshotAssetStore();
        var thumbnailPath = assets.ResolveAbsolutePath(record.ThumbnailPath);
        var renderedPath = assets.ResolveAbsolutePath(record.RenderedImagePath);
        var translatedPath = assets.ResolveAbsolutePath(record.TranslatedImagePath!);
        var platform = new CapturingScreenshotMediaPlatform();
        platform.AssetAvailabilityByPath[thumbnailPath] = ScreenshotAssetAvailability.Missing;
        platform.AssetAvailabilityByPath[translatedPath] = translatedAvailability;
        platform.AssetAvailabilityByPath[renderedPath] = ScreenshotAssetAvailability.Available;
        var viewModel = CreateViewModel(repository, platform, assets);

        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        await viewModel.ExecuteCardActionAsync(card, ScreenshotMediaActions.CopyImage);

        Assert.True(card.CanCopyImage);
        Assert.False(card.IsImageMissing);
        Assert.Equal([translatedPath, renderedPath], platform.AvailabilityCheckedPaths);
        Assert.Equal([thumbnailPath, renderedPath], platform.LoadedPaths);
        Assert.Equal([renderedPath], platform.CopiedImagePaths);
        Assert.Equal(ScreenshotAssetAvailability.Available, card.ImageAvailability);
        Assert.Equal(renderedPath, card.CanonicalImageAbsolutePath);
    }

    [Fact]
    public async Task Favorite_action_persists_and_refreshes_the_card_projection()
    {
        var repository = new MemoryScreenshotRepository([Record(1, Now)]);
        var viewModel = CreateViewModel(repository);
        await viewModel.RefreshAsync();
        var card = Assert.Single(Assert.Single(viewModel.Rows).Cards);

        await viewModel.ExecuteCardActionAsync(card, ScreenshotMediaActions.Favorite);

        var refreshed = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        Assert.True(refreshed.IsFavorite);
        Assert.Equal("\uE735", refreshed.FavoriteGlyph);
        Assert.True(repository.Get(card.Id)?.IsFavorite);
        Assert.Equal(1, viewModel.FavoriteCount);
    }

    [Fact]
    public async Task Transform_persistence_event_refreshes_the_media_query_and_open_detail()
    {
        var runId = Guid.NewGuid();
        var record = Record(1, Now, ocrText: "Original OCR");
        var repository = new MemoryScreenshotRepository([record]);
        var viewModel = CreateViewModel(repository);
        await viewModel.RefreshAsync();
        var originalCard = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        var detail = Assert.IsType<ScreenshotDetailViewModel>(
            await viewModel.OpenDetailsAsync(originalCard));
        viewModel.SearchText = "fresh summary";
        var coordinator = new ScreenshotTransformPersistenceCoordinator(
            repository,
            new FixedTimeProvider(Now.AddSeconds(1)),
            new CurrentRunValidity(runId));
        var refreshed = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        coordinator.RecordUpdated += OnRecordUpdated;

        Assert.True(coordinator.Persist(new ScreenshotTransformCompleted(
            runId,
            record.Id,
            ScreenshotTransformOperation.Summary,
            "Fresh summary",
            fromCache: false)));
        await refreshed.Task.WaitAsync(TimeSpan.FromSeconds(2));

        var refreshedCard = Assert.Single(Assert.Single(viewModel.Rows).Cards);
        Assert.Equal("Fresh summary", refreshedCard.TextPreview);
        Assert.Equal("Fresh summary", detail.SummaryText);
        coordinator.RecordUpdated -= OnRecordUpdated;

        async void OnRecordUpdated(
            object? sender,
            ScreenshotRecordUpdatedEventArgs eventArgs)
        {
            _ = sender;
            try
            {
                await viewModel.NotifyRecordUpdatedAsync(eventArgs.ScreenshotId);
                refreshed.TrySetResult();
            }
            catch (Exception exception)
            {
                refreshed.TrySetException(exception);
            }
        }
    }

    [Theory]
    [InlineData(1100, 3)]
    [InlineData(760, 2)]
    [InlineData(520, 1)]
    public async Task Responsive_projection_regroups_cards_without_changing_the_page(double width, int columns)
    {
        var repository = new MemoryScreenshotRepository(
            Enumerable.Range(1, 7).Select(index => Record(index, Now.AddMinutes(-index))).ToArray());
        var viewModel = CreateViewModel(repository);
        await viewModel.RefreshAsync();

        viewModel.UpdateViewportWidth(width);

        Assert.Equal(columns, viewModel.ColumnCount);
        Assert.Equal(7, viewModel.Rows.Sum(row => row.Cards.Count));
        Assert.All(viewModel.Rows, row => Assert.InRange(row.Cards.Count, 1, columns));
    }

    [Fact]
    public void Filter_labels_are_localized_user_facing_values()
    {
        var viewModel = new ScreenshotMediaPageViewModel(
            "Screenshots",
            "Capture and revisit screenshots");

        Assert.Equal(3, viewModel.FilterOptions.Count);
        Assert.DoesNotContain(
            viewModel.FilterOptions,
            option => option.Label.Contains("record", StringComparison.OrdinalIgnoreCase));
        Assert.All(viewModel.FilterOptions, option =>
        {
            Assert.False(string.IsNullOrWhiteSpace(option.Label));
            Assert.DoesNotContain("ScreenshotFilter", option.Label, StringComparison.Ordinal);
        });
    }

    private static ScreenshotMediaPageViewModel CreateViewModel(
        MemoryScreenshotRepository repository,
        CapturingScreenshotMediaPlatform? platform = null,
        FakeScreenshotAssetStore? assets = null,
        IScreenshotTransformCacheInvalidator? transformCacheInvalidator = null) => new(
            "Screenshots",
            "Capture and revisit screenshots",
            repository,
            assets ?? new FakeScreenshotAssetStore(),
            platform ?? new CapturingScreenshotMediaPlatform(),
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            transformCacheInvalidator);

    private static ScreenshotTransformRequest TransformRequest(string screenshotId) => new(
        Guid.Parse("33333333-3333-3333-3333-333333333333"),
        screenshotId,
        "OCR text",
        ScreenshotTransformOperation.Summary,
        "image-revision");

    internal static ScreenshotRecord Record(
        int index,
        DateTimeOffset createdAt,
        string? ocrText = null,
        string? translatedText = null,
        bool isFavorite = false) => new(
            id: $"shot-{index:000}",
            originalImagePath: $"Screenshots/shot-{index:000}-original.png",
            renderedImagePath: $"Screenshots/shot-{index:000}.png",
            thumbnailPath: $"Screenshots/shot-{index:000}-thumbnail.png",
            widthPixels: 1200,
            heightPixels: 800,
            fileSizeBytes: 240_000,
            ocrText: ocrText ?? $"Recognized text {index}",
            createdAtUtc: createdAt,
            translatedText: translatedText,
            isFavorite: isFavorite);

    private sealed class CurrentRunValidity(Guid runId) : IScreenshotResultRunValidity
    {
        public bool IsResultCurrent(Guid candidate) => candidate == runId;
    }

    private sealed class DelayedAggregateScreenshotRepository(
        IEnumerable<ScreenshotRecord> seed) : MemoryScreenshotRepository(seed)
    {
        public TaskCompletionSource FirstAggregateStarted { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource ReleaseFirstAggregate { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public override ScreenshotRecordAggregate GetAggregate(
            ScreenshotRecordAggregateQuery query)
        {
            if (string.Equals(query.SearchText, "old", StringComparison.Ordinal))
            {
                FirstAggregateStarted.TrySetResult();
                ReleaseFirstAggregate.Task.GetAwaiter().GetResult();
            }
            return base.GetAggregate(query);
        }
    }
}

internal class MemoryScreenshotRepository(
    IEnumerable<ScreenshotRecord> seed) : IScreenshotRecordRepository
{
    private readonly Dictionary<string, ScreenshotRecord> records = seed.ToDictionary(record => record.Id);
    private int aggregateCallCount;
    private int searchCallCount;

    public ScreenshotRecordQuery? LastQuery { get; private set; }

    public ScreenshotRecordAggregateQuery? LastAggregateQuery { get; private set; }

    public int AggregateCallCount => Volatile.Read(ref aggregateCallCount);

    public int SearchCallCount => Volatile.Read(ref searchCallCount);

    public int LastAggregateThreadId { get; private set; }

    public int LastSearchThreadId { get; private set; }

    public int LastGetThreadId { get; private set; }

    public IReadOnlyList<ScreenshotRecord> VisibleRecords => records.Values
        .Where(record => record.DeletedAtUtc is null)
        .ToArray();

    public void Add(ScreenshotRecord record) => records.Add(record.Id, record);

    public virtual ScreenshotRecord? Get(string id, bool includeDeleted = false)
    {
        LastGetThreadId = Environment.CurrentManagedThreadId;
        return records.TryGetValue(id, out var record)
            && (includeDeleted || record.DeletedAtUtc is null)
                ? record
                : null;
    }

    public virtual ScreenshotRecordPage Search(ScreenshotRecordQuery query)
    {
        Interlocked.Increment(ref searchCallCount);
        LastSearchThreadId = Environment.CurrentManagedThreadId;
        LastQuery = query;
        var matches = Match(query.SearchText, query.FavoritesOnly)
            .OrderByDescending(record => record.CreatedAtUtc)
            .ThenBy(record => record.Id, StringComparer.Ordinal)
            .ToArray();
        return new ScreenshotRecordPage(
            matches.Skip(query.Offset).Take(query.Limit).ToArray(),
            matches.Length,
            query.Offset,
            query.Limit);
    }

    public virtual ScreenshotRecordAggregate GetAggregate(
        ScreenshotRecordAggregateQuery query)
    {
        Interlocked.Increment(ref aggregateCallCount);
        LastAggregateThreadId = Environment.CurrentManagedThreadId;
        LastAggregateQuery = query;
        var matches = Match(query.SearchText, query.FavoritesOnly);
        return new ScreenshotRecordAggregate(
            matches.Count,
            matches.Count(record =>
                record.CreatedAtUtc >= query.LocalDayStartUtc
                && record.CreatedAtUtc < query.LocalDayEndUtcExclusive),
            matches.Count(record => record.IsFavorite));
    }

    public ScreenshotRecordStats GetStats()
    {
        var visible = VisibleRecords;
        return new ScreenshotRecordStats(
            visible.Count,
            visible.Count(record => record.IsFavorite),
            visible.Sum(record => record.FileSizeBytes),
            visible.Sum(record => (long)record.CharacterCount));
    }

    private IReadOnlyList<ScreenshotRecord> Match(string? searchText, bool favoritesOnly)
    {
        var normalized = ScreenshotSearchNormalizer.Normalize(searchText);
        return records.Values
            .Where(record => record.DeletedAtUtc is null)
            .Where(record => !favoritesOnly || record.IsFavorite)
            .Where(record => normalized.Length == 0
                || ScreenshotSearchNormalizer.ForRecord(
                        record.OcrText,
                        record.RefinedText,
                        record.TranslatedText,
                        record.SummaryText)
                    .Contains(normalized, StringComparison.Ordinal))
            .ToArray();
    }

    public IReadOnlyList<ScreenshotRecord> ListDeletedBefore(
        DateTimeOffset deletedBeforeUtcExclusive) => records.Values
            .Where(record => record.DeletedAtUtc < deletedBeforeUtcExclusive)
            .OrderBy(record => record.DeletedAtUtc)
            .ThenBy(record => record.Id, StringComparer.Ordinal)
            .ToArray();

    public IReadOnlySet<string> ListReferencedAssetPaths() => records.Values
        .SelectMany(record => new[]
        {
            record.OriginalImagePath,
            record.RenderedImagePath,
            record.ThumbnailPath,
            record.TranslatedImagePath,
        })
        .Where(path => path is not null)
        .Cast<string>()
        .ToHashSet(StringComparer.OrdinalIgnoreCase);

    public bool SetFavorite(string id, bool isFavorite, DateTimeOffset updatedAtUtc)
    {
        var current = Get(id);
        if (current is null)
        {
            return false;
        }
        records[id] = Clone(current, isFavorite: isFavorite, updatedAtUtc: updatedAtUtc);
        return true;
    }

    public bool SoftDelete(string id, DateTimeOffset deletedAtUtc)
    {
        var current = Get(id);
        if (current is null)
        {
            return false;
        }
        records[id] = Clone(current, deletedAtUtc: deletedAtUtc, updatedAtUtc: deletedAtUtc);
        return true;
    }

    public bool PurgeDeleted(
        string id,
        DateTimeOffset deletedBeforeUtcExclusive)
    {
        var current = Get(id, includeDeleted: true);
        return current?.DeletedAtUtc < deletedBeforeUtcExclusive
            && records.Remove(id);
    }

    public bool ReplaceOcrAndInvalidateTransforms(
        string id,
        string text,
        DateTimeOffset updatedAtUtc)
    {
        var current = Get(id);
        if (current is null)
        {
            return false;
        }
        records[id] = new ScreenshotRecord(
            current.Id,
            current.OriginalImagePath,
            current.RenderedImagePath,
            current.ThumbnailPath,
            current.WidthPixels,
            current.HeightPixels,
            current.FileSizeBytes,
            text,
            current.CreatedAtUtc,
            translatedImagePath: null,
            sourceDisplayId: current.SourceDisplayId,
            sourceWindowTitle: current.SourceWindowTitle,
            refinedText: null,
            translatedText: null,
            summaryText: null,
            isFavorite: current.IsFavorite,
            updatedAtUtc: updatedAtUtc,
            deletedAtUtc: current.DeletedAtUtc);
        return true;
    }

    public bool UpdateTransform(
        string id,
        ScreenshotTransformOperation operation,
        string text,
        DateTimeOffset updatedAtUtc,
        string? translatedImagePath = null)
    {
        var current = Get(id);
        if (current is null)
        {
            return false;
        }
        records[id] = Clone(
            current,
            refinedText: operation == ScreenshotTransformOperation.Refinement ? text : current.RefinedText,
            translatedText: operation == ScreenshotTransformOperation.Translation ? text : current.TranslatedText,
            summaryText: operation == ScreenshotTransformOperation.Summary ? text : current.SummaryText,
            translatedImagePath: translatedImagePath ?? current.TranslatedImagePath,
            updatedAtUtc: updatedAtUtc);
        return true;
    }

    private static ScreenshotRecord Clone(
        ScreenshotRecord source,
        bool? isFavorite = null,
        string? refinedText = null,
        string? translatedText = null,
        string? summaryText = null,
        string? translatedImagePath = null,
        DateTimeOffset? updatedAtUtc = null,
        DateTimeOffset? deletedAtUtc = null) => new(
            source.Id,
            source.OriginalImagePath,
            source.RenderedImagePath,
            source.ThumbnailPath,
            source.WidthPixels,
            source.HeightPixels,
            source.FileSizeBytes,
            source.OcrText,
            source.CreatedAtUtc,
            translatedImagePath ?? source.TranslatedImagePath,
            source.SourceDisplayId,
            source.SourceWindowTitle,
            refinedText ?? source.RefinedText,
            translatedText ?? source.TranslatedText,
            summaryText ?? source.SummaryText,
            isFavorite ?? source.IsFavorite,
            updatedAtUtc ?? source.UpdatedAtUtc,
            deletedAtUtc ?? source.DeletedAtUtc);
}

internal sealed class FakeScreenshotAssetStore : IScreenshotAssetStore
{
    public List<ScreenshotAssetSet> DeletedAssets { get; } = [];

    public List<int> ResolveThreadIds { get; } = [];

    public Task<ScreenshotAssetSet> SaveAsync(
        ScreenshotAssetWriteRequest request,
        CancellationToken cancellationToken) => throw new NotSupportedException();

    public Task<ScreenshotAssetDeleteResult> DeleteAsync(
        ScreenshotAssetSet assets,
        CancellationToken cancellationToken)
    {
        DeletedAssets.Add(assets);
        return Task.FromResult(new ScreenshotAssetDeleteResult(
            assets.AllRelativePaths.Count));
    }

    public string ResolveAbsolutePath(string relativePath)
    {
        ResolveThreadIds.Add(Environment.CurrentManagedThreadId);
        return "C:\\VoxFlowData\\" + relativePath.Replace('/', '\\');
    }

    public Task<int> CleanupOrphansAsync(
        IReadOnlySet<string> referencedRelativePaths,
        DateTimeOffset deleteBeforeUtcExclusive,
        CancellationToken cancellationToken) => Task.FromResult(0);
}

internal sealed class CapturingScreenshotMediaPlatform : IScreenshotMediaPlatform
{
    private static readonly BitmapSource AvailableBitmap = CreateBitmap();

    public ScreenshotAssetAvailability ImageAvailability { get; set; } =
        ScreenshotAssetAvailability.Available;

    public bool CreateDistinctImages { get; set; }

    public bool ReturnUnfrozenImages { get; set; }

    public bool ConfirmDelete { get; set; }

    public Dictionary<string, ScreenshotAssetAvailability> AssetAvailabilityByPath { get; } =
        new(StringComparer.OrdinalIgnoreCase);

    public List<string> AvailabilityCheckedPaths { get; } = [];

    public List<string> LoadedPaths { get; } = [];

    public List<int> ImageLoadThreadIds { get; } = [];

    public List<string> CopiedImagePaths { get; } = [];

    public List<string> CopiedTexts { get; } = [];

    public List<string> SavedImagePaths { get; } = [];

    public List<string> RevealedImagePaths { get; } = [];

    public ScreenshotAssetAvailability GetAssetAvailability(string absolutePath)
    {
        AvailabilityCheckedPaths.Add(absolutePath);
        return AvailabilityFor(absolutePath);
    }

    public ScreenshotImageLoadResult LoadImage(string absolutePath)
    {
        ImageLoadThreadIds.Add(Environment.CurrentManagedThreadId);
        LoadedPaths.Add(absolutePath);
        var availability = AvailabilityFor(absolutePath);
        return availability == ScreenshotAssetAvailability.Available
            ? new ScreenshotImageLoadResult(
                CreateDistinctImages || ReturnUnfrozenImages
                    ? CreateBitmap(freeze: !ReturnUnfrozenImages)
                    : AvailableBitmap,
                availability)
            : new ScreenshotImageLoadResult(null, availability);
    }

    public Task CopyImageAsync(string absolutePath, CancellationToken cancellationToken)
    {
        CopiedImagePaths.Add(absolutePath);
        return Task.CompletedTask;
    }

    public Task CopyTextAsync(string text, CancellationToken cancellationToken)
    {
        CopiedTexts.Add(text);
        return Task.CompletedTask;
    }

    public Task<bool> SaveImageAsAsync(
        string absolutePath,
        string suggestedFileName,
        CancellationToken cancellationToken)
    {
        SavedImagePaths.Add(absolutePath);
        return Task.FromResult(true);
    }

    public Task RevealInExplorerAsync(string absolutePath, CancellationToken cancellationToken)
    {
        RevealedImagePaths.Add(absolutePath);
        return Task.CompletedTask;
    }

    public Task<bool> ConfirmDeleteAsync(
        string title,
        string message,
        CancellationToken cancellationToken) => Task.FromResult(ConfirmDelete);

    private static BitmapSource CreateBitmap(bool freeze = true)
    {
        byte[] pixels = [0, 0, 0, 255];
        var bitmap = BitmapSource.Create(
            1,
            1,
            96,
            96,
            PixelFormats.Bgra32,
            null,
            pixels,
            4);
        if (freeze)
        {
            bitmap.Freeze();
        }
        return bitmap;
    }

    private ScreenshotAssetAvailability AvailabilityFor(string absolutePath) =>
        AssetAvailabilityByPath.TryGetValue(absolutePath, out var availability)
            ? availability
            : ImageAvailability;
}

internal sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => utcNow;
}
