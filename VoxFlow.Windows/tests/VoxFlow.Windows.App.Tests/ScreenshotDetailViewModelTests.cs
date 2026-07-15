using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotDetailViewModelTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 8, 30, 0, TimeSpan.Zero);

    [Fact]
    public async Task Projects_persisted_images_metadata_and_all_text_sections()
    {
        var record = new VoxFlow.Windows.Application.Screenshot.ScreenshotRecord(
            "shot-detail",
            "Screenshots/shot-detail-original.png",
            "Screenshots/shot-detail.png",
            "Screenshots/shot-detail-thumbnail.png",
            2560,
            1440,
            512_000,
            "OCR text",
            Now,
            translatedImagePath: "Screenshots/shot-detail-translated.png",
            sourceDisplayId: "DISPLAY1",
            sourceWindowTitle: "Editor",
            refinedText: "Refined text",
            translatedText: "Translated text",
            summaryText: "Summary text",
            isFavorite: true);
        var repository = new MemoryScreenshotRepository([record]);
        var platform = new CapturingScreenshotMediaPlatform();

        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
        await viewModel.RefreshAsync();

        Assert.True(viewModel.HasImage);
        Assert.True(viewModel.HasTranslatedImage);
        Assert.Equal("2026-07-14 08:30", viewModel.CreatedAtText);
        Assert.Equal("2560 × 1440", viewModel.ResolutionText);
        Assert.Equal("OCR text", viewModel.OcrText);
        Assert.Equal("Refined text", viewModel.RefinedText);
        Assert.Equal("Translated text", viewModel.TranslatedText);
        Assert.Equal("Summary text", viewModel.SummaryText);
        Assert.Equal("Editor", viewModel.SourceWindowTitle);
        Assert.True(viewModel.IsFavorite);
    }

    [Fact]
    public async Task Copy_save_reveal_and_reprocess_use_the_current_detail_selection()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(
            1,
            Now,
            ocrText: "Original OCR",
            translatedText: "Current translation");
        var repository = new MemoryScreenshotRepository([record]);
        var platform = new CapturingScreenshotMediaPlatform();
        var cache = new ScreenshotTransformCache();
        var cachedRequest = TransformRequest(record.Id);
        cache.Store(cachedRequest, "cached transform");
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            cache);
        await viewModel.RefreshAsync();
        viewModel.SelectTextSection(ScreenshotDetailTextSection.Translation);
        var reprocessed = string.Empty;
        viewModel.ReprocessRequested += (_, id) => reprocessed = id;

        await viewModel.ExecuteAsync(ScreenshotMediaActions.CopyText);
        await viewModel.ExecuteAsync(ScreenshotMediaActions.CopyImage);
        await viewModel.ExecuteAsync(ScreenshotMediaActions.SaveAs);
        await viewModel.ExecuteAsync(ScreenshotMediaActions.Reveal);
        await viewModel.ExecuteAsync(ScreenshotMediaActions.Reprocess);

        Assert.Equal(["Current translation"], platform.CopiedTexts);
        Assert.Single(platform.CopiedImagePaths);
        Assert.Single(platform.SavedImagePaths);
        Assert.Single(platform.RevealedImagePaths);
        Assert.Equal(record.Id, reprocessed);
        Assert.False(cache.TryGet(cachedRequest, out _));
    }

    [Fact]
    public async Task Reprocess_requires_the_same_rendered_asset_used_by_the_ocr_pipeline()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        var assets = new FakeScreenshotAssetStore();
        var renderedPath = assets.ResolveAbsolutePath(record.RenderedImagePath);
        var originalPath = assets.ResolveAbsolutePath(record.OriginalImagePath);
        var platform = new CapturingScreenshotMediaPlatform();
        platform.AssetAvailabilityByPath[renderedPath] = ScreenshotAssetAvailability.Missing;
        platform.AssetAvailabilityByPath[originalPath] = ScreenshotAssetAvailability.Available;
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            assets,
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
        var requests = 0;
        viewModel.ReprocessRequested += (_, _) => requests++;

        await viewModel.RefreshAsync();
        await viewModel.ExecuteAsync(ScreenshotMediaActions.Reprocess);

        Assert.True(viewModel.HasImage);
        Assert.False(viewModel.CanReprocess);
        Assert.Equal(0, requests);
        Assert.Equal(L10n.Localize("ScreenshotReprocessUnavailable"), viewModel.Feedback);
    }

    [Fact]
    public async Task Reprocess_remains_available_when_rendered_asset_exists_but_raw_capture_is_missing()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        var assets = new FakeScreenshotAssetStore();
        var renderedPath = assets.ResolveAbsolutePath(record.RenderedImagePath);
        var originalPath = assets.ResolveAbsolutePath(record.OriginalImagePath);
        var platform = new CapturingScreenshotMediaPlatform();
        platform.AssetAvailabilityByPath[renderedPath] = ScreenshotAssetAvailability.Available;
        platform.AssetAvailabilityByPath[originalPath] = ScreenshotAssetAvailability.Missing;
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            assets,
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
        var requestedId = string.Empty;
        viewModel.ReprocessRequested += (_, id) => requestedId = id;

        await viewModel.RefreshAsync();
        await viewModel.ExecuteAsync(ScreenshotMediaActions.Reprocess);

        Assert.True(viewModel.CanReprocess);
        Assert.Equal(record.Id, requestedId);
    }

    [Fact]
    public async Task Missing_assets_keep_text_visible_disable_image_actions_and_allow_record_cleanup()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(
            1,
            Now,
            ocrText: "Text survives missing files");
        var repository = new MemoryScreenshotRepository([record]);
        var platform = new CapturingScreenshotMediaPlatform
        {
            ImageAvailability = ScreenshotAssetAvailability.Missing,
            ConfirmDelete = true,
        };
        var cache = new ScreenshotTransformCache();
        var cachedRequest = TransformRequest(record.Id);
        cache.Store(cachedRequest, "cached transform");
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            cache);
        await viewModel.RefreshAsync();

        await viewModel.ExecuteAsync(ScreenshotMediaActions.CopyImage);
        await viewModel.ExecuteAsync(ScreenshotMediaActions.CopyText);
        await viewModel.ExecuteAsync(ScreenshotMediaActions.Delete);

        Assert.False(viewModel.HasImage);
        Assert.False(viewModel.CanCopyImage);
        Assert.Equal("Text survives missing files", Assert.Single(platform.CopiedTexts));
        Assert.Empty(platform.CopiedImagePaths);
        Assert.True(viewModel.IsDeleted);
        Assert.Null(repository.Get(record.Id));
        Assert.False(cache.TryGet(cachedRequest, out _));
    }

    [Fact]
    public async Task Cancelled_detail_delete_keeps_the_record_and_window_open()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        var platform = new CapturingScreenshotMediaPlatform { ConfirmDelete = false };
        var cache = new ScreenshotTransformCache();
        var cachedRequest = TransformRequest(record.Id);
        cache.Store(cachedRequest, "cached transform");
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            cache);
        await viewModel.RefreshAsync();
        var closeRequests = 0;
        viewModel.CloseRequested += (_, _) => closeRequests++;

        await viewModel.ExecuteAsync(ScreenshotMediaActions.Delete);

        Assert.NotNull(repository.Get(record.Id));
        Assert.False(viewModel.IsDeleted);
        Assert.Equal(0, closeRequests);
        Assert.True(cache.TryGet(cachedRequest, out _));
    }

    [Fact]
    public async Task Record_update_refreshes_an_open_detail_without_recreating_it()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(1, Now, ocrText: "OCR");
        var repository = new MemoryScreenshotRepository([record]);
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            new CapturingScreenshotMediaPlatform(),
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
        await viewModel.RefreshAsync();
        repository.UpdateTransform(
            record.Id,
            VoxFlow.Windows.Application.Screenshot.ScreenshotTransformOperation.Summary,
            "Fresh summary",
            Now.AddSeconds(1));

        await viewModel.NotifyRecordUpdatedAsync(record.Id);

        Assert.Equal("Fresh summary", viewModel.SummaryText);
    }

    [Fact]
    public async Task Refresh_preserves_the_translated_image_selection_with_new_bitmap_instances()
    {
        var record = new VoxFlow.Windows.Application.Screenshot.ScreenshotRecord(
            "shot-translated-refresh",
            "Screenshots/shot-translated-refresh-original.png",
            "Screenshots/shot-translated-refresh.png",
            "Screenshots/shot-translated-refresh-thumbnail.png",
            1200,
            800,
            240_000,
            "OCR",
            Now,
            translatedImagePath: "Screenshots/shot-translated-refresh-translated.png");
        var repository = new MemoryScreenshotRepository([record]);
        var platform = new CapturingScreenshotMediaPlatform
        {
            CreateDistinctImages = true,
        };
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
        await viewModel.RefreshAsync();
        viewModel.ShowTranslation();
        var previousTranslation = viewModel.DisplayedImage;

        await viewModel.RefreshAsync();

        Assert.NotNull(viewModel.TranslatedImage);
        Assert.NotSame(previousTranslation, viewModel.TranslatedImage);
        Assert.Same(viewModel.TranslatedImage, viewModel.DisplayedImage);
    }

    [Fact]
    public void Refresh_reads_records_resolves_paths_and_freezes_decoded_images_off_the_caller_thread()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        var assets = new FakeScreenshotAssetStore();
        var platform = new CapturingScreenshotMediaPlatform
        {
            ReturnUnfrozenImages = true,
        };
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            assets,
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
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
        Assert.NotEqual(callerThreadId, repository.LastGetThreadId);
        Assert.NotEmpty(assets.ResolveThreadIds);
        Assert.All(
            assets.ResolveThreadIds,
            threadId => Assert.NotEqual(callerThreadId, threadId));
        Assert.NotEmpty(platform.ImageLoadThreadIds);
        Assert.All(
            platform.ImageLoadThreadIds,
            threadId => Assert.NotEqual(callerThreadId, threadId));
        Assert.NotNull(viewModel.OriginalImage);
        Assert.True(viewModel.OriginalImage.IsFrozen);
    }

    [Fact]
    public async Task Late_detail_refresh_cannot_overwrite_a_newer_generation()
    {
        var record = ScreenshotMediaPageViewModelTests.Record(1, Now);
        var repository = new MemoryScreenshotRepository([record]);
        Assert.True(repository.UpdateTransform(
            record.Id,
            VoxFlow.Windows.Application.Screenshot.ScreenshotTransformOperation.Summary,
            "Old summary",
            Now));
        var platform = new BlockingFirstImageLoadPlatform();
        var viewModel = new ScreenshotDetailViewModel(
            record.Id,
            repository,
            new FakeScreenshotAssetStore(),
            platform,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc);
        var oldRefresh = viewModel.RefreshAsync();
        await platform.FirstImageLoadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.True(repository.UpdateTransform(
            record.Id,
            VoxFlow.Windows.Application.Screenshot.ScreenshotTransformOperation.Summary,
            "Fresh summary",
            Now.AddSeconds(1)));

        var newRefresh = viewModel.RefreshAsync();
        try
        {
            await newRefresh.WaitAsync(TimeSpan.FromSeconds(2));
            Assert.Equal("Fresh summary", viewModel.SummaryText);
        }
        finally
        {
            platform.ReleaseFirstImageLoad.TrySetResult();
        }

        await oldRefresh.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Equal("Fresh summary", viewModel.SummaryText);
        Assert.False(viewModel.IsLoading);
    }

    private static ScreenshotTransformRequest TransformRequest(string screenshotId) => new(
        Guid.Parse("22222222-2222-2222-2222-222222222222"),
        screenshotId,
        "OCR text",
        ScreenshotTransformOperation.Summary,
        "image-revision");

    private sealed class BlockingFirstImageLoadPlatform : IScreenshotMediaPlatform
    {
        private static readonly BitmapSource Image = CreateImage();
        private int imageLoadCount;

        public TaskCompletionSource FirstImageLoadStarted { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource ReleaseFirstImageLoad { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ScreenshotAssetAvailability GetAssetAvailability(string absolutePath) =>
            ScreenshotAssetAvailability.Available;

        public ScreenshotImageLoadResult LoadImage(string absolutePath)
        {
            if (Interlocked.Increment(ref imageLoadCount) == 1)
            {
                FirstImageLoadStarted.TrySetResult();
                ReleaseFirstImageLoad.Task.GetAwaiter().GetResult();
            }
            return new ScreenshotImageLoadResult(
                Image,
                ScreenshotAssetAvailability.Available);
        }

        public Task CopyImageAsync(string absolutePath, CancellationToken cancellationToken) =>
            Task.CompletedTask;

        public Task CopyTextAsync(string text, CancellationToken cancellationToken) =>
            Task.CompletedTask;

        public Task<bool> SaveImageAsAsync(
            string absolutePath,
            string suggestedFileName,
            CancellationToken cancellationToken) => Task.FromResult(true);

        public Task RevealInExplorerAsync(
            string absolutePath,
            CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<bool> ConfirmDeleteAsync(
            string title,
            string message,
            CancellationToken cancellationToken) => Task.FromResult(true);

        private static BitmapSource CreateImage()
        {
            byte[] pixels = [0, 0, 0, 255];
            var image = BitmapSource.Create(
                1,
                1,
                96,
                96,
                PixelFormats.Bgra32,
                null,
                pixels,
                4);
            image.Freeze();
            return image;
        }
    }
}
