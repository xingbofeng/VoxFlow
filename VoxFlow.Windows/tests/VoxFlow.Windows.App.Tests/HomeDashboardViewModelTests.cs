using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;
using System.Globalization;
using System.Text.Json;

namespace VoxFlow.Windows.App.Tests;

public sealed class HomeDashboardViewModelTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Statistics_and_52_week_activity_count_all_home_assets()
    {
        var entries = new[]
        {
            CreateEntry("qwen-today", "qwen", "原始一", "最终一", Now),
            CreateEntry("tencent-today", "tencent", "raw two", "final two", Now.AddHours(-2)),
            CreateEntry("aliyun-yesterday", "aliyun", "raw three", "final three", Now.AddDays(-1)),
            CreateEntry("also-counted", "clipboard", "screen", "screen", Now),
        };
        var viewModel = CreateViewModel(entries);

        viewModel.Reload();

        // TotalAssets / TodayAssets / DictationAssets / ScreenshotAssets (mac parity).
        Assert.Equal(4, viewModel.Statistics.TotalAssets);
        Assert.Equal(3, viewModel.Statistics.TodayAssets);
        Assert.Equal(4, viewModel.Statistics.DictationAssets);
        Assert.Equal(0, viewModel.Statistics.ScreenshotAssets);
        Assert.Equal(52, viewModel.ActivityWeeks.Count);
        Assert.All(viewModel.ActivityWeeks, week => Assert.Equal(7, week.Days.Count));
        Assert.Equal(364, viewModel.ActivityWeeks.Sum(week => week.Days.Count));
        Assert.Equal(4, viewModel.ActivityWeeks.Sum(week => week.Days.Sum(day => day.Count)));
        var today = DateOnly.FromDateTime(Now.UtcDateTime.Date);
        var sundayOffset = (7 - (int)today.DayOfWeek) % 7;
        Assert.Equal(today.AddDays(sundayOffset),
            viewModel.ActivityWeeks[^1].Days[^1].Date);
        Assert.Equal(
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
            ],
            viewModel.SourceFilters);
        Assert.Contains(HomeTextSourceFilter.Screenshot, viewModel.SourceFilters);
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
            .Append(CreateEntry("clipboard-asset", "clipboard", "needle", "needle", Now))
            .ToArray();
        var viewModel = CreateViewModel(entries, pageSize: 10);
        viewModel.Reload();

        // macOS keeps unconfigured/agent-style dictation assets visible.
        Assert.Equal(29, viewModel.TotalFilteredCount);
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

        viewModel.SetSourceFilter(HomeTextSourceFilter.All);
        viewModel.SearchText = "needle";
        Assert.Equal(
            new[] { "clipboard-asset", "qwen-17" }.Order(StringComparer.Ordinal),
            viewModel.VisibleEntries.Select(item => item.Id).Order(StringComparer.Ordinal));

        viewModel.SetSourceFilter(HomeTextSourceFilter.Qwen);
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
    public void Unified_home_projection_merges_sort_search_and_page_with_asset_stats()
    {
        var dictationStore = new InMemoryHistoryStore(
        [
            CreateEntry("dictation", "qwen", "dictation raw", "dictation final", Now),
        ]);
        var workflow = new WorkflowTaskRecord(
            "summary",
            WorkflowTaskKind.SelectionSummary,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            Guid.NewGuid(),
            rawText: "selection raw",
            partialText: null,
            finalText: "workflow searchable result",
            providerId: "fixture-provider",
            model: "fixture-model",
            targetJson: null,
            contextJson: null,
            traceJson: null,
            outputJson: null,
            failureJson: null,
            warningsJson: null,
            createdAtUnixMs: Now.AddMinutes(2).ToUnixTimeMilliseconds(),
            updatedAtUnixMs: Now.AddMinutes(2).AddSeconds(1).ToUnixTimeMilliseconds(),
            completedAtUnixMs: Now.AddMinutes(2).AddSeconds(1).ToUnixTimeMilliseconds());
        var file = new FileTranscriptionJob(
            "file-job",
            @"C:\Media\meeting.mp3",
            "meeting.mp3",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            Now.AddMinutes(1).ToUnixTimeMilliseconds(),
            status: FileTranscriptionJobStatus.Completed,
            durationMs: 1_000,
            progress: 1,
            finalText: "file searchable result",
            segmentCount: 1,
            segmentCompleted: 1,
            updatedAtUnixMs: Now.AddMinutes(1).AddSeconds(1).ToUnixTimeMilliseconds(),
            completedAtUnixMs: Now.AddMinutes(1).AddSeconds(1).ToUnixTimeMilliseconds());
        var unified = new UnifiedHistoryQueryService(
            dictationStore,
            new HomeWorkflowRepository([workflow]),
            new HomeFileRepository([file]));
        var viewModel = new HomeDashboardViewModel(
            dictationStore,
            new CapturingClipboardWriter(),
            new ControlledTimeProvider(Now),
            pageSize: 2,
            unifiedHistory: unified);

        viewModel.Reload();

        Assert.Equal(3, viewModel.TotalFilteredCount);
        Assert.Equal(2, viewModel.TotalPages);
        Assert.Equal(
            new[] { "workflow:summary", "file:file-job" },
            viewModel.VisibleEntries.Select(item => item.Id));
        // Stats preserve the macOS breakdown instead of merging every text workflow.
        Assert.Equal(3, viewModel.Statistics.TotalAssets);
        Assert.Equal(1, viewModel.Statistics.DictationAssets);
        Assert.Equal(0, viewModel.Statistics.ScreenshotAssets);
        Assert.Equal(1, viewModel.Statistics.ClipboardAssets);
        Assert.Equal(3, viewModel.Statistics.ReusableAssets);

        viewModel.SearchText = "file searchable";
        Assert.Equal("file:file-job", Assert.Single(viewModel.VisibleEntries).Id);
        viewModel.SearchText = "workflow searchable";
        Assert.Equal("workflow:summary", Assert.Single(viewModel.VisibleEntries).Id);

        Assert.True(viewModel.OpenDetail("workflow:summary"));
        Assert.IsType<WorkflowHistoryDetailViewModel>(viewModel.SelectedDetail);
        Assert.True(viewModel.OpenDetail("file:file-job"));
        Assert.IsType<GenericAssetHistoryDetailViewModel>(viewModel.SelectedDetail);
    }

    [Fact]
    public void Workflow_badges_filters_copy_and_cross_store_batch_delete_are_source_aware()
    {
        var dictationStore = new InMemoryHistoryStore(
        [
            CreateEntry("dictation", "qwen", "dictation raw", "dictation final", Now),
        ]);
        var workflows = new HomeWorkflowRepository(
        [
            WorkflowHistory(
                "translation",
                WorkflowTaskKind.SelectionTranslation,
                "translation raw",
                Now.AddMinutes(3),
                finalText: "translation result"),
            WorkflowHistory(
                "summary",
                WorkflowTaskKind.SelectionSummary,
                "summary raw",
                Now.AddMinutes(2),
                partialText: "summary partial"),
            WorkflowHistory(
                "agent",
                WorkflowTaskKind.AgentCompose,
                "agent voice",
                Now.AddMinutes(1),
                finalText: "agent summary"),
        ]);
        var files = new HomeFileRepository(
        [
            CompletedFile("file-job", Now.AddSeconds(30)),
        ]);
        var unified = new UnifiedHistoryQueryService(dictationStore, workflows, files);
        var clipboard = new CapturingClipboardWriter();
        var viewModel = new HomeDashboardViewModel(
            dictationStore,
            clipboard,
            new ControlledTimeProvider(Now),
            unifiedHistory: unified);
        viewModel.Reload();

        Assert.Contains(HomeTextSourceFilter.SelectionTranslation, viewModel.SourceFilters);
        Assert.Contains(HomeTextSourceFilter.SelectionSummary, viewModel.SourceFilters);
        Assert.Contains(HomeTextSourceFilter.AgentCompose, viewModel.SourceFilters);
        Assert.Contains(HomeTextSourceFilter.FileTranscription, viewModel.SourceFilters);
        var translation = Assert.Single(
            viewModel.VisibleEntries,
            item => item.Kind == UnifiedHistoryKind.SelectionTranslation);
        var summary = Assert.Single(
            viewModel.VisibleEntries,
            item => item.Kind == UnifiedHistoryKind.SelectionSummary);
        var agent = Assert.Single(
            viewModel.VisibleEntries,
            item => item.Kind == UnifiedHistoryKind.AgentCompose);
        Assert.Equal(L10n.Localize("HistorySourceSelectionTranslation"), translation.SourceLabel);
        Assert.Equal(L10n.Localize("HistorySourceSelectionSummary"), summary.SourceLabel);
        Assert.Equal(L10n.Localize("HistorySourceAgentCompose"), agent.SourceLabel);
        Assert.All([translation, summary, agent], item => Assert.True(item.IsWorkflow));
        Assert.Equal("\uE774", translation.WorkflowGlyph);
        Assert.Equal("\uE8A5", summary.WorkflowGlyph);
        Assert.Equal("\uE950", agent.WorkflowGlyph);
        Assert.Equal(L10n.Localize("WorkflowStatusCompleted"), translation.StatusLabel);
        Assert.Equal(L10n.Localize("WorkflowStatusPartiallyCompleted"), summary.StatusLabel);
        Assert.False(translation.IsFailed);
        Assert.Equal("translation raw", translation.RawTextPreview);
        Assert.Equal("translation result", translation.ResultTextPreview);
        Assert.Equal("summary partial", summary.ResultTextPreview);

        viewModel.SetSourceFilter(HomeTextSourceFilter.SelectionSummary);
        Assert.Equal("workflow:summary", Assert.Single(viewModel.VisibleEntries).Id);
        Assert.True(viewModel.CopyEntry("workflow:summary"));
        Assert.Equal("summary partial", clipboard.LastText);

        viewModel.SetSourceFilter(HomeTextSourceFilter.All);
        viewModel.ToggleSelection("dictation");
        viewModel.ToggleSelection("workflow:translation");
        viewModel.ToggleSelection("workflow:agent");
        viewModel.ToggleSelection("file:file-job");
        Assert.Equal(4, viewModel.DeleteSelected());
        Assert.Empty(dictationStore.ReadAll());
        Assert.Null(workflows.Get("translation"));
        Assert.NotNull(workflows.Get("summary"));
        Assert.Null(workflows.Get("agent"));
        Assert.Null(files.Get("file-job"));
    }

    [Fact]
    public void Selection_and_agent_details_project_source_specific_safe_fields()
    {
        var selection = WorkflowHistory(
            "translation-detail",
            WorkflowTaskKind.SelectionTranslation,
            "selected original",
            Now.AddMinutes(1),
            finalText: "translated result",
            failureCode: "provider_timeout");
        var trace = new AgentActionTrace(
            "fixture-provider",
            AgentExecutionMode.BuiltinAgent,
            WorkflowTaskStatus.Completed,
            "agent voice instruction",
            Now.ToUnixTimeMilliseconds(),
            screenContext: new AgentScreenContextMetadata(
                "Visual Studio Code",
                "Code.exe",
                "report.md",
                ["selectedText", "uiaVisibleText"],
                ["ocrSkipped"],
                Now.ToUnixTimeMilliseconds()),
            events:
            [
                new AgentActionEvent(
                    "event-1",
                    AgentActionEventKind.ToolResolved,
                    "文件已写入",
                    "42 bytes",
                    Now.AddSeconds(1).ToUnixTimeMilliseconds(),
                    elapsedMs: 15,
                    toolName: "write_file",
                    isFailure: false),
            ],
            resultSummary: "已创建报告",
            model: "fixture-model",
            artifacts:
            [
                new AgentArtifact(
                    "artifact-1",
                    AgentArtifactKind.File,
                    @"~\report.md",
                    "报告",
                    Now.AddSeconds(1).ToUnixTimeMilliseconds()),
            ],
            completedAtUnixMs: Now.AddSeconds(2).ToUnixTimeMilliseconds());
        var agent = new WorkflowTaskRecord(
            "agent-detail",
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            Guid.NewGuid(),
            rawText: "agent voice instruction",
            partialText: null,
            finalText: "已创建报告",
            providerId: "fixture-provider",
            model: "fixture-model",
            targetJson: null,
            contextJson: JsonSerializer.SerializeToElement(new
            {
                sources = new[] { "selectedText", "uiaVisibleText" },
            }),
            traceJson: JsonSerializer.SerializeToElement(trace, DomainJson.Options),
            outputJson: null,
            failureJson: null,
            warningsJson: null,
            createdAtUnixMs: Now.ToUnixTimeMilliseconds(),
            updatedAtUnixMs: Now.AddSeconds(2).ToUnixTimeMilliseconds(),
            completedAtUnixMs: Now.AddSeconds(2).ToUnixTimeMilliseconds());
        var dictationStore = new InMemoryHistoryStore([]);
        var unified = new UnifiedHistoryQueryService(
            dictationStore,
            new HomeWorkflowRepository([selection, agent]));
        var viewModel = new HomeDashboardViewModel(
            dictationStore,
            new CapturingClipboardWriter(),
            new ControlledTimeProvider(Now),
            unifiedHistory: unified);
        viewModel.Reload();

        Assert.True(viewModel.OpenDetail("workflow:translation-detail"));
        var selectionDetail = Assert.IsType<WorkflowHistoryDetailViewModel>(
            viewModel.SelectedDetail);
        Assert.True(selectionDetail.IsSelection);
        Assert.False(selectionDetail.IsAgent);
        Assert.Equal("selected original", selectionDetail.OriginalText);
        Assert.Equal("translated result", selectionDetail.ResultText);
        Assert.Equal("fixture-provider", selectionDetail.ProviderId);
        Assert.Equal(WorkflowTaskStatus.Completed, selectionDetail.Status);
        Assert.Equal(1_000, selectionDetail.DurationMilliseconds);
        Assert.True(selectionDetail.HasFailure);
        Assert.Equal("provider_timeout", selectionDetail.FailureCode);

        Assert.True(viewModel.OpenDetail("workflow:agent-detail"));
        var agentDetail = Assert.IsType<WorkflowHistoryDetailViewModel>(
            viewModel.SelectedDetail);
        Assert.True(agentDetail.IsAgent);
        Assert.Equal("agent voice instruction", agentDetail.VoiceInstruction);
        Assert.Equal(["selectedText", "uiaVisibleText"], agentDetail.ContextSources);
        Assert.Equal("文件已写入", Assert.Single(agentDetail.Events).Title);
        Assert.Equal("write_file", Assert.Single(agentDetail.ToolNames));
        Assert.Equal(@"~\report.md", Assert.Single(agentDetail.Artifacts).Path);
        Assert.Equal("已创建报告", agentDetail.ResultSummary);
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
        Assert.True(viewModel.IsDetailOpen);
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
    public void Home_action_availability_tracks_empty_selection_and_detail_state()
    {
        var entry = CreateEntry("availability", "qwen", "raw", "final", Now);
        var viewModel = new HomeDashboardViewModel(
            new InMemoryHistoryStore([entry]),
            new CapturingClipboardWriter(),
            new ControlledTimeProvider(Now),
            new CapturingHistoryReprocessor("reprocessed"));

        Assert.False(viewModel.CanClearAll);
        Assert.False(viewModel.CanDeleteSelected);
        viewModel.Reload();
        Assert.True(viewModel.CanClearAll);
        viewModel.ToggleSelection(entry.Id);
        Assert.True(viewModel.CanDeleteSelected);
        Assert.True(viewModel.OpenDetail(entry.Id));
        Assert.True(viewModel.CanSaveSelectedEdit);
        Assert.True(viewModel.CanReprocessSelected);
        viewModel.SelectedDetail!.EditedFinalText = string.Empty;
        Assert.False(viewModel.CanSaveSelectedEdit);
    }

    [Fact]
    public async Task Home_action_failures_are_safe_visible_and_do_not_escape_handlers()
    {
        var entry = CreateEntry("failure", "qwen", "raw", "final", Now);
        var innerStore = new InMemoryHistoryStore([entry]);
        var unified = new UnifiedHistoryQueryService(innerStore);
        var viewModel = new HomeDashboardViewModel(
            new ThrowingUpdateHistoryStore(innerStore),
            new ThrowingClipboardWriter(),
            new ControlledTimeProvider(Now),
            new ThrowingHistoryReprocessor(),
            unifiedHistory: new ThrowingDeleteHistoryService(unified));
        viewModel.Reload();

        Assert.False(viewModel.CopyEntry(entry.Id));
        Assert.Equal(L10n.Localize("HistoryCopyFailed"), viewModel.ActionFeedback);
        Assert.True(viewModel.OpenDetail(entry.Id));
        Assert.False(viewModel.CopySelectedDiagnostic());
        Assert.False(viewModel.SaveSelectedEdit());
        Assert.Equal(L10n.Localize("HistorySaveFailed"), viewModel.ActionFeedback);
        Assert.False(await viewModel.ReprocessSelectedAsync(CancellationToken.None));
        Assert.Equal(
            L10n.Localize("HistoryReprocessFailed"),
            viewModel.ActionFeedback);
        Assert.False(viewModel.DeleteEntry(entry.Id));
        viewModel.ToggleSelection(entry.Id);
        Assert.Equal(0, viewModel.DeleteSelected());
        Assert.Equal(0, viewModel.ClearAll());
        var feedback = Assert.IsType<string>(viewModel.ActionFeedback);
        Assert.Equal(L10n.Localize("HistoryDeleteFailed"), feedback);
        Assert.DoesNotContain(
            "sensitive fixture failure",
            feedback,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Home_reprocess_preserves_cancellation()
    {
        var entry = CreateEntry("cancel", "qwen", "raw", "final", Now);
        var viewModel = new HomeDashboardViewModel(
            new InMemoryHistoryStore([entry]),
            new CapturingClipboardWriter(),
            new ControlledTimeProvider(Now),
            new CancellingHistoryReprocessor());
        viewModel.Reload();
        Assert.True(viewModel.OpenDetail(entry.Id));
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            viewModel.ReprocessSelectedAsync(cancellation.Token).AsTask());

        Assert.False(viewModel.IsReprocessing);
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
            "HistorySourceSelectionTranslation",
            "HistorySourceSelectionSummary",
            "HistorySourceAgentCompose",
            "HistorySourceFileTranscription",
            "HistoryEmpty",
            "HistorySelect",
            "HistoryCopy",
            "HistoryDetails",
            "HistoryDelete",
            "HistoryDeleteSelected",
            "HistoryClearAll",
            "HistoryCopySucceeded",
            "HistoryCopyFailed",
            "HistoryDeleteSucceeded",
            "HistoryDeleteFailed",
            "HistorySaveSucceeded",
            "HistorySaveFailed",
            "HistoryReprocessSucceeded",
            "HistoryReprocessFailed",
            "HistoryActionFailed",
            "HistoryDeleteConfirmationTitle",
            "HistoryDeleteConfirmationMessage",
            "HistoryDeleteSelectedConfirmationMessage",
            "HistoryClearAllConfirmationMessage",
            "HistoryDeleteSelectedUnavailable",
            "HistoryClearAllUnavailable",
            "HistorySaveUnavailable",
            "HistoryReprocessUnavailable",
            "HistoryPreviousPage",
            "HistoryNextPage",
            "HistoryDetailTitle",
            "HistoryNoPreview",
            "HistoryContentTypeVoice",
            "HistoryContentTypeImage",
            "HistoryContentTypeFile",
            "HistoryContentTypeWorkflow",
            "HistoryContentTypeText",
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
            "HistoryDetailWorkflowMetadata",
            "HistoryDetailStatus",
            "HistoryDetailFailure",
            "HistoryDetailProvider",
            "HistoryDetailModel",
            "HistoryDetailContextSources",
            "HistoryDetailTimeline",
            "HistoryDetailTools",
            "HistoryDetailArtifacts",
            "HistoryDetailResultSummary",
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

    private static WorkflowTaskRecord WorkflowHistory(
        string id,
        WorkflowTaskKind kind,
        string rawText,
        DateTimeOffset createdAt,
        string? partialText = null,
        string? finalText = null,
        string? failureCode = null)
    {
        var status = finalText is null
            ? WorkflowTaskStatus.PartiallyCompleted
            : WorkflowTaskStatus.Completed;
        return new WorkflowTaskRecord(
            id,
            kind,
            finalText is null ? WorkflowTaskStage.Processing : WorkflowTaskStage.Completed,
            status,
            Guid.NewGuid(),
            rawText,
            partialText,
            finalText,
            "fixture-provider",
            "fixture-model",
            targetJson: null,
            contextJson: null,
            traceJson: null,
            outputJson: null,
            failureJson: failureCode is null
                ? null
                : JsonSerializer.SerializeToElement(new { code = failureCode }),
            warningsJson: null,
            createdAt.ToUnixTimeMilliseconds(),
            createdAt.AddSeconds(1).ToUnixTimeMilliseconds(),
            createdAt.AddSeconds(1).ToUnixTimeMilliseconds());
    }

    private static FileTranscriptionJob CompletedFile(
        string id,
        DateTimeOffset createdAt) => new(
        id,
        $@"C:\Media\{id}.mp3",
        $"{id}.mp3",
        AsrProviderId.Qwen,
        RecognitionLanguage.Automatic,
        createdAt.ToUnixTimeMilliseconds(),
        FileTranscriptionJobStatus.Completed,
        durationMs: 1_000,
        progress: 1,
        finalText: "file result",
        segmentCount: 1,
        segmentCompleted: 1,
        updatedAtUnixMs: createdAt.AddSeconds(1).ToUnixTimeMilliseconds(),
        completedAtUnixMs: createdAt.AddSeconds(1).ToUnixTimeMilliseconds());

    private sealed class CapturingClipboardWriter : ITextClipboardWriter
    {
        public string? LastText { get; private set; }

        public void WriteText(string text) => LastText = text;
    }

    private sealed class ThrowingClipboardWriter : ITextClipboardWriter
    {
        public void WriteText(string text) =>
            throw new InvalidOperationException("sensitive fixture failure");
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

    private sealed class ThrowingHistoryReprocessor : IHistoryReprocessor
    {
        public ValueTask<string> ReprocessAsync(
            string rawText,
            CancellationToken cancellationToken) =>
            ValueTask.FromException<string>(
                new InvalidOperationException("sensitive fixture failure"));
    }

    private sealed class CancellingHistoryReprocessor : IHistoryReprocessor
    {
        public ValueTask<string> ReprocessAsync(
            string rawText,
            CancellationToken cancellationToken) =>
            ValueTask.FromCanceled<string>(cancellationToken);
    }

    private sealed class ThrowingUpdateHistoryStore(IHistoryStore inner)
        : IHistoryStore
    {
        public HistoryMaintenanceResult WriteAndPrune(
            HistoryEntry entry,
            DateTimeOffset? deleteBeforeUtcExclusive) =>
            inner.WriteAndPrune(entry, deleteBeforeUtcExclusive);

        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) =>
            inner.PruneBefore(deleteBeforeUtcExclusive);

        public IReadOnlyList<HistoryEntry> ReadAll() => inner.ReadAll();

        public int Delete(IReadOnlyCollection<string> ids) => inner.Delete(ids);

        public int Clear() => inner.Clear();

        public bool UpdateFinalText(string id, string finalText) =>
            throw new InvalidOperationException("sensitive fixture failure");
    }

    private sealed class ThrowingDeleteHistoryService(IUnifiedHistoryService inner)
        : IUnifiedHistoryService
    {
        public IReadOnlyList<UnifiedHistoryEntry> ReadAll() => inner.ReadAll();

        public UnifiedHistoryPage Search(UnifiedHistoryQuery query) =>
            inner.Search(query);

        public int Delete(IReadOnlyCollection<string> ids) =>
            throw new InvalidOperationException("sensitive fixture failure");

        public int Clear() =>
            throw new InvalidOperationException("sensitive fixture failure");
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

    private sealed class HomeWorkflowRepository(
        IReadOnlyList<WorkflowTaskRecord> tasks) : IWorkflowTaskRepository
    {
        private readonly List<WorkflowTaskRecord> values = [.. tasks];
        public void Create(WorkflowTaskRecord task) => throw new NotSupportedException();
        public WorkflowTaskRecord? Get(string id) => values.FirstOrDefault(task => task.Id == id);
        public WorkflowTaskPage Search(WorkflowTaskQuery query)
        {
            var page = values.Skip(query.Offset).Take(query.Limit).ToArray();
            return new WorkflowTaskPage(page, values.Count, query.Offset, query.Limit);
        }
        public bool TryUpdate(WorkflowTaskRecord task, Guid expectedGeneration) => false;
        public bool Delete(string id) => values.RemoveAll(task => task.Id == id) == 1;
        public IReadOnlyList<string> ListActiveIds() => [];
        public int PruneTerminalBefore(long cutoffUnixMs) => 0;
        public int MarkActiveAsInterrupted(long interruptedAtUnixMs) => 0;
    }

    private sealed class HomeFileRepository(IReadOnlyList<FileTranscriptionJob> jobs)
        : IFileTranscriptionJobRepository
    {
        private readonly List<FileTranscriptionJob> values = [.. jobs];
        public void Create(FileTranscriptionJob job) => throw new NotSupportedException();
        public FileTranscriptionJob? Get(string id) => values.FirstOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => values.ToArray();
        public bool Update(FileTranscriptionJob job) => false;
        public bool Delete(string id) => values.RemoveAll(job => job.Id == id) == 1;
        public int MarkRunningAsInterrupted() => 0;
    }
}
