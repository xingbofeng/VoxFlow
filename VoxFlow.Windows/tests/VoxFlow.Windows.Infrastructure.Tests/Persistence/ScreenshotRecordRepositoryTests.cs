using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class ScreenshotRecordRepositoryTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 13, 8, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Stable_paging_orders_equal_timestamps_by_id_without_duplicates()
    {
        using var fixture = new RepositoryFixture();
        foreach (var id in new[] { "c", "a", "e", "b", "d" })
        {
            fixture.Repository.Add(Record(id, createdAtUtc: Now));
        }

        var first = fixture.Repository.Search(new(null, favoritesOnly: false, offset: 0, limit: 2));
        var second = fixture.Repository.Search(new(null, favoritesOnly: false, offset: 2, limit: 2));
        var third = fixture.Repository.Search(new(null, favoritesOnly: false, offset: 4, limit: 2));

        Assert.Equal(["a", "b"], first.Items.Select(item => item.Id));
        Assert.Equal(["c", "d"], second.Items.Select(item => item.Id));
        Assert.Equal(["e"], third.Items.Select(item => item.Id));
        Assert.All([first, second, third], page => Assert.Equal(5, page.TotalCount));
    }

    [Fact]
    public void Search_normalizes_width_and_case_and_covers_all_text_fields()
    {
        using var fixture = new RepositoryFixture();
        fixture.Repository.Add(Record(
            "ocr",
            ocrText: "ＡＢＣ release",
            refinedText: "refined wording"));
        fixture.Repository.Add(Record(
            "translation",
            translatedText: "Translated Needle"));
        fixture.Repository.Add(Record(
            "summary",
            summaryText: "Final Action Item"));

        Assert.Equal(["ocr"], SearchIds(fixture, "abc RELEASE"));
        Assert.Equal(["ocr"], SearchIds(fixture, "REFINED"));
        Assert.Equal(["translation"], SearchIds(fixture, "translated needle"));
        Assert.Equal(["summary"], SearchIds(fixture, "action item"));
        Assert.Empty(SearchIds(fixture, "'); DROP TABLE screenshot_records; --"));
        Assert.Equal(3, fixture.Repository.Search(new(null, false, 0, 20)).TotalCount);
    }

    [Fact]
    public void Favorites_soft_delete_and_stats_are_persistent_and_exclude_deleted_rows()
    {
        using var fixture = new RepositoryFixture();
        fixture.Repository.Add(Record("one", fileSizeBytes: 100, ocrText: "hello"));
        fixture.Repository.Add(Record("two", fileSizeBytes: 250, ocrText: "world"));

        Assert.True(fixture.Repository.SetFavorite("two", true, Now.AddMinutes(1)));
        Assert.Equal(["two"], fixture.Repository.Search(new(null, true, 0, 20)).Items.Select(x => x.Id));
        Assert.Equal(new ScreenshotRecordStats(2, 1, 350, 10), fixture.Repository.GetStats());

        Assert.True(fixture.Repository.SoftDelete("one", Now.AddMinutes(2)));
        Assert.False(fixture.Repository.SoftDelete("one", Now.AddMinutes(3)));
        Assert.Null(fixture.Repository.Get("one"));
        Assert.NotNull(fixture.Repository.Get("one", includeDeleted: true));
        Assert.Equal(new ScreenshotRecordStats(1, 1, 250, 5), fixture.Repository.GetStats());

        fixture.Reopen();
        Assert.True(fixture.Repository.Get("two")!.IsFavorite);
        Assert.Null(fixture.Repository.Get("one"));
    }

    [Fact]
    public void Aggregate_applies_search_and_favorite_filters_with_half_open_utc_day_bounds()
    {
        using var fixture = new RepositoryFixture();
        var localDayStartUtc = new DateTimeOffset(
            2026,
            7,
            14,
            7,
            0,
            0,
            TimeSpan.Zero);
        var localDayEndUtc = localDayStartUtc.AddDays(1);
        fixture.Repository.Add(Record(
            "before",
            createdAtUtc: localDayStartUtc.AddMilliseconds(-1),
            ocrText: "needle before",
            isFavorite: true));
        fixture.Repository.Add(Record(
            "start",
            createdAtUtc: localDayStartUtc,
            ocrText: "needle start"));
        fixture.Repository.Add(Record(
            "inside-favorite",
            createdAtUtc: localDayEndUtc.AddMilliseconds(-1),
            ocrText: "needle inside",
            isFavorite: true));
        fixture.Repository.Add(Record(
            "end",
            createdAtUtc: localDayEndUtc,
            ocrText: "needle end",
            isFavorite: true));
        fixture.Repository.Add(Record(
            "other-text",
            createdAtUtc: localDayStartUtc.AddHours(1),
            ocrText: "haystack",
            isFavorite: true));

        var allNeedles = fixture.Repository.GetAggregate(new ScreenshotRecordAggregateQuery(
            "ＮＥＥＤＬＥ",
            favoritesOnly: false,
            localDayStartUtc,
            localDayEndUtc));
        var favoriteNeedles = fixture.Repository.GetAggregate(new ScreenshotRecordAggregateQuery(
            "needle",
            favoritesOnly: true,
            localDayStartUtc,
            localDayEndUtc));
        var injected = fixture.Repository.GetAggregate(new ScreenshotRecordAggregateQuery(
            "'); DROP TABLE screenshot_records; --",
            favoritesOnly: false,
            localDayStartUtc,
            localDayEndUtc));

        Assert.Equal(new ScreenshotRecordAggregate(4, 2, 3), allNeedles);
        Assert.Equal(new ScreenshotRecordAggregate(3, 1, 3), favoriteNeedles);
        Assert.Equal(new ScreenshotRecordAggregate(0, 0, 0), injected);
        Assert.Equal(5, fixture.Repository.Search(new(null, false, 0, 20)).TotalCount);
    }

    [Fact]
    public void Retention_queries_include_soft_deleted_references_until_guarded_purge()
    {
        using var fixture = new RepositoryFixture();
        fixture.Repository.Add(Record("active"));
        fixture.Repository.Add(Record(
            "expired",
            translatedImagePath: "Screenshots/expired/expired-translated.png"));
        fixture.Repository.Add(Record("recent"));
        Assert.True(fixture.Repository.SoftDelete("expired", Now.AddDays(1)));
        Assert.True(fixture.Repository.SoftDelete("recent", Now.AddDays(2)));
        var cutoff = Now.AddDays(1).AddHours(12);

        var expired = fixture.Repository.ListDeletedBefore(cutoff);
        var referencesBeforePurge = fixture.Repository.ListReferencedAssetPaths();

        Assert.Equal(["expired"], expired.Select(record => record.Id));
        Assert.Contains("Screenshots/active/active.png", referencesBeforePurge);
        Assert.Contains("Screenshots/expired/expired.png", referencesBeforePurge);
        Assert.Contains(
            "Screenshots/expired/expired-translated.png",
            referencesBeforePurge);
        Assert.Contains("Screenshots/recent/recent.png", referencesBeforePurge);
        Assert.False(fixture.Repository.PurgeDeleted("recent", cutoff));
        Assert.True(fixture.Repository.PurgeDeleted("expired", cutoff));
        Assert.Null(fixture.Repository.Get("expired", includeDeleted: true));
        Assert.DoesNotContain(
            "Screenshots/expired/expired.png",
            fixture.Repository.ListReferencedAssetPaths());
    }

    [Fact]
    public void Successful_transform_updates_only_one_field_and_refreshes_search_atomically()
    {
        using var fixture = new RepositoryFixture();
        fixture.Repository.Add(Record(
            "record",
            ocrText: "original OCR",
            translatedText: "old translation",
            summaryText: "existing summary"));

        Assert.True(fixture.Repository.UpdateTransform(
            "record",
            ScreenshotTransformOperation.Translation,
            "new translated value",
            Now.AddMinutes(1),
            "Screenshots/record/record-translated.png"));

        var updated = fixture.Repository.Get("record")!;
        Assert.Equal("original OCR", updated.OcrText);
        Assert.Equal("new translated value", updated.TranslatedText);
        Assert.Equal("existing summary", updated.SummaryText);
        Assert.Equal("Screenshots/record/record-translated.png", updated.TranslatedImagePath);
        Assert.Equal(["record"], SearchIds(fixture, "new translated"));
        Assert.Empty(SearchIds(fixture, "old translation"));

        Assert.Throws<ArgumentException>(() => fixture.Repository.UpdateTransform(
            "record",
            ScreenshotTransformOperation.Translation,
            "  ",
            Now.AddMinutes(2)));
        Assert.Equal("new translated value", fixture.Repository.Get("record")!.TranslatedText);
    }

    [Fact]
    public void Reprocessed_ocr_updates_search_and_invalidates_all_derived_content()
    {
        using var fixture = new RepositoryFixture();
        fixture.Repository.Add(Record(
            "record",
            ocrText: "old OCR",
            refinedText: "kept refinement",
            translatedText: "kept translation",
            summaryText: "kept summary",
            translatedImagePath: "Screenshots/record/record-translated.png"));

        Assert.True(fixture.Repository.ReplaceOcrAndInvalidateTransforms(
            "record",
            "  refreshed OCR text  ",
            Now.AddMinutes(1)));

        var updated = fixture.Repository.Get("record")!;
        Assert.Equal("refreshed OCR text", updated.OcrText);
        Assert.Null(updated.RefinedText);
        Assert.Null(updated.TranslatedText);
        Assert.Null(updated.SummaryText);
        Assert.Null(updated.TranslatedImagePath);
        Assert.Equal("refreshed OCR text".Length, updated.CharacterCount);
        Assert.Equal(["record"], SearchIds(fixture, "refreshed OCR"));
        Assert.Empty(SearchIds(fixture, "old OCR"));
        Assert.Empty(SearchIds(fixture, "kept refinement"));
        Assert.Empty(SearchIds(fixture, "kept translation"));
        Assert.Empty(SearchIds(fixture, "kept summary"));
    }

    [Fact]
    public void Record_rejects_absolute_agent_and_traversal_paths()
    {
        Assert.Throws<ArgumentException>(() => Record(
            "absolute",
            renderedImagePath: @"C:\Users\Fixture\AgentRuntime\capture.png"));
        Assert.Throws<ArgumentException>(() => Record(
            "agent",
            renderedImagePath: "AgentRuntime/sessions/capture.png"));
        Assert.Throws<ArgumentException>(() => Record(
            "escape",
            renderedImagePath: "Screenshots/../capture.png"));
    }

    private static string[] SearchIds(RepositoryFixture fixture, string searchText) =>
        [.. fixture.Repository.Search(new(searchText, false, 0, 20)).Items.Select(item => item.Id)];

    private static ScreenshotRecord Record(
        string id,
        DateTimeOffset? createdAtUtc = null,
        string ocrText = "",
        string? refinedText = null,
        string? translatedText = null,
        string? summaryText = null,
        long fileSizeBytes = 10,
        string? renderedImagePath = null,
        string? translatedImagePath = null,
        bool isFavorite = false) => new(
            id,
            $"Screenshots/{id}/{id}-original.png",
            renderedImagePath ?? $"Screenshots/{id}/{id}.png",
            $"Screenshots/{id}/{id}-thumbnail.png",
            widthPixels: 1200,
            heightPixels: 800,
            fileSizeBytes,
            ocrText,
            createdAtUtc ?? Now,
            translatedImagePath: translatedImagePath,
            refinedText: refinedText,
            translatedText: translatedText,
            summaryText: summaryText,
            isFavorite: isFavorite);

    private sealed class RepositoryFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly string databasePath;
        private SqliteTransactionRunner runner;

        public RepositoryFixture()
        {
            databasePath = Path.Combine(directory.Path, "voxflow.db");
            var flags = new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true);
            new VoxFlowDatabaseMigrator(
            [
                .. InteractiveFeatureMigrationCatalog.For(flags),
                .. ScreenshotMigrationCatalog.All(),
            ]).Migrate(databasePath);
            runner = NewRunner();
            Repository = new SqliteScreenshotRecordRepository(runner);
        }

        public SqliteScreenshotRecordRepository Repository { get; private set; }

        public void Reopen()
        {
            runner.Dispose();
            runner = NewRunner();
            Repository = new SqliteScreenshotRecordRepository(runner);
        }

        public void Dispose()
        {
            runner.Dispose();
            directory.Dispose();
        }

        private SqliteTransactionRunner NewRunner() => new(
            new SqliteConnectionFactory(databasePath, pooling: false));
    }
}
