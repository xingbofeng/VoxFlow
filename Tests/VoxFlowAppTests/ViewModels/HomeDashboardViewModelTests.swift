import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class HomeDashboardViewModelTests: XCTestCase {
    func testSourceBreakdownSummaryUsesClipboardDisplayName() {
        let breakdown = HomeSourceBreakdown(dictation: 10, screenshot: 126, clipboard: 80)

        XCTAssertEqual(breakdown.summaryText, "语音 10 / 截图 126 / 剪贴板 80")
    }

    func testLoadComputesStatisticsAndGroupedAssets() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "today",
            source: .dictation,
            contentType: .text,
            title: "今天输入文本",
            text: "今天输入文本",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "yesterday",
            source: .dictation,
            contentType: .text,
            title: "昨天输入",
            text: "昨天输入",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.stats.totalAssets, 2)
        XCTAssertEqual(viewModel.stats.focusedAssets, 1)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(dictation: 2))
        XCTAssertEqual(viewModel.stats.reusableAssets, 2)
        XCTAssertEqual(viewModel.assetGroups.map(\.title), ["今天", "昨天"])
        XCTAssertEqual(viewModel.assetGroups.first?.items.map(\.id), ["today"])
    }

    func testLoadBuildsHomeAssetGroupsFromAssetLedger() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "voice",
            source: .dictation,
            contentType: .text,
            title: "语音识别内容",
            text: "语音识别内容",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "screenshot",
            source: .screenshot,
            contentType: .image,
            title: "Image (1200x800)",
            text: "截图里的错误提示",
            imagePath: "/tmp/screenshot.png",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 10)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "clipboard",
            source: .clipboard,
            contentType: .link,
            title: "https://example.com",
            text: "https://example.com",
            url: "https://example.com",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.totalAssetCount, 3)
        XCTAssertEqual(viewModel.assetGroups.map(\.title), ["今天", "昨天"])
        XCTAssertEqual(viewModel.assetGroups.first?.items.map(\.id), ["voice"])
        XCTAssertEqual(viewModel.assetGroups.last?.items.map(\.id), ["screenshot", "clipboard"])
        XCTAssertEqual(viewModel.assetGroups.first?.items.first?.sourceTitle, "语音")
        XCTAssertEqual(viewModel.assetGroups.last?.items.first?.sourceTitle, "截图")
    }

    func testAssetBackedHomeIgnoresLegacyHistoryListData() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(
            id: "legacy-history",
            finalText: "旧首页历史",
            createdAt: now
        ))
        try environment.assetRepository.save(homeAsset(
            id: "dictation-legacy-history",
            source: .dictation,
            contentType: .text,
            title: "旧首页历史",
            text: "旧首页历史",
            createdAt: now
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["dictation-legacy-history"])
    }

    func testLoadComputesStatsFromAssetsWhenAssetLedgerHasMigratedData() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "today-voice",
            source: .dictation,
            contentType: .text,
            title: "今天语音",
            text: "今天语音文本",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "yesterday-clip",
            source: .clipboard,
            contentType: .text,
            title: "昨天复制",
            text: "昨天复制文本",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 10)
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.stats.totalAssets, 2)
        XCTAssertEqual(viewModel.stats.focusedAssets, 1)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(dictation: 1, clipboard: 1))
        XCTAssertEqual(viewModel.stats.reusableAssets, 2)
        XCTAssertEqual(viewModel.activity.thisWeekAssets, 2)
    }

    func testSelectingHomeAssetLoadsPreviewDetailAndDismissesIt() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "screenshot",
            source: .screenshot,
            contentType: .image,
            title: "Image (1200x800)",
            text: "截图预览文字",
            imagePath: "/tmp/screenshot.png",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.selectAssetItem(id: "screenshot")

        XCTAssertEqual(viewModel.selectedAssetDetail?.id, "screenshot")
        XCTAssertEqual(viewModel.selectedAssetDetail?.title, "Image (1200x800)")
        XCTAssertEqual(viewModel.selectedAssetDetail?.previewText, "截图预览文字")
        XCTAssertEqual(viewModel.selectedAssetDetail?.imagePath, "/tmp/screenshot.png")

        viewModel.clearSelectedHomeDetail()

        XCTAssertNil(viewModel.selectedAssetDetail)
    }

    func testDirectHistoryDetailSelectionClearsExistingAssetPreview() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "screenshot",
            source: .screenshot,
            contentType: .image,
            title: "Image (1200x800)",
            text: "截图预览文字",
            imagePath: "/tmp/screenshot.png",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        try environment.historyRepository.save(historyEntry(
            id: "history-voice",
            rawText: "原始录音",
            finalText: "纠正后的录音"
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectAssetItem(id: "screenshot")

        viewModel.selectHistoryItem(id: "history-voice")

        XCTAssertNil(viewModel.selectedAssetDetail)
        XCTAssertEqual(viewModel.selectedDetail?.id, "history-voice")
    }

    func testSelectingDictationAssetOpensRichHistoryDetailInsteadOfAssetPreview() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(
            id: "history-voice",
            rawText: "原始录音",
            finalText: "纠正后的录音"
        ))
        try environment.assetRepository.save(homeAsset(
            id: "dictation-history-voice",
            source: .dictation,
            contentType: .text,
            title: "纠正后的录音",
            text: "纠正后的录音",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.selectAssetItem(id: "dictation-history-voice")

        XCTAssertNil(viewModel.selectedAssetDetail)
        XCTAssertEqual(viewModel.selectedDetail?.id, "history-voice")
        XCTAssertEqual(viewModel.selectedDetail?.rawText, "原始录音")
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "纠正后的录音")
    }

    func testSelectingAgentComposeAssetOpensRichTaskDetailInsteadOfAssetPreview() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "agent-task",
                mode: .agentCompose,
                stage: .outputting,
                status: .completed,
                targetAppName: "微信",
                rawTranscript: "帮我回复今晚可以",
                finalText: "可以，今晚发给你。",
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-agent-task",
            source: .dictation,
            contentType: .text,
            title: "帮我回复今晚可以",
            text: "帮我回复今晚可以",
            createdAt: now
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.selectAssetItem(id: "dictation-agent-task")

        XCTAssertNil(viewModel.selectedAssetDetail)
        XCTAssertEqual(viewModel.selectedDetail?.id, "agent-task")
        XCTAssertEqual(viewModel.selectedDetail?.taskMode, .agentCompose)
        XCTAssertEqual(viewModel.selectedDetail?.rawText, "帮我回复今晚可以")
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "可以，今晚发给你。")
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).first?.sourceTitle, "任务助手")
    }

    func testLoadRepairsMissingAgentComposeAssetFromCompletedVoiceTask() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try insertVoiceTask(
            id: "runtime-agent-task",
            mode: "agentCompose",
            status: "completed",
            text: "帮我打开 Google",
            createdAt: now,
            into: container.databaseQueue
        )

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        let item = try XCTUnwrap(viewModel.assetGroups.flatMap(\.items).first)
        XCTAssertEqual(item.id, "dictation-runtime-agent-task")
        XCTAssertEqual(item.sourceTitle, "任务助手")
        XCTAssertEqual(item.previewText, "帮我打开 Google")
        XCTAssertEqual(try environment.assetRepository.asset(id: "dictation-runtime-agent-task")?.text, "帮我打开 Google")

        viewModel.selectAssetItem(id: "dictation-runtime-agent-task")
        XCTAssertEqual(viewModel.selectedDetail?.id, "runtime-agent-task")
        XCTAssertNil(viewModel.selectedAssetDetail)
    }

    func testSelectingAgentDispatchAssetOpensRichTaskDetailInsteadOfAssetPreview() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "dispatch-task",
                mode: .agentDispatch,
                stage: .outputting,
                status: .completed,
                targetAppName: "Terminal",
                rawTranscript: "让 codex 修复测试",
                finalText: "fix failing tests",
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-dispatch-task",
            source: .dictation,
            contentType: .text,
            title: "让 codex 修复测试",
            text: "让 codex 修复测试",
            createdAt: now
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.selectAssetItem(id: "dictation-dispatch-task")

        XCTAssertNil(viewModel.selectedAssetDetail)
        XCTAssertEqual(viewModel.selectedDetail?.id, "dispatch-task")
        XCTAssertEqual(viewModel.selectedDetail?.taskMode, .agentDispatch)
        XCTAssertEqual(viewModel.selectedDetail?.rawText, "让 codex 修复测试")
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "fix failing tests")
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).first?.sourceTitle, "AI 编程")
    }

    func testDeletingDictationAssetAlsoDeletesLegacyHistoryRecord() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(
            id: "history-voice",
            finalText: "历史语音"
        ))
        try environment.assetRepository.save(homeAsset(
            id: "dictation-history-voice",
            source: .dictation,
            contentType: .text,
            title: "历史语音",
            text: "历史语音",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.deleteAssetItem(id: "dictation-history-voice")

        XCTAssertNil(try environment.assetRepository.asset(id: "dictation-history-voice"))
        XCTAssertNotNil(try environment.historyRepository.entry(id: "history-voice")?.deletedAt)
        XCTAssertTrue(viewModel.assetGroups.flatMap(\.items).isEmpty)
    }

    func testDeletingAgentAssetAlsoDeletesVoiceTask() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "agent-task",
                mode: .agentCompose,
                stage: .outputting,
                status: .completed,
                rawTranscript: "帮我说",
                finalText: "帮我说结果",
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-agent-task",
            source: .dictation,
            contentType: .text,
            title: "帮我说",
            text: "帮我说",
            createdAt: now
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.deleteAssetItem(id: "dictation-agent-task")

        XCTAssertNil(try environment.assetRepository.asset(id: "dictation-agent-task"))
        XCTAssertNil(try taskRepository.fetch(id: "agent-task"))
        XCTAssertTrue(viewModel.assetGroups.flatMap(\.items).isEmpty)
    }

    func testBatchDeleteSelectedAssetsAndClearAllAssets() throws {
        let clock = MutableHomeClock(now: Date(timeIntervalSince1970: 1_800_000_100))
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        for index in 0..<3 {
            try environment.assetRepository.save(homeAsset(
                id: "asset-\(index)",
                source: .clipboard,
                contentType: .text,
                title: "asset \(index)",
                text: "asset \(index)",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
            ))
        }
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.toggleAssetSelection(id: "asset-0")
        viewModel.toggleAssetSelection(id: "asset-1")
        viewModel.deleteSelectedAssets()

        XCTAssertEqual(viewModel.selectedAssetIDs, [])
        XCTAssertEqual(viewModel.stats.totalAssets, 1)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(clipboard: 1))
        XCTAssertEqual(viewModel.stats.reusableAssets, 1)
        XCTAssertEqual(viewModel.totalAssetCount, 1)
        XCTAssertNil(try environment.assetRepository.asset(id: "asset-0"))
        XCTAssertNil(try environment.assetRepository.asset(id: "asset-1"))
        XCTAssertNotNil(try environment.assetRepository.asset(id: "asset-2"))
        XCTAssertEqual(viewModel.lastActionMessage, "已删除 2 条资产")
        XCTAssertEqual(viewModel.lastActionTone, .destructive)

        viewModel.clearAllAssets()

        XCTAssertEqual(viewModel.totalAssetCount, 0)
        XCTAssertEqual(viewModel.stats, HomeDashboardStats())
        XCTAssertTrue(viewModel.assetGroups.isEmpty)
        XCTAssertEqual(viewModel.lastActionMessage, "已清空资产")
    }

    func testSearchFiltersHomeAssetsFromAssetLedger() async throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "voice",
            source: .dictation,
            contentType: .text,
            title: "会议纪要",
            text: "会议纪要",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "screenshot",
            source: .screenshot,
            contentType: .image,
            title: "Image (1200x800)",
            text: "构建失败",
            imagePath: "/tmp/screenshot.png",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.updateSearch("构建")

        await waitUntil {
            viewModel.totalAssetCount == 1
                && viewModel.assetGroups.flatMap(\.items).map(\.id) == ["screenshot"]
        }

        XCTAssertEqual(viewModel.totalAssetCount, 1)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["screenshot"])
    }

    func testContentTypeFilterNarrowsHomeAssetsAndResetsPageState() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "voice",
            source: .dictation,
            contentType: .text,
            title: "语音识别内容",
            text: "语音识别内容",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "screenshot",
            source: .screenshot,
            contentType: .image,
            title: "Image (1200x800)",
            text: "截图里的错误提示",
            imagePath: "/tmp/screenshot.png",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "clipboard-link",
            source: .clipboard,
            contentType: .link,
            title: "https://example.com",
            text: "https://example.com",
            url: "https://example.com",
            createdAt: makeDate(year: 2026, month: 6, day: 6, hour: 9)
        ))
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            calendar: testCalendar,
            historyPageSize: 1
        )
        viewModel.load()
        viewModel.nextAssetPage()
        viewModel.toggleAssetSelection(id: "voice")

        viewModel.updateAssetContentTypeFilter(.image)

        XCTAssertEqual(viewModel.selectedAssetContentTypeFilter, .image)
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        XCTAssertEqual(viewModel.selectedAssetIDs, [])
        XCTAssertEqual(viewModel.totalAssetCount, 1)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["screenshot"])
    }

    func testSourceFilterNarrowsHomeAssetsByClipboardAndTaskAssistant() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "agent-task",
                mode: .agentCompose,
                stage: .outputting,
                status: .completed,
                rawTranscript: "帮我回复今晚可以",
                finalText: "可以，今晚发给你。",
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-voice-task",
            source: .dictation,
            contentType: .text,
            title: "普通语音",
            text: "普通语音",
            createdAt: now
        ))
        try environment.assetRepository.save(homeAsset(
            id: "dictation-agent-task",
            source: .dictation,
            contentType: .text,
            title: "帮我回复今晚可以",
            text: "帮我回复今晚可以",
            createdAt: now.addingTimeInterval(-60)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "clip-text",
            source: .clipboard,
            contentType: .text,
            title: "剪贴板内容",
            text: "剪贴板内容",
            createdAt: now.addingTimeInterval(-120)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.updateAssetSourceFilter(.clipboard)

        XCTAssertEqual(viewModel.selectedAssetSourceFilter, .clipboard)
        XCTAssertEqual(viewModel.totalAssetCount, 1)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["clip-text"])

        viewModel.updateAssetSourceFilter(.agentCompose)

        XCTAssertEqual(viewModel.selectedAssetSourceFilter, .agentCompose)
        XCTAssertEqual(viewModel.totalAssetCount, 1)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["dictation-agent-task"])
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.sourceTitle), ["任务助手"])
    }

    func testLoadBuildsContributionActivity() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "today",
            source: .dictation,
            contentType: .text,
            title: "today",
            text: "today",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "yesterday",
            source: .clipboard,
            contentType: .text,
            title: "yesterday",
            text: "yesterday",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "same-day",
            source: .screenshot,
            contentType: .image,
            title: "same-day",
            text: "same-day",
            imagePath: "/tmp/same-day.png",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 15)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "older",
            source: .dictation,
            contentType: .text,
            title: "older",
            text: "older",
            createdAt: makeDate(year: 2025, month: 5, day: 20, hour: 9)
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.activity.days.count, 364)
        XCTAssertEqual(viewModel.activity.days.first?.date, makeDate(year: 2025, month: 6, day: 16, hour: 0))
        XCTAssertEqual(viewModel.activity.days.last?.date, makeDate(year: 2026, month: 6, day: 14, hour: 0))
        XCTAssertEqual(viewModel.activity.days.first?.assetCount, 0)
        XCTAssertEqual(viewModel.activity.days.first?.level, 0)
        XCTAssertEqual(viewModel.activity.days[357].assetCount, 2)
        XCTAssertEqual(viewModel.activity.days[357].level, 4)
        XCTAssertEqual(viewModel.activity.days[358].assetCount, 1)
        XCTAssertEqual(viewModel.activity.days[358].level, 2)
        XCTAssertEqual(viewModel.activity.days.last?.assetCount, 0)
        XCTAssertEqual(viewModel.activity.days.last?.level, 0)
        XCTAssertEqual(viewModel.activity.thisWeekAssets, 3)
        XCTAssertEqual(viewModel.activity.maxDailyAssets, 2)
    }

    func testSelectingActivityDayFiltersStatsAndHistory() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "today",
            source: .dictation,
            contentType: .text,
            title: "今天输入文本",
            text: "今天输入文本",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "yesterday-morning",
            source: .clipboard,
            contentType: .text,
            title: "昨天上午",
            text: "昨天上午",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "yesterday-afternoon",
            source: .screenshot,
            contentType: .image,
            title: "昨天下午",
            text: "昨天下午",
            imagePath: "/tmp/yesterday.png",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 15)
        ))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectActivityDay(makeDate(year: 2026, month: 6, day: 8, hour: 18))

        XCTAssertEqual(viewModel.selectedActivityDate, makeDate(year: 2026, month: 6, day: 8, hour: 0))
        XCTAssertEqual(viewModel.stats.totalAssets, 3)
        XCTAssertEqual(viewModel.stats.focusedAssets, 2)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(screenshot: 1, clipboard: 1))
        XCTAssertEqual(viewModel.stats.reusableAssets, 2)
        XCTAssertEqual(viewModel.focusedAssetsTitle, "6月8日新增")
        XCTAssertEqual(viewModel.assetGroups.map(\.title), ["6月8日"])
        XCTAssertEqual(viewModel.assetGroups.first?.items.map(\.id), ["yesterday-afternoon", "yesterday-morning"])

        viewModel.clearActivityDaySelection()

        XCTAssertNil(viewModel.selectedActivityDate)
        XCTAssertEqual(viewModel.focusedAssetsTitle, "今日新增")
        XCTAssertEqual(viewModel.stats.totalAssets, 3)
        XCTAssertEqual(viewModel.stats.focusedAssets, 1)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["today", "yesterday-afternoon", "yesterday-morning"])
    }

    func testActivityBlankTapRestoresDefaultDashboardState() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "today",
            source: .dictation,
            contentType: .text,
            title: "今天输入文本",
            text: "今天输入文本",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))
        try environment.assetRepository.save(homeAsset(
            id: "yesterday",
            source: .clipboard,
            contentType: .text,
            title: "昨天输入",
            text: "昨天输入",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectActivityDay(makeDate(year: 2026, month: 6, day: 8, hour: 18))

        viewModel.restoreDefaultDashboardFocusFromActivityBlankTap()

        XCTAssertNil(viewModel.selectedActivityDate)
        XCTAssertEqual(viewModel.focusedAssetsTitle, "今日新增")
        XCTAssertEqual(viewModel.stats.totalAssets, 2)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["today", "yesterday"])
    }

    func testApplicationPointerDownRestoresDefaultDashboardState() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectActivityDay(makeDate(year: 2026, month: 6, day: 8, hour: 18))

        viewModel.handleApplicationPointerDown()

        XCTAssertNil(viewModel.selectedActivityDate)
        XCTAssertEqual(viewModel.focusedAssetsTitle, "今日新增")
    }

    func testSelectingHistoryItemUsesRawLLMDiagnosticTraceWhenAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeDashboardLLMDiagnostics-\(UUID().uuidString)", isDirectory: true)
        LLMDiagnosticCapture.shared.configure(enabled: true, directory: directory)
        addTeardownBlock {
            LLMDiagnosticCapture.shared.configure(enabled: false, directory: directory)
        }
        let rawTrace = TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "provider",
                providerName: "OpenAI",
                endpoint: "https://api.example.com/v1/chat/completions",
                model: "gpt-test",
                temperature: 0.2,
                timeoutSeconds: 8,
                requestBodyJSON: #"{"messages":[{"role":"system","content":"完整系统提示"},{"role":"user","content":"完整用户请求"}]}"#,
                responseText: "完整模型返回",
                statusCode: 200,
                durationMS: 123,
                errorMessage: nil,
                completedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        LLMDiagnosticCapture.shared.capture(taskID: "entry", trace: rawTrace)
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let safeTraceData = try JSONEncoder().encode(rawTrace.safeForPersistence())
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                processingTraceJSON: String(data: safeTraceData, encoding: .utf8)
            )
        )
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.selectHistoryItem(id: "entry")

        XCTAssertEqual(viewModel.selectedDetail?.trace?.llm?.responseText, "完整模型返回")
        XCTAssertTrue(viewModel.selectedDetail?.trace?.llm?.requestBodyJSON.contains("完整用户请求") == true)
        XCTAssertTrue(viewModel.selectedDetail?.trace?.llm?.requestBodyJSON.contains("完整系统提示") == true)
    }

    func testCopyWritesAssetTextToClipboardWriter() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "entry",
            source: .clipboard,
            contentType: .text,
            title: "可复制文本",
            text: "可复制文本",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        let clipboard = CapturingClipboardWriter()
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: clipboard,
            calendar: testCalendar
        )
        viewModel.load()

        viewModel.copyAssetItem(id: "entry")

        XCTAssertEqual(clipboard.copiedTexts, ["可复制文本"])
        XCTAssertEqual(viewModel.lastActionMessage, "已复制资产内容")
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    func testHistoryChangeNotificationReloadsDashboard() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        try environment.assetRepository.save(homeAsset(
            id: "new",
            source: .dictation,
            contentType: .text,
            title: "刚刚输入",
            text: "刚刚输入",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 10)
        ))
        environment.notifyHistoryDidChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["new"])
    }

    func testLoadIfNeededDoesNotReloadAlreadyLoadedDashboard() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.assetRepository.save(homeAsset(
            id: "initial",
            source: .dictation,
            contentType: .text,
            title: "已有记录",
            text: "已有记录",
            createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.load()
        try environment.assetRepository.save(homeAsset(
            id: "later",
            source: .dictation,
            contentType: .text,
            title: "切换后新增",
            text: "切换后新增",
            createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
        ))
        viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["initial"])

        viewModel.load()

        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).map(\.id), ["later", "initial"])
    }

    func testLoadIncludesAgentComposeTasksAndOpensTheirDetail() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "agent-task",
                mode: .agentCompose,
                stage: .outputting,
                status: .completed,
                targetAppName: "微信",
                rawTranscript: "帮我回复今晚可以",
                finalText: "可以，今晚发给你。",
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-agent-task",
            source: .dictation,
            contentType: .text,
            title: "帮我回复今晚可以",
            text: "帮我回复今晚可以",
            createdAt: now
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.load()
        viewModel.selectAssetItem(id: "dictation-agent-task")

        let item = try XCTUnwrap(viewModel.assetGroups.flatMap(\.items).first)
        XCTAssertEqual(item.id, "dictation-agent-task")
        XCTAssertEqual(item.sourceTitle, "任务助手")
        XCTAssertEqual(viewModel.selectedDetail?.taskMode, .agentCompose)
        XCTAssertEqual(viewModel.selectedDetail?.appName, "微信")
    }

    func testLoadIncludesSelectionActionTasksWithHomeBadges() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try insertVoiceTask(
            id: "selection-translation",
            mode: "selectionTranslation",
            status: "completed",
            text: "划词翻译结果",
            createdAt: now,
            into: container.databaseQueue
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-selection-translation",
            source: .dictation,
            contentType: .text,
            title: "划词翻译结果",
            text: "划词翻译结果",
            createdAt: now
        ))
        try insertVoiceTask(
            id: "selection-summary",
            mode: "selectionSummary",
            status: "completed",
            text: "划词总结结果",
            createdAt: now.addingTimeInterval(-60),
            into: container.databaseQueue
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-selection-summary",
            source: .dictation,
            contentType: .text,
            title: "划词总结结果",
            text: "划词总结结果",
            createdAt: now.addingTimeInterval(-60)
        ))
        try insertVoiceTask(
            id: "selection-agent",
            mode: "selectionAgent",
            status: "failed",
            text: "划词任务助手上下文",
            createdAt: now.addingTimeInterval(-120),
            into: container.databaseQueue
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-selection-agent",
            source: .dictation,
            contentType: .text,
            title: "划词任务助手上下文",
            text: "划词任务助手上下文",
            createdAt: now.addingTimeInterval(-120)
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.load()

        let items = viewModel.assetGroups.flatMap(\.items)
        XCTAssertEqual(items.map(\.id), [
            "dictation-selection-translation",
            "dictation-selection-summary",
            "dictation-selection-agent"
        ])
        XCTAssertEqual(items.map(\.sourceTitle), ["划词翻译", "划词总结", "划词任务助手"])
    }

    func testAgentComposeDetailDecodesSavedLLMTrace() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "agent-task",
                mode: .agentCompose,
                stage: .outputting,
                status: .completed,
                targetAppName: "微信",
                rawTranscript: "帮我回复微信",
                finalText: "可以，我六点前发给你。",
                trace: #"{"llm":{"providerID":"provider","providerName":"OpenAI","endpoint":"https:\/\/api.example.com\/v1\/chat\/completions","model":"gpt-agent","temperature":0.2,"timeoutSeconds":8,"requestBodyJSON":"{\"messages\":[{\"role\":\"user\",\"content\":\"帮我回复微信\"}]}","responseText":"可以，我六点前发给你。","statusCode":200,"durationMS":123,"errorMessage":null}}"#,
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.selectHistoryItem(id: "agent-task")

        XCTAssertEqual(viewModel.selectedDetail?.trace?.llm?.model, "gpt-agent")
        XCTAssertEqual(viewModel.selectedDetail?.trace?.llm?.statusCode, 200)
        XCTAssertTrue(
            viewModel.selectedDetail?.trace?.llm?.requestBodyJSON.contains("[redacted: user content]") == true
        )
        XCTAssertNil(viewModel.selectedDetail?.trace?.llm?.responseText)
    }

    func testAgentComposeAssetCopyAndDeleteUseVoiceTaskRepository() throws {
        let clock = MutableHomeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "agent-task",
                mode: .agentCompose,
                stage: .outputting,
                status: .completed,
                rawTranscript: "任务助手",
                finalText: "生成结果",
                createdAt: clock.now,
                updatedAt: clock.now,
                completedAt: clock.now
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-agent-task",
            source: .dictation,
            contentType: .text,
            title: "生成结果",
            text: "生成结果",
            createdAt: clock.now
        ))
        let clipboard = CapturingClipboardWriter()
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: clipboard,
            calendar: testCalendar
        )
        viewModel.load()

        viewModel.copyAssetItem(id: "dictation-agent-task")
        viewModel.deleteAssetItem(id: "dictation-agent-task")

        XCTAssertEqual(clipboard.copiedTexts, ["生成结果"])
        XCTAssertNil(try taskRepository.fetch(id: "agent-task"))
        XCTAssertTrue(viewModel.assetGroups.flatMap(\.items).isEmpty)
    }

    func testFailedVoiceTaskDetailCanCopyRecoverableRawTranscript() throws {
        let clock = MutableHomeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "failed-task",
                mode: .dictation,
                stage: .transcribing,
                status: .failed,
                rawTranscript: "失败前可恢复文本",
                finalText: nil,
                createdAt: clock.now,
                updatedAt: clock.now
            )
        )
        let clipboard = CapturingClipboardWriter()
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: clipboard,
            calendar: testCalendar
        )

        viewModel.selectHistoryItem(id: "failed-task")
        let detail = try XCTUnwrap(viewModel.selectedDetail)

        XCTAssertTrue(viewModel.availableRecoveryActions(for: detail).contains(.copy))

        viewModel.copyDetailText()

        XCTAssertEqual(clipboard.copiedTexts, ["失败前可恢复文本"])
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "已复制")
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    func testCompletedDictationDetailReoutputsThroughOutputService() async throws {
        let clock = MutableHomeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        try taskRepository.create(
            VoiceTask(
                id: "dictation-task",
                mode: .dictation,
                stage: .outputting,
                status: .completed,
                targetAppBundleID: "com.example.editor",
                targetAppName: "Editor",
                rawTranscript: "原始文本",
                finalText: "最终文本",
                createdAt: clock.now,
                updatedAt: clock.now,
                completedAt: clock.now
            )
        )
        let outputService = CapturingHistoryOutputService(result: .injected)
        let currentTarget = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor"
        )
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: CapturingClipboardWriter(),
            outputService: outputService,
            targetProvider: StaticDictationTargetProvider(target: currentTarget),
            calendar: testCalendar
        )

        viewModel.selectHistoryItem(id: "dictation-task")

        await viewModel.reoutputDetailText()

        XCTAssertEqual(outputService.deliveries, [
            CapturingHistoryOutputService.Delivery(
                text: "最终文本",
                mode: .dictation,
                target: currentTarget,
                originalTarget: DictationTarget(
                    bundleID: "com.example.editor",
                    appName: "Editor"
                )
            )
        ])
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "已重新输出")
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    func testSelectedVoiceTaskDiagnosticCopyUsesSanitizedExporter() throws {
        let clock = MutableHomeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let taskRepository = VoiceTaskRepository(
            databaseQueue: container.databaseQueue,
            clock: clock
        )
        let outputData = try JSONEncoder().encode(
            OutputResult.permissionDenied(reason: "敏感输出原因")
        )
        try taskRepository.create(
            VoiceTask(
                id: "diagnostic-task",
                mode: .dictation,
                stage: .outputting,
                status: .partiallyCompleted,
                targetAppBundleID: "com.example.editor",
                targetAppName: "Editor",
                audioRelativePath: "audio/private-recording.wav",
                rawTranscript: "完整敏感原文",
                finalText: "完整敏感最终文本",
                outputResult: String(data: outputData, encoding: .utf8),
                failureJson: #"{"stage":"output","code":"permissionDenied","message":"敏感失败详情","recoverable":true}"#,
                asrMetadata: VoiceTaskASRMetadata(
                    providerID: "qwen3_asr",
                    modelID: "qwen3-asr-0.6b-mlx-4bit",
                    language: "zh-CN",
                    sessionID: "session-123",
                    audioDurationMs: 1_200,
                    finalLatencyMs: 340,
                    droppedFrameCount: 2,
                    errorCode: "permissionDenied"
                ),
                createdAt: clock.now,
                updatedAt: clock.now,
                completedAt: clock.now
            )
        )
        let clipboard = CapturingClipboardWriter()
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: clipboard,
            calendar: testCalendar
        )

        viewModel.selectHistoryItem(id: "diagnostic-task")
        viewModel.copySelectedTaskDiagnostic()

        let json = try XCTUnwrap(clipboard.copiedTexts.last)
        XCTAssertFalse(json.contains("完整敏感原文"))
        XCTAssertFalse(json.contains("完整敏感最终文本"))
        XCTAssertFalse(json.contains("audio/private-recording.wav"))
        XCTAssertFalse(json.contains("敏感输出原因"))
        XCTAssertFalse(json.contains("敏感失败详情"))
        XCTAssertTrue(json.contains(#""rawTranscriptLength":"#))
        XCTAssertTrue(json.contains(#""finalTextLength":"#))
        XCTAssertTrue(json.contains(#""hasAudio":true"#))
        XCTAssertTrue(json.contains(#""outputResultKind":"permissionDenied""#))
        XCTAssertTrue(json.contains(#""errorCode":"permissionDenied""#))
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "已复制诊断信息")
    }

    func testSelectedHistoryDiagnosticCopyExportsSanitizedDetailWhenVoiceTaskIsUnavailable() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "history-diagnostic",
                rawText: "完整敏感原文",
                finalText: "完整敏感最终文本",
                processingWarningsJSON: #"["llm_refinement_failed"]"#,
                processingTraceJSON: #"{"contextRounds":{"enabled":true,"requestedRounds":3,"usedRounds":2,"contextHistoryIDs":["same-app-new","same-app-old"],"excludedReasons":["expired"],"wrapperVersion":"context-rounds-wrapper.v1"},"styleRoute":{"candidateStyleIDs":["builtin.chat","builtin.coding"],"routerResponse":"敏感模型输出","selectedStyleID":"builtin.coding","fallbackReason":null,"styleSelectionSource":"aiRouter","routerVersion":"1.0.0","renderedPromptHash":"abc123","durationMS":88},"voiceCorrection":{"candidateEvents":[],"appliedEvents":[],"warnings":[],"failureReason":"敏感失败详情"}}"#
            )
        )
        let clipboard = CapturingClipboardWriter()
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: clipboard,
            calendar: testCalendar
        )

        viewModel.selectHistoryItem(id: "history-diagnostic")
        viewModel.copySelectedTaskDiagnostic()

        let json = try XCTUnwrap(clipboard.copiedTexts.last)
        XCTAssertFalse(json.contains("完整敏感原文"))
        XCTAssertFalse(json.contains("完整敏感最终文本"))
        XCTAssertFalse(json.contains("敏感失败详情"))
        XCTAssertTrue(json.contains(#""id":"history-diagnostic""#))
        XCTAssertTrue(json.contains(#""rawTranscriptLength":"#))
        XCTAssertTrue(json.contains(#""finalTextLength":"#))
        XCTAssertTrue(json.contains(#""warnings":["llm_refinement_failed"]"#))
        XCTAssertTrue(json.contains(#""hasTrace":true"#))
        XCTAssertTrue(json.contains(#""hasContextRounds":true"#))
        XCTAssertTrue(json.contains(#""contextRoundsRequested":3"#))
        XCTAssertTrue(json.contains(#""contextRoundsUsed":2"#))
        XCTAssertTrue(json.contains(#""contextRoundsHistoryIDs":["same-app-new","same-app-old"]"#))
        XCTAssertTrue(json.contains(#""contextRoundsExcludedReasons":["expired"]"#))
        XCTAssertTrue(json.contains(#""contextRoundsWrapperVersion":"context-rounds-wrapper.v1""#))
        XCTAssertTrue(json.contains(#""hasStyleRoute":true"#))
        XCTAssertTrue(json.contains(#""styleRouteCandidateStyleIDs":["builtin.chat","builtin.coding"]"#))
        XCTAssertTrue(json.contains(#""styleRouteSelectedStyleID":"builtin.coding""#))
        XCTAssertTrue(json.contains(#""styleSelectionSource":"aiRouter""#))
        XCTAssertTrue(json.contains(#""styleRouteRouterVersion":"1.0.0""#))
        XCTAssertTrue(json.contains(#""styleRouteRenderedPromptHash":"abc123""#))
        XCTAssertTrue(json.contains(#""styleRouteDurationMS":88"#))
        XCTAssertFalse(json.contains("敏感模型输出"))
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "已复制诊断信息")
    }

    func testSelectHistoryItemLoadsDetail() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                rawText: "原始文本",
                finalText: "最终文本",
                processingWarningsJSON: #"["llm_refinement_failed"]"#,
                processingTraceJSON: #"{"llm":{"providerID":"provider","providerName":"OpenAI","endpoint":"https:\/\/api.example.com\/v1\/chat\/completions","model":"gpt","temperature":0.2,"timeoutSeconds":8,"requestBodyJSON":"{}","responseText":"最终文本","statusCode":200,"durationMS":123,"errorMessage":null}}"#
            )
        )
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.selectHistoryItem(id: "entry")

        XCTAssertEqual(viewModel.selectedDetail?.id, "entry")
        XCTAssertEqual(viewModel.selectedDetail?.rawText, "原始文本")
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "最终文本")
        XCTAssertEqual(viewModel.selectedDetail?.warnings, ["llm_refinement_failed"])
        XCTAssertEqual(viewModel.selectedDetail?.trace?.llm?.model, "gpt")
        XCTAssertEqual(viewModel.selectedDetail?.trace?.llm?.statusCode, 200)
        XCTAssertNil(viewModel.lastError)
    }

    func testBackdropDismissClearsSelectedDetail() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(id: "entry"))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.selectHistoryItem(id: "entry")

        viewModel.clearSelectedHomeDetail()

        XCTAssertNil(viewModel.selectedDetail)
    }

    func testReprocessSelectedHistoryItemUsesRawTextAndUpdatesHistory() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                rawText: "原始文本",
                finalText: "旧文本",
                durationMS: 30_000
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-entry",
            source: .dictation,
            contentType: .text,
            title: "旧文本",
            text: "旧文本",
            createdAt: now
        ))
        let pipeline = CapturingHomeTextPipeline(
            result: TextProcessingResult(
                rawText: "原始文本",
                finalText: "新文本",
                llmProviderID: "llm-provider",
                styleID: "style-formal",
                warnings: ["replacement_rule_invalid_regex:rule"]
            )
        )
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: CapturingClipboardWriter(),
            textPipeline: pipeline,
            calendar: testCalendar
        )
        viewModel.load()
        viewModel.selectHistoryItem(id: "entry")

        await viewModel.reprocessSelectedHistoryItem()

        let saved = try XCTUnwrap(environment.historyRepository.entry(id: "entry"))
        XCTAssertEqual(pipeline.receivedTexts, ["原始文本"])
        XCTAssertEqual(saved.rawText, "原始文本")
        XCTAssertEqual(saved.finalText, "新文本")
        XCTAssertEqual(saved.llmProviderID, "llm-provider")
        XCTAssertEqual(saved.styleID, "style-formal")
        XCTAssertEqual(saved.charCount, 3)
        XCTAssertEqual(saved.cpm, 6)
        XCTAssertEqual(saved.updatedAt, now)
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "新文本")
        let asset = try XCTUnwrap(try environment.assetRepository.asset(id: "dictation-entry"))
        XCTAssertEqual(asset.title, "新文本")
        XCTAssertEqual(asset.text, "新文本")
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).first?.title, "新文本")
        XCTAssertEqual(saved.processingWarningsJSON, #"["replacement_rule_invalid_regex:rule"]"#)
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    func testReprocessSelectedHistoryItemShowsProgressAndNoChangeFeedback() async throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                rawText: "原始文本",
                finalText: "原始文本",
                durationMS: 30_000
            )
        )
        let pipeline = SuspendedHomeTextPipeline(
            result: TextProcessingResult(rawText: "原始文本", finalText: "原始文本")
        )
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: CapturingClipboardWriter(),
            textPipeline: pipeline,
            calendar: testCalendar
        )
        viewModel.selectHistoryItem(id: "entry")

        let reprocessTask = Task {
            await viewModel.reprocessSelectedHistoryItem()
        }
        await waitUntil { pipeline.hasStarted }

        XCTAssertTrue(viewModel.isReprocessing)
        XCTAssertEqual(viewModel.lastActionMessage, "正在重新处理历史记录…")
        XCTAssertEqual(viewModel.lastActionTone, .informational)

        pipeline.finish()
        await reprocessTask.value

        XCTAssertFalse(viewModel.isReprocessing)
        XCTAssertEqual(viewModel.lastActionMessage, "已重新处理，文本无变化")
        XCTAssertEqual(viewModel.lastActionTone, .informational)
    }

    func testReprocessSelectedHistoryItemPassesOriginalTargetAndCorrectionContext() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        let event = CorrectionEvent(
            ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            original: "QQ。",
            replacement: "Qwen3",
            range: CorrectionTextRange(location: 0, length: 3),
            scope: .application(bundleIdentifier: "com.mitchellh.ghostty"),
            source: .automaticLearning
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                rawText: "QQ。",
                finalText: "QQ。",
                durationMS: 30_000,
                createdAt: now,
                targetAppBundleID: "com.mitchellh.ghostty"
            )
        )
        let pipeline = CapturingHomeTextPipeline(
            result: TextProcessingResult(
                rawText: "QQ。",
                finalText: "Qwen3",
                trace: TextProcessingTrace(
                    voiceCorrection: VoiceCorrectionTrace(
                        candidateEvents: [event],
                        appliedEvents: [event]
                    )
                )
            )
        )
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: CapturingClipboardWriter(),
            textPipeline: pipeline,
            calendar: testCalendar
        )

        viewModel.selectHistoryItem(id: "entry")
        await viewModel.reprocessSelectedHistoryItem()

        XCTAssertEqual(pipeline.receivedTexts, ["QQ。"])
        XCTAssertEqual(pipeline.receivedTargets.map { $0?.bundleID }, ["com.mitchellh.ghostty"])
        XCTAssertEqual(pipeline.receivedCorrectionContexts.map { $0?.mode }, [.dictation])
        XCTAssertEqual(pipeline.receivedCorrectionContexts.map { $0?.bundleIdentifier }, ["com.mitchellh.ghostty"])
        XCTAssertEqual(pipeline.receivedCorrectionContexts.map { $0?.providerID }, ["apple_speech"])
        XCTAssertEqual(pipeline.receivedCorrectionContexts.map { $0?.language }, ["zh-CN"])
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "Qwen3")
        XCTAssertEqual(viewModel.selectedDetail?.trace?.voiceCorrection?.appliedEvents, [event])
    }

    func testEditingSelectedHistoryItemLearnsCorrectionFromManualFinalTextChange() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                rawText: "use q 问 today",
                finalText: "use q 问 today",
                durationMS: 30_000,
                createdAt: now,
                targetAppBundleID: "com.cursor.Cursor"
            )
        )
        try environment.assetRepository.save(homeAsset(
            id: "dictation-entry",
            source: .dictation,
            contentType: .text,
            title: "use q 问 today",
            text: "use q 问 today",
            createdAt: now
        ))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectHistoryItem(id: "entry")
        let vocabularyChange = expectation(description: "manual history edit notifies vocabulary UI")
        let observer = NotificationCenter.default.addObserver(
            forName: .correctionVocabularyDidChange,
            object: nil,
            queue: nil
        ) { _ in
            vocabularyChange.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try viewModel.updateSelectedHistoryFinalText("use Qwen today")
        wait(for: [vocabularyChange], timeout: 0.1)

        let saved = try XCTUnwrap(environment.historyRepository.entry(id: "entry"))
        XCTAssertEqual(saved.finalText, "use Qwen today")
        XCTAssertEqual(saved.updatedAt, now)
        XCTAssertEqual(viewModel.selectedDetail?.finalText, "use Qwen today")
        let asset = try XCTUnwrap(try environment.assetRepository.asset(id: "dictation-entry"))
        XCTAssertEqual(asset.title, "use Qwen today")
        XCTAssertEqual(asset.text, "use Qwen today")

        let rule = try XCTUnwrap(try environment.correctionRuleRepository.list().first)
        XCTAssertEqual(rule.original, "q 问")
        XCTAssertEqual(rule.replacement, "Qwen")
        XCTAssertEqual(rule.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(rule.lifecycle, .active)
        XCTAssertEqual(rule.source, .automaticLearning)
        XCTAssertEqual(rule.providerID, "apple_speech")
        XCTAssertEqual(rule.language, "zh-CN")
    }

    func testAssetPaginationPageSizeFilterResetDeleteFallbackAndClear() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        for index in 0..<41 {
            try environment.assetRepository.save(homeAsset(
                id: "entry-\(index)",
                source: .clipboard,
                contentType: .text,
                title: index == 0 ? "needle" : "final \(index)",
                text: index == 0 ? "needle" : "final \(index)",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
            ))
        }
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            calendar: testCalendar,
            historyPageSize: 20
        )

        viewModel.load()
        XCTAssertEqual(viewModel.totalAssetCount, 41)
        XCTAssertEqual(viewModel.totalAssetPages, 3)
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).count, 20)

        viewModel.goToAssetPage(3)
        XCTAssertEqual(viewModel.assetCurrentPage, 3)
        XCTAssertEqual(viewModel.assetGroups.flatMap(\.items).count, 1)
        viewModel.deleteAssetItem(id: "entry-0")
        XCTAssertEqual(viewModel.assetCurrentPage, 2)
        XCTAssertEqual(viewModel.totalAssetCount, 40)

        viewModel.updateAssetPageSize(50)
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        XCTAssertEqual(viewModel.pageSize, 50)
        viewModel.goToAssetPage(2)
        viewModel.updateSearch("final 1")
        XCTAssertEqual(viewModel.assetCurrentPage, 1)

        viewModel.clearAllAssets()
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        XCTAssertEqual(viewModel.stats, HomeDashboardStats())
        XCTAssertEqual(viewModel.totalAssetCount, 0)
        XCTAssertTrue(viewModel.assetGroups.isEmpty)
    }

    func testSearchInputReturnsBeforeSlowAssetQueryCompletes() throws {
        let base = try DependencyContainer.inMemory()
        let repository = SlowSearchAssetRepository(pageDelay: 0.2)
        let container = DependencyContainer(
            clock: base.clock,
            paths: base.paths,
            storageHealth: base.storageHealth,
            databaseQueue: base.databaseQueue,
            credentialStore: base.credentialStore,
            historyRepository: base.historyRepository,
            assetRepository: repository,
            styleRepository: base.styleRepository,
            asrProviderRepository: base.asrProviderRepository,
            llmProviderRepository: base.llmProviderRepository,
            transcriptionJobRepository: base.transcriptionJobRepository,
            noteRepository: base.noteRepository,
            screenshotRecordRepository: base.screenshotRecordRepository,
            mediaRecordRepository: base.mediaRecordRepository,
            settingsRepository: base.settingsRepository,
            correctionTargetRepository: base.correctionTargetRepository,
            correctionEvidenceRepository: base.correctionEvidenceRepository,
            correctionRuleRepository: base.correctionRuleRepository,
            correctionSnapshotProvider: base.correctionSnapshotProvider,
            voiceCorrectionProcessor: base.voiceCorrectionProcessor,
            hotwordFileSyncService: base.hotwordFileSyncService
        )
        let viewModel = HomeDashboardViewModel(
            environment: AppEnvironment(container: container),
            calendar: testCalendar
        )

        let startedAt = Date()
        viewModel.updateSearch("needle")

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.05)
    }

    func testLoadUsesDatabaseAggregateWithoutCallingHistoryListRecent() throws {
        let base = try DependencyContainer.inMemory()
        let historyRepository = CapturingListHistoryRepository(base: base.historyRepository)
        let container = DependencyContainer(
            clock: base.clock,
            paths: base.paths,
            storageHealth: base.storageHealth,
            databaseQueue: base.databaseQueue,
            credentialStore: base.credentialStore,
            historyRepository: historyRepository,
            assetRepository: base.assetRepository,
            styleRepository: base.styleRepository,
            asrProviderRepository: base.asrProviderRepository,
            llmProviderRepository: base.llmProviderRepository,
            transcriptionJobRepository: base.transcriptionJobRepository,
            noteRepository: base.noteRepository,
            screenshotRecordRepository: base.screenshotRecordRepository,
            mediaRecordRepository: base.mediaRecordRepository,
            settingsRepository: base.settingsRepository,
            correctionTargetRepository: base.correctionTargetRepository,
            correctionEvidenceRepository: base.correctionEvidenceRepository,
            correctionRuleRepository: base.correctionRuleRepository,
            correctionSnapshotProvider: base.correctionSnapshotProvider,
            voiceCorrectionProcessor: base.voiceCorrectionProcessor,
            hotwordFileSyncService: base.hotwordFileSyncService
        )
        let viewModel = HomeDashboardViewModel(
            environment: AppEnvironment(container: container),
            calendar: testCalendar
        )

        viewModel.load()

        XCTAssertEqual(historyRepository.listRecentLimits, [])
    }

    func testAssetPreviousNextAndInvalidPageNumbersStayWithinAvailablePages() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        for index in 0..<41 {
            try environment.assetRepository.save(homeAsset(
                id: "page-entry-\(index)",
                source: .clipboard,
                contentType: .text,
                title: "page entry \(index)",
                text: "page entry \(index)",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
            ))
        }
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            calendar: testCalendar,
            historyPageSize: 20
        )
        viewModel.load()

        viewModel.previousAssetPage()
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        viewModel.nextAssetPage()
        XCTAssertEqual(viewModel.assetCurrentPage, 2)
        viewModel.previousAssetPage()
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        viewModel.goToAssetPage(-10)
        XCTAssertEqual(viewModel.assetCurrentPage, 1)
        viewModel.goToAssetPage(999)
        XCTAssertEqual(viewModel.assetCurrentPage, 3)
        viewModel.nextAssetPage()
        XCTAssertEqual(viewModel.assetCurrentPage, 3)
    }

    private func historyEntry(
        id: String,
        rawText: String = "raw",
        finalText: String = "final",
        charCount: Int? = nil,
        durationMS: Int = 1000,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        targetAppBundleID: String? = nil,
        processingWarningsJSON: String? = nil,
        processingTraceJSON: String? = nil
    ) -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: id,
            rawText: rawText,
            finalText: finalText,
            language: "zh-CN",
            asrProviderID: "apple_speech",
            llmProviderID: nil,
            styleID: nil,
            durationMS: durationMS,
            charCount: charCount ?? finalText.count,
            cpm: 120,
            targetAppBundleID: targetAppBundleID,
            targetAppName: "Editor",
            processingWarningsJSON: processingWarningsJSON,
            processingTraceJSON: processingTraceJSON,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }

    private func homeAsset(
        id: String,
        source: AssetSource,
        contentType: AssetContentType,
        title: String,
        text: String? = nil,
        imagePath: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        colorValue: String? = nil,
        createdAt: Date
    ) -> AssetItem {
        AssetItem(
            id: id,
            source: source,
            contentType: contentType,
            title: title,
            previewText: text,
            text: text,
            rawText: nil,
            imagePath: imagePath,
            filePath: filePath,
            url: url,
            colorValue: colorValue,
            sourceAppName: nil,
            sourceAppBundleID: nil,
            contentHash: "hash-\(id)",
            captureReason: source == .dictation ? .dictationCompleted : .userCopied,
            metadataJSON: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = testCalendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return testCalendar.date(from: components)!
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private final class CapturingClipboardWriter: ClipboardWriting {
    private(set) var copiedTexts: [String] = []

    func copy(_ text: String) {
        copiedTexts.append(text)
    }
}

private final class CapturingHomeTextPipeline: TextProcessing {
    private(set) var receivedTexts: [String] = []
    private(set) var receivedTargets: [DictationTarget?] = []
    private(set) var receivedCorrectionContexts: [CorrectionContext?] = []
    let result: TextProcessingResult

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        receivedTexts.append(rawText)
        receivedTargets.append(nil)
        receivedCorrectionContexts.append(nil)
        return result
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        receivedTexts.append(rawText)
        receivedTargets.append(target)
        receivedCorrectionContexts.append(correctionContext)
        return result
    }
}

private final class SuspendedHomeTextPipeline: TextProcessing {
    private let result: TextProcessingResult
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        await process(rawText, target: nil, correctionContext: nil, onRefinedTextUpdate: { _ in })
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return result
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class CapturingHistoryOutputService: OutputService {
    struct Delivery: Equatable {
        let text: String
        let mode: VoiceTaskMode
        let target: DictationTarget?
        let originalTarget: DictationTarget?
    }

    private let result: OutputResult
    private(set) var deliveries: [Delivery] = []

    init(result: OutputResult) {
        self.result = result
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        deliveries.append(
            Delivery(
                text: text,
                mode: mode,
                target: target,
                originalTarget: originalTarget
            )
        )
        return result
    }
}

private final class MutableHomeClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}

private func insertVoiceTask(
    id: String,
    mode: String,
    status: String,
    text: String,
    createdAt: Date,
    into queue: DatabaseQueue
) throws {
    let timestamp = ISO8601DateFormatter().string(from: createdAt)
    try queue.write { connection in
        let statement = try connection.prepare(
            """
            INSERT INTO voice_tasks
                (id, mode, stage, status, raw_transcript, final_text, warnings_json, created_at, updated_at, completed_at)
            VALUES (?, ?, 'outputting', ?, ?, ?, '[]', ?, ?, ?)
            """
        )
        try statement.bind(id, at: 1)
        try statement.bind(mode, at: 2)
        try statement.bind(status, at: 3)
        try statement.bind(text, at: 4)
        try statement.bind(text, at: 5)
        try statement.bind(timestamp, at: 6)
        try statement.bind(timestamp, at: 7)
        try statement.bind(timestamp, at: 8)
        _ = try statement.step()
    }
}

private final class CapturingListHistoryRepository: HistoryRepository {
    private let base: any HistoryRepository
    private(set) var listRecentLimits: [Int] = []

    init(base: any HistoryRepository) {
        self.base = base
    }

    func save(_ entry: DictationHistoryEntry) throws { try base.save(entry) }
    func entry(id: String) throws -> DictationHistoryEntry? { try base.entry(id: id) }
    func listRecent(limit: Int) throws -> [DictationHistoryEntry] {
        listRecentLimits.append(limit)
        return try base.listRecent(limit: limit)
    }
    func listRecent(limit: Int, offset: Int) throws -> [DictationHistoryEntry] {
        listRecentLimits.append(limit)
        return try base.listRecent(limit: limit, offset: offset)
    }
    func search(_ query: String, limit: Int) throws -> [DictationHistoryEntry] {
        try base.search(query, limit: limit)
    }
    func search(_ query: String, limit: Int, offset: Int) throws -> [DictationHistoryEntry] {
        try base.search(query, limit: limit, offset: offset)
    }
    func softDelete(id: String, deletedAt: Date) throws {
        try base.softDelete(id: id, deletedAt: deletedAt)
    }
}

private final class SlowSearchAssetRepository: AssetRepository {
    private let pageDelay: TimeInterval

    init(pageDelay: TimeInterval) {
        self.pageDelay = pageDelay
    }

    func save(_ item: AssetItem) throws {}

    func asset(id: String) throws -> AssetItem? {
        nil
    }

    func page(query: AssetQuery) throws -> AssetPage {
        if !query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Thread.sleep(forTimeInterval: pageDelay)
        }
        return AssetPage(items: [], totalCount: 0)
    }

    func softDelete(id: String, deletedAt: Date) throws {}

    func softDelete(ids: [String], deletedAt: Date) throws {}

    func clearAll(deletedAt: Date) throws {}
}
