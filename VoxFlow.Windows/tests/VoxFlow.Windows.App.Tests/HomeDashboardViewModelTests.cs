using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;
using System.Globalization;

namespace VoxFlow.Windows.App.Tests;

public sealed class HomeDashboardViewModelTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Statistics_and_52_week_activity_include_text_dictation_only()
    {
        var entries = new[]
        {
            CreateEntry("qwen-today", "qwen", "原始一", "最终一", Now),
            CreateEntry("tencent-today", "tencent", "raw two", "final two", Now.AddHours(-2)),
            CreateEntry("aliyun-yesterday", "aliyun", "raw three", "final three", Now.AddDays(-1)),
            CreateEntry("excluded", "screenshot", "screen", "screen", Now),
        };
        var viewModel = CreateViewModel(entries);

        viewModel.Reload();

        Assert.Equal(3, viewModel.Statistics.TotalDictations);
        Assert.Equal(2, viewModel.Statistics.TodayDictations);
        Assert.Equal(entries.Take(3).Sum(entry => entry.FinalText.Length),
            viewModel.Statistics.TotalCharacters);
        Assert.Equal(375, viewModel.Statistics.TotalDurationMilliseconds);
        Assert.Equal(52, viewModel.ActivityWeeks.Count);
        Assert.All(viewModel.ActivityWeeks, week => Assert.Equal(7, week.Days.Count));
        Assert.Equal(364, viewModel.ActivityWeeks.Sum(week => week.Days.Count));
        Assert.Equal(3, viewModel.ActivityWeeks.Sum(week => week.Days.Sum(day => day.Count)));
        Assert.Equal(DateOnly.FromDateTime(Now.UtcDateTime.Date),
            viewModel.ActivityWeeks[^1].Days[^1].Date);
        Assert.Equal(
            [
                HomeTextSourceFilter.All,
                HomeTextSourceFilter.Qwen,
                HomeTextSourceFilter.TencentCloud,
                HomeTextSourceFilter.AliyunDashScope,
                HomeTextSourceFilter.Volcengine,
            ],
            viewModel.SourceFilters);
        Assert.DoesNotContain(
            Enum.GetNames<HomeTextSourceFilter>(),
            name => name.Contains("screenshot", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Text_source_search_and_pagination_compose_and_reset_to_page_one()
    {
        var entries = Enumerable.Range(0, 25)
            .Select(index => CreateEntry(
                $"qwen-{index:D2}",
                "qwen",
                $"raw {index}",
                index == 17 ? "contains NEEDLE" : $"final {index}",
                Now.AddMinutes(-index)))
            .Concat(Enumerable.Range(0, 3).Select(index => CreateEntry(
                $"tencent-{index}",
                "tencent",
                $"cloud raw {index}",
                $"cloud final {index}",
                Now.AddHours(-index))))
            .Append(CreateEntry("excluded", "clipboard", "needle", "needle", Now))
            .ToArray();
        var viewModel = CreateViewModel(entries, pageSize: 10);
        viewModel.Reload();

        Assert.Equal(28, viewModel.TotalFilteredCount);
        Assert.Equal(3, viewModel.TotalPages);
        Assert.Equal(10, viewModel.VisibleEntries.Count);

        viewModel.GoToPage(3);
        Assert.Equal(3, viewModel.CurrentPage);

        viewModel.SetSourceFilter(HomeTextSourceFilter.Qwen);
        Assert.Equal(1, viewModel.CurrentPage);
        Assert.Equal(25, viewModel.TotalFilteredCount);

        viewModel.SearchText = "needle";
        Assert.Equal(1, viewModel.CurrentPage);
        Assert.Equal(["qwen-17"], viewModel.VisibleEntries.Select(item => item.Id));

        viewModel.SearchText = " RAW 2 ";
        Assert.Contains(viewModel.VisibleEntries, item => item.Id == "qwen-02");
        Assert.DoesNotContain(viewModel.VisibleEntries, item => item.Id.StartsWith("tencent"));
    }

    [Fact]
    public void Copy_delete_batch_delete_and_clear_refresh_all_dashboard_projections()
    {
        var store = new InMemoryHistoryStore(
            Enumerable.Range(0, 5)
                .Select(index => CreateEntry(
                    $"item-{index}",
                    "qwen",
                    $"raw-{index}",
                    $"final-{index}",
                    Now.AddMinutes(-index))));
        var clipboard = new CapturingClipboardWriter();
        var viewModel = new HomeDashboardViewModel(
            store,
            clipboard,
            new ControlledTimeProvider(Now),
            pageSize: 2);
        viewModel.Reload();

        viewModel.CopyEntry("item-0");
        Assert.Equal("final-0", clipboard.LastText);

        Assert.True(viewModel.DeleteEntry("item-0"));
        Assert.Equal(4, viewModel.Statistics.TotalDictations);
        Assert.Equal(2, viewModel.TotalPages);

        viewModel.ToggleSelection("item-1");
        viewModel.ToggleSelection("item-2");
        Assert.Equal(2, viewModel.DeleteSelected());
        Assert.Empty(viewModel.SelectedEntryIds);
        Assert.Equal(["item-3", "item-4"], store.ReadAll().Select(entry => entry.Id));

        Assert.Equal(2, viewModel.ClearAll());
        Assert.Empty(viewModel.VisibleEntries);
        Assert.Equal(0, viewModel.Statistics.TotalDictations);
        Assert.Equal(1, viewModel.CurrentPage);
        Assert.Equal(1, viewModel.TotalPages);
    }

    [Fact]
    public void Detail_contains_typed_processing_metadata_and_copyable_sanitized_diagnostics()
    {
        var entry = CreateEntry("detail", "qwen", "private raw", "private final", Now) with
        {
            Metadata = new HistoryMetadata(
                recovered: false,
                capturedFrameCount: 42,
                droppedFrameCount: 2,
                durationMilliseconds: 125,
                errorCode: VoxFlowErrorCode.NetworkFailure,
                asrProvider: AsrProviderId.Qwen,
                qwenVariant: QwenVariant.Qwen06B,
                recognitionLanguage: RecognitionLanguage.ChineseMandarin,
                llmProvider: LlmProviderId.OpenAI,
                llmDurationMilliseconds: 35),
        };
        var clipboard = new CapturingClipboardWriter();
        var viewModel = CreateViewModel([entry], clipboard: clipboard);
        viewModel.Reload();

        Assert.True(viewModel.OpenDetail("detail"));
        var detail = Assert.IsType<HistoryDetailViewModel>(viewModel.SelectedDetail);

        Assert.Equal("private raw", detail.RawText);
        Assert.Equal("private final", detail.FinalText);
        Assert.Equal(AsrProviderId.Qwen, detail.AsrProvider);
        Assert.Equal(QwenVariant.Qwen06B, detail.QwenVariant);
        Assert.Equal(RecognitionLanguage.ChineseMandarin, detail.RecognitionLanguage);
        Assert.Equal(LlmProviderId.OpenAI, detail.LlmProvider);
        Assert.Equal(125, detail.DurationMilliseconds);
        Assert.Equal(35, detail.LlmDurationMilliseconds);
        Assert.DoesNotContain(entry.RawText, detail.SanitizedDiagnostic, StringComparison.Ordinal);
        Assert.DoesNotContain(entry.FinalText, detail.SanitizedDiagnostic, StringComparison.Ordinal);

        viewModel.CopySelectedDiagnostic();
        Assert.Equal(detail.SanitizedDiagnostic, clipboard.LastText);
    }

    [Fact]
    public async Task Detail_edit_and_reprocess_update_the_same_history_record()
    {
        var entry = CreateEntry("editable", "qwen", "raw draft", "old final", Now);
        var store = new InMemoryHistoryStore([entry]);
        var reprocessor = new CapturingHistoryReprocessor("reprocessed final");
        var viewModel = new HomeDashboardViewModel(
            store,
            new CapturingClipboardWriter(),
            new ControlledTimeProvider(Now),
            reprocessor);
        viewModel.Reload();
        viewModel.OpenDetail(entry.Id);

        viewModel.SelectedDetail!.EditedFinalText = "manual edit";
        Assert.True(viewModel.SaveSelectedEdit());
        Assert.Equal("manual edit", store.ReadAll().Single().FinalText);

        await viewModel.ReprocessSelectedAsync(CancellationToken.None);
        Assert.Equal("raw draft", reprocessor.LastRawText);
        Assert.Equal("reprocessed final", store.ReadAll().Single().FinalText);
        Assert.Equal("reprocessed final", viewModel.SelectedDetail!.FinalText);
    }

    [Fact]
    public void Home_and_history_copy_is_complete_in_all_supported_languages()
    {
        string[] keys =
        [
            "HomeStatsTotal",
            "HomeStatsToday",
            "HomeStatsCharacters",
            "HomeStatsDuration",
            "HomeActivityTitle",
            "HistoryTitle",
            "HistorySearchLabel",
            "HistorySourceLabel",
            "HistorySourceAll",
            "HistorySourceQwen",
            "HistorySourceTencent",
            "HistorySourceAliyun",
            "HistorySourceVolcengine",
            "HistoryEmpty",
            "HistorySelect",
            "HistoryCopy",
            "HistoryDetails",
            "HistoryDelete",
            "HistoryDeleteSelected",
            "HistoryClearAll",
            "HistoryPreviousPage",
            "HistoryNextPage",
            "HistoryDetailTitle",
            "HistoryDetailClose",
            "HistoryDetailRawText",
            "HistoryDetailFinalText",
            "HistoryDetailMetadata",
            "HistoryDetailLanguage",
            "HistoryDetailDuration",
            "HistoryDetailLlmDuration",
            "HistoryDetailFrames",
            "HistoryDetailSave",
            "HistoryDetailReprocess",
            "HistoryDetailDiagnostic",
            "HistoryDetailCopyDiagnostic",
        ];
        CultureInfo[] cultures =
        [
            new("en"),
            new("zh-Hans"),
            new("zh-Hant"),
            new("ja"),
            new("ko"),
        ];

        foreach (var culture in cultures)
        {
            foreach (var key in keys)
            {
                var value = L10n.Localize(key, culture);
                Assert.False(string.IsNullOrWhiteSpace(value));
                Assert.NotEqual(key, value);
            }
        }
    }

    private static HomeDashboardViewModel CreateViewModel(
        IEnumerable<HistoryEntry> entries,
        int pageSize = 20,
        CapturingClipboardWriter? clipboard = null) => new(
            new InMemoryHistoryStore(entries),
            clipboard ?? new CapturingClipboardWriter(),
            new ControlledTimeProvider(Now),
            pageSize: pageSize);

    private static HistoryEntry CreateEntry(
        string id,
        string source,
        string rawText,
        string finalText,
        DateTimeOffset createdAt) => new(
            id,
            source,
            rawText,
            finalText,
            new HistoryMetadata(
                recovered: false,
                capturedFrameCount: 42,
                droppedFrameCount: 0,
                durationMilliseconds: 125,
                errorCode: null),
            createdAt);

    private sealed class CapturingClipboardWriter : ITextClipboardWriter
    {
        public string? LastText { get; private set; }

        public void WriteText(string text) => LastText = text;
    }

    private sealed class CapturingHistoryReprocessor(string result) : IHistoryReprocessor
    {
        public string? LastRawText { get; private set; }

        public ValueTask<string> ReprocessAsync(
            string rawText,
            CancellationToken cancellationToken)
        {
            LastRawText = rawText;
            return ValueTask.FromResult(result);
        }
    }

    private sealed class InMemoryHistoryStore(IEnumerable<HistoryEntry> seed) : IHistoryStore
    {
        private readonly List<HistoryEntry> entries = [.. seed];

        public HistoryMaintenanceResult WriteAndPrune(
            HistoryEntry entry,
            DateTimeOffset? deleteBeforeUtcExclusive)
        {
            entries.Add(entry);
            var deleted = deleteBeforeUtcExclusive is null
                ? 0
                : PruneBefore(deleteBeforeUtcExclusive.Value);
            return new HistoryMaintenanceResult(true, deleted);
        }

        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) =>
            entries.RemoveAll(entry => entry.CreatedAtUtc < deleteBeforeUtcExclusive);

        public IReadOnlyList<HistoryEntry> ReadAll() =>
            [.. entries.OrderByDescending(entry => entry.CreatedAtUtc).ThenBy(entry => entry.Id)];

        public int Delete(IReadOnlyCollection<string> ids)
        {
            var set = ids.ToHashSet(StringComparer.Ordinal);
            return entries.RemoveAll(entry => set.Contains(entry.Id));
        }

        public int Clear()
        {
            var count = entries.Count;
            entries.Clear();
            return count;
        }

        public bool UpdateFinalText(string id, string finalText)
        {
            var index = entries.FindIndex(entry => entry.Id == id);
            if (index < 0)
            {
                return false;
            }

            entries[index] = entries[index] with { FinalText = finalText };
            return true;
        }
    }
}
