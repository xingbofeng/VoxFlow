import XCTest
@testable import VoiceInputApp

@MainActor
final class HomeDashboardViewModelTests: XCTestCase {
    func testLoadComputesStatisticsAndGroupedHistory() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "today",
                finalText: "今天输入文本",
                charCount: 50,
                durationMS: 30_000,
                createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "yesterday",
                finalText: "昨天输入",
                charCount: 30,
                durationMS: 30_000,
                createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
            )
        )

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.stats.totalCharacters, 80)
        XCTAssertEqual(viewModel.stats.todayCharacters, 50)
        XCTAssertEqual(viewModel.stats.averageCPM, 80)
        XCTAssertEqual(viewModel.stats.streakDays, 2)
        XCTAssertEqual(viewModel.historyGroups.map(\.title), ["今天", "昨天"])
        XCTAssertEqual(viewModel.historyGroups.first?.items.map(\.id), ["today"])
    }

    func testLoadBuildsContributionActivity() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "today",
                finalText: "today",
                charCount: 40,
                createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "yesterday",
                finalText: "yesterday",
                charCount: 10,
                createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "same-day",
                finalText: "same-day",
                charCount: 30,
                createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 15)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "older",
                finalText: "older",
                charCount: 80,
                createdAt: makeDate(year: 2025, month: 5, day: 20, hour: 9)
            )
        )

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        XCTAssertEqual(viewModel.activity.days.count, 364)
        XCTAssertEqual(viewModel.activity.days.first?.date, makeDate(year: 2025, month: 6, day: 16, hour: 0))
        XCTAssertEqual(viewModel.activity.days.last?.date, makeDate(year: 2026, month: 6, day: 14, hour: 0))
        XCTAssertEqual(viewModel.activity.days.first?.characters, 0)
        XCTAssertEqual(viewModel.activity.days.first?.level, 0)
        XCTAssertEqual(viewModel.activity.days[357].characters, 40)
        XCTAssertEqual(viewModel.activity.days[357].level, 4)
        XCTAssertEqual(viewModel.activity.days[358].characters, 40)
        XCTAssertEqual(viewModel.activity.days[358].level, 4)
        XCTAssertEqual(viewModel.activity.days.last?.characters, 0)
        XCTAssertEqual(viewModel.activity.days.last?.level, 0)
        XCTAssertEqual(viewModel.activity.thisWeekCharacters, 80)
        XCTAssertEqual(viewModel.activity.maxDailyCharacters, 40)
    }

    func testSelectingActivityDayFiltersStatsAndHistory() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "today",
                finalText: "今天输入文本",
                charCount: 50,
                durationMS: 30_000,
                createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "yesterday-morning",
                finalText: "昨天上午",
                charCount: 30,
                durationMS: 30_000,
                createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "yesterday-afternoon",
                finalText: "昨天下午",
                charCount: 10,
                durationMS: 30_000,
                createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 15)
            )
        )

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectActivityDay(makeDate(year: 2026, month: 6, day: 8, hour: 18))

        XCTAssertEqual(viewModel.selectedActivityDate, makeDate(year: 2026, month: 6, day: 8, hour: 0))
        XCTAssertEqual(viewModel.stats.totalCharacters, 40)
        XCTAssertEqual(viewModel.stats.todayCharacters, 40)
        XCTAssertEqual(viewModel.stats.averageCPM, 40)
        XCTAssertEqual(viewModel.focusedCharactersTitle, "6月8日字符")
        XCTAssertEqual(viewModel.historyGroups.map(\.title), ["6月8日"])
        XCTAssertEqual(viewModel.historyGroups.first?.items.map(\.id), ["yesterday-afternoon", "yesterday-morning"])

        viewModel.clearActivityDaySelection()

        XCTAssertNil(viewModel.selectedActivityDate)
        XCTAssertEqual(viewModel.focusedCharactersTitle, "今日字符")
        XCTAssertEqual(viewModel.stats.totalCharacters, 90)
        XCTAssertEqual(viewModel.stats.todayCharacters, 50)
        XCTAssertEqual(viewModel.historyGroups.flatMap(\.items).map(\.id), ["today", "yesterday-afternoon", "yesterday-morning"])
    }

    func testActivityBlankTapRestoresDefaultDashboardState() throws {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 12)
        let clock = MutableHomeClock(now: now)
        let container = try DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "today",
                finalText: "今天输入文本",
                charCount: 50,
                createdAt: makeDate(year: 2026, month: 6, day: 9, hour: 9)
            )
        )
        try environment.historyRepository.save(
            historyEntry(
                id: "yesterday",
                finalText: "昨天输入",
                charCount: 30,
                createdAt: makeDate(year: 2026, month: 6, day: 8, hour: 9)
            )
        )
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectActivityDay(makeDate(year: 2026, month: 6, day: 8, hour: 18))

        viewModel.restoreDefaultDashboardFocusFromActivityBlankTap()

        XCTAssertNil(viewModel.selectedActivityDate)
        XCTAssertEqual(viewModel.focusedCharactersTitle, "今日字符")
        XCTAssertEqual(viewModel.stats.totalCharacters, 80)
        XCTAssertEqual(viewModel.historyGroups.flatMap(\.items).map(\.id), ["today", "yesterday"])
    }

    func testApplicationPointerDownRestoresDefaultDashboardState() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()
        viewModel.selectActivityDay(makeDate(year: 2026, month: 6, day: 8, hour: 18))

        viewModel.handleApplicationPointerDown()

        XCTAssertNil(viewModel.selectedActivityDate)
        XCTAssertEqual(viewModel.focusedCharactersTitle, "今日字符")
    }

    func testHistoryItemExposesFinalAndRawTextForConversionToggle() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(
            historyEntry(
                id: "entry",
                rawText: "转换前文本",
                finalText: "转换后文本"
            )
        )
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        let item = try XCTUnwrap(viewModel.historyGroups.first?.items.first)
        XCTAssertTrue(item.hasTextVariants)
        XCTAssertEqual(item.text(for: .final), "转换后文本")
        XCTAssertEqual(item.text(for: .raw), "转换前文本")
    }

    func testSearchFiltersHistoryThroughRepository() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(id: "match", finalText: "搜索目标"))
        try environment.historyRepository.save(historyEntry(id: "miss", finalText: "其他文本"))

        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.updateSearch("目标")

        XCTAssertEqual(viewModel.historyGroups.flatMap(\.items).map(\.id), ["match"])
    }

    func testCopyWritesFinalTextToClipboardWriter() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(id: "entry", finalText: "可复制文本"))
        let clipboard = CapturingClipboardWriter()
        let viewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: clipboard,
            calendar: testCalendar
        )
        viewModel.load()

        viewModel.copyHistoryItem(id: "entry")

        XCTAssertEqual(clipboard.copiedTexts, ["可复制文本"])
        XCTAssertEqual(viewModel.lastActionMessage, "已复制历史文本")
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    func testHistoryChangeNotificationReloadsDashboard() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        try environment.historyRepository.save(historyEntry(id: "new", finalText: "刚刚输入"))
        environment.historyDidChange.send()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(viewModel.historyGroups.flatMap(\.items).map(\.id), ["new"])
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
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)

        viewModel.load()
        viewModel.selectHistoryItem(id: "agent-task")

        let item = try XCTUnwrap(viewModel.historyGroups.flatMap(\.items).first)
        XCTAssertEqual(item.id, "agent-task")
        XCTAssertEqual(item.taskMode, .agentCompose)
        XCTAssertEqual(item.finalText, "可以，今晚发给你。")
        XCTAssertEqual(viewModel.selectedDetail?.taskMode, .agentCompose)
        XCTAssertEqual(viewModel.selectedDetail?.appName, "微信")
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
    }

    func testAgentComposeHistoryCopyAndDeleteUseVoiceTaskRepository() throws {
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
                rawTranscript: "帮我说",
                finalText: "生成结果",
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
        viewModel.load()

        viewModel.copyHistoryItem(id: "agent-task")
        viewModel.deleteHistoryItem(id: "agent-task")

        XCTAssertEqual(clipboard.copiedTexts, ["生成结果"])
        XCTAssertNil(try taskRepository.fetch(id: "agent-task"))
        XCTAssertTrue(viewModel.historyGroups.flatMap(\.items).isEmpty)
    }

    func testDeleteSoftDeletesAndReloadsHistory() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(id: "entry", finalText: "删除文本"))
        let viewModel = HomeDashboardViewModel(environment: environment, calendar: testCalendar)
        viewModel.load()

        viewModel.deleteHistoryItem(id: "entry")

        XCTAssertEqual(viewModel.historyGroups, [])
        XCTAssertNotNil(try environment.historyRepository.entry(id: "entry")?.deletedAt)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除历史记录")
        XCTAssertEqual(viewModel.lastActionTone, .destructive)
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

        viewModel.dismissSelectedDetailFromBackdrop()

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
        XCTAssertEqual(viewModel.historyGroups.flatMap(\.items).first?.finalText, "新文本")
        XCTAssertEqual(saved.processingWarningsJSON, #"["replacement_rule_invalid_regex:rule"]"#)
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    private func historyEntry(
        id: String,
        rawText: String = "raw",
        finalText: String = "final",
        charCount: Int? = nil,
        durationMS: Int = 1000,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
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
            targetAppBundleID: nil,
            targetAppName: "Editor",
            processingWarningsJSON: processingWarningsJSON,
            processingTraceJSON: processingTraceJSON,
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
    let result: TextProcessingResult

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        receivedTexts.append(rawText)
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
