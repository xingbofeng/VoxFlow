import AppKit
import Combine
import Foundation

struct HomeDashboardStats: Equatable {
    var totalCharacters = 0
    var todayCharacters = 0
    var averageCPM = 0
    var streakDays = 0
}

struct HomeActivityDay: Equatable, Identifiable {
    let date: Date
    let characters: Int
    let level: Int

    var id: Date { date }
}

struct HomeActivitySummary: Equatable {
    var days: [HomeActivityDay] = []
    var thisWeekCharacters = 0
    var maxDailyCharacters = 0
}

struct HomeHistoryItem: Equatable, Identifiable {
    let id: String
    let finalText: String
    let rawText: String
    let appName: String?
    let appBundleID: String?
    let charCount: Int
    let cpm: Double
    let createdAt: Date
    let taskMode: VoiceTaskMode?
    let taskStatus: VoiceTaskStatus?
}

enum HomeHistoryTextVariant: Equatable {
    case final
    case raw
}

struct HomeHistoryGroup: Equatable, Identifiable {
    let id: String
    let title: String
    let date: Date
    let items: [HomeHistoryItem]
}

struct HomeHistoryDetail: Equatable, Identifiable {
    let id: String
    let rawText: String
    let finalText: String
    let language: String
    let asrProviderID: String?
    let llmProviderID: String?
    let styleID: String?
    let appName: String?
    let appBundleID: String?
    let durationMS: Int
    let charCount: Int
    let cpm: Double
    let warnings: [String]
    let trace: TextProcessingTrace?
    let createdAt: Date
    let updatedAt: Date
    // Agent compose fields
    let taskMode: VoiceTaskMode?
    let taskStatus: VoiceTaskStatus?
    let windowTitle: String?
    let contextPreview: String?
    let outputResultRaw: String?
}

protocol ClipboardWriting: AnyObject {
    func copy(_ text: String)
}

typealias HistoryRecoveryAction = VoiceTaskRecoveryAction

final class GeneralPasteboardWriter: ClipboardWriting {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var stats = HomeDashboardStats()
    @Published private(set) var activity = HomeActivitySummary()
    @Published private(set) var selectedActivityDate: Date?
    @Published private(set) var historyGroups: [HomeHistoryGroup] = []
    @Published private(set) var selectedDetail: HomeHistoryDetail?
    @Published private(set) var isReprocessing = false
    @Published private(set) var canLoadMoreHistory = false
    @Published private(set) var currentPage = 1
    @Published private(set) var pageSize: Int
    @Published private(set) var totalHistoryCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var lastActionTone = ActionFeedbackTone.success
    @Published var searchText = ""

    private let environment: any AppServiceProviding & AppEventRouting
    private let clipboardWriter: ClipboardWriting
    private let outputService: (any OutputService)?
    private let targetProvider: (any DictationTargetProviding)?
    private let textPipeline: (any TextProcessing)?
    private let calendar: Calendar
    private let historyLimit: Int
    private let historyPageSize: Int
    private let voiceTaskRepository: VoiceTaskRepository
    private let homeHistoryRepository: any HomeHistoryQuerying
    private var recentEntries: [DictationHistoryEntry] = []
    private var recentAgentTasks: [VoiceTask] = []
    private var visibleHistoryItemLimit: Int
    private var cancellables: Set<AnyCancellable> = []
    private var hasLoaded = false

    var openHistoryDetailRequests: AnyPublisher<String, Never> {
        environment.openHistoryDetailPublisher
    }

    init(
        environment: any AppServiceProviding & AppEventRouting,
        clipboardWriter: ClipboardWriting = GeneralPasteboardWriter(),
        outputService: (any OutputService)? = nil,
        targetProvider: (any DictationTargetProviding)? = nil,
        textPipeline: (any TextProcessing)? = nil,
        calendar: Calendar = .current,
        historyLimit: Int = 1_000,
        historyPageSize: Int = 20,
        homeHistoryRepository: (any HomeHistoryQuerying)? = nil
    ) {
        self.environment = environment
        self.clipboardWriter = clipboardWriter
        self.outputService = outputService
        self.targetProvider = targetProvider
        self.textPipeline = textPipeline ?? Self.makeDefaultTextPipeline(environment: environment)
        self.calendar = calendar
        self.historyLimit = historyLimit
        self.historyPageSize = max(1, historyPageSize)
        self.pageSize = max(1, historyPageSize)
        self.visibleHistoryItemLimit = max(1, historyPageSize)
        self.voiceTaskRepository = VoiceTaskRepository(
            databaseQueue: environment.databaseQueue,
            clock: environment.clock
        )
        self.homeHistoryRepository = homeHistoryRepository
            ?? HomeHistoryRepository(databaseQueue: environment.databaseQueue)
        environment.historyDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.load()
            }
            .store(in: &cancellables)
    }

    func load() {
        do {
            try reloadDashboardAggregate()
            try reloadHistoryPage()
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        load()
    }

    func updateSearch(_ query: String) {
        searchText = query
        currentPage = 1
        refreshHistoryPage()
    }

    func selectActivityDay(_ date: Date) {
        selectedActivityDate = calendar.startOfDay(for: date)
        currentPage = 1
        refreshScopedDashboardState()
    }

    func clearActivityDaySelection() {
        selectedActivityDate = nil
        currentPage = 1
        refreshScopedDashboardState()
    }

    func restoreDefaultDashboardFocusFromActivityBlankTap() {
        handleApplicationPointerDown()
    }

    func handleApplicationPointerDown() {
        guard selectedActivityDate != nil else {
            return
        }
        clearActivityDaySelection()
    }

    func copyHistoryItem(id: String) {
        guard let item = historyGroups.flatMap(\.items).first(where: { $0.id == id }) else {
            return
        }
        clipboardWriter.copy(item.finalText)
        lastError = nil
        lastActionMessage = "已复制历史文本"
        lastActionTone = .success
    }

    func deleteHistoryItem(id: String) {
        do {
            if historyGroups.flatMap(\.items).first(where: { $0.id == id })?.taskMode != nil {
                try voiceTaskRepository.delete(id: id)
            } else {
                try environment.historyRepository.softDelete(id: id, deletedAt: environment.clock.now)
            }
            load()
            lastError = nil
            lastActionMessage = "已删除历史记录"
            lastActionTone = .destructive
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectHistoryItem(id: String) {
        do {
            if let entry = try environment.historyRepository.entry(id: id), entry.deletedAt == nil {
                selectedDetail = HomeHistoryDetail(entry: entry)
                    .replacingTrace(LLMDiagnosticCapture.shared.trace(taskID: id))
                lastError = nil
                return
            }
            if let task = try voiceTaskRepository.fetch(id: id) {
                selectedDetail = HomeHistoryDetail(task: task)
                    .replacingTrace(LLMDiagnosticCapture.shared.trace(taskID: id))
                lastError = nil
                return
            }
            selectedDetail = nil
            lastError = "未找到历史记录。"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearSelectedDetail() {
        selectedDetail = nil
    }

    func dismissSelectedDetailFromBackdrop() {
        clearSelectedDetail()
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    func loadMoreHistory() {
        nextPage()
    }

    var totalPages: Int {
        max(1, Int(ceil(Double(totalHistoryCount) / Double(pageSize))))
    }

    var canGoToPreviousPage: Bool { currentPage > 1 }
    var canGoToNextPage: Bool { currentPage < totalPages }

    func goToPage(_ page: Int) {
        let target = min(max(1, page), totalPages)
        guard target != currentPage else { return }
        currentPage = target
        refreshHistoryPage()
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func updateHistoryPageSize(_ size: Int) {
        guard size > 0, size != pageSize else { return }
        pageSize = size
        currentPage = 1
        refreshHistoryPage()
    }

    func clearAllHistory() {
        do {
            try homeHistoryRepository.clearAll(deletedAt: environment.clock.now)
            currentPage = 1
            selectedDetail = nil
            load()
            lastActionMessage = "已清空历史数据"
            lastActionTone = .destructive
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Recovery actions

    /// Returns the available recovery actions for the selected history detail.
    func availableRecoveryActions(for detail: HomeHistoryDetail) -> [HistoryRecoveryAction] {
        VoiceTaskRecoveryPolicy.availableActions(
            mode: detail.taskMode,
            status: detail.taskStatus,
            hasFinalText: !detail.finalText.isEmpty,
            hasRawTranscript: !detail.rawText.isEmpty,
            outputResultKind: detail.outputResultKind
        )
    }

    /// Copies the best recoverable text from the selected detail.
    func copyDetailText() {
        guard let text = selectedDetail?.recoverableTextForCopy else {
            lastError = "没有可复制的文本。"
            return
        }
        clipboardWriter.copy(text)
        lastError = nil
        lastActionMessage = "已复制"
        lastActionTone = .success
    }

    /// Re-outputs the final text (dictation tasks only).
    func reoutputDetailText() async {
        guard let detail = selectedDetail,
              detail.taskMode == .dictation,
              !detail.finalText.isEmpty else {
            lastError = "无法重新输出。"
            return
        }
        guard let outputService else {
            lastError = "输出服务不可用。"
            return
        }

        let result = await outputService.deliver(
            text: detail.finalText,
            mode: .dictation,
            target: targetProvider?.currentTarget(),
            originalTarget: detail.originalDictationTarget
        )
        switch result.kind {
        case .inserted:
            lastError = nil
            lastActionMessage = "已重新输出"
            lastActionTone = .success
        case .copied, .targetChanged:
            lastError = nil
            lastActionMessage = "已复制到剪贴板，请手动粘贴"
            lastActionTone = .success
        case .permissionDenied, .failed, .cancelled:
            lastError = "重新输出失败。"
        }
    }

    func copySelectedTaskDiagnostic() {
        guard let detail = selectedDetail,
              detail.taskMode != nil else {
            lastError = "没有可导出的诊断信息。"
            return
        }

        do {
            guard let task = try voiceTaskRepository.fetch(id: detail.id) else {
                lastError = "未找到语音任务。"
                return
            }
            let data = try VoiceTaskDiagnosticExporter().export(task)
            guard let json = String(data: data, encoding: .utf8) else {
                lastError = "诊断信息编码失败。"
                return
            }
            clipboardWriter.copy(json)
            lastError = nil
            lastActionMessage = "已复制诊断信息"
            lastActionTone = .success
        } catch {
            lastError = error.localizedDescription
        }
    }

    var focusedCharactersTitle: String {
        guard let selectedActivityDate else {
            return "今日字符"
        }
        return "\(dateTitle(for: selectedActivityDate))字符"
    }

    func reprocessSelectedHistoryItem() async {
        guard let id = selectedDetail?.id else {
            return
        }
        guard let textPipeline else {
            lastError = "文本处理管线不可用。"
            return
        }

        isReprocessing = true
        defer { isReprocessing = false }

        do {
            guard let entry = try environment.historyRepository.entry(id: id), entry.deletedAt == nil else {
                selectedDetail = nil
                lastError = "未找到历史记录。"
                return
            }

            let result = await textPipeline.process(entry.rawText)
            let finalText = normalizedFinalText(from: result, fallback: entry.rawText)
            let updatedEntry = updatedHistoryEntry(from: entry, finalText: finalText, processingResult: result)
            try environment.historyRepository.save(updatedEntry)
            environment.notifyHistoryDidChange()
            load()
            selectedDetail = HomeHistoryDetail(entry: updatedEntry)
            lastError = nil
            lastActionMessage = "已重新处理历史记录"
            lastActionTone = .success
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshScopedDashboardState() {
        do {
            try reloadDashboardAggregate()
            try reloadHistoryPage()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshHistoryPage() {
        do {
            try reloadHistoryPage()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reloadDashboardAggregate() throws {
        let today = calendar.startOfDay(for: environment.clock.now)
        let focusDay = selectedActivityDate.map(calendar.startOfDay(for:)) ?? today
        let focusEnd = calendar.date(byAdding: .day, value: 1, to: focusDay) ?? focusDay
        let currentWeekStart = startOfWeek(containing: today)
        let activityStart = calendar.date(byAdding: .day, value: -51 * 7, to: currentWeekStart)
            ?? currentWeekStart
        let activityEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let aggregate = try homeHistoryRepository.dashboardAggregate(
            statsStartDate: selectedActivityDate == nil ? nil : focusDay,
            statsEndDate: selectedActivityDate == nil ? nil : focusEnd,
            focusStartDate: focusDay,
            focusEndDate: focusEnd,
            activityStartDate: activityStart,
            activityEndDate: activityEnd,
            activityTimeZoneOffsetSeconds: calendar.timeZone.secondsFromGMT(for: today)
        )

        let totalMinutes = max(Double(aggregate.totalDurationMS) / 60_000.0, 1.0 / 60_000.0)
        let averageCPM = aggregate.totalCharacters == 0
            ? 0
            : Int((Double(aggregate.totalCharacters) / totalMinutes).rounded())
        let activeDays = Set(aggregate.activityDays.map { calendar.startOfDay(for: $0.date) })
        stats = HomeDashboardStats(
            totalCharacters: aggregate.totalCharacters,
            todayCharacters: aggregate.focusedCharacters,
            averageCPM: averageCPM,
            streakDays: streakDays(from: activeDays, referenceDay: focusDay)
        )

        let charactersByDay = Dictionary(
            uniqueKeysWithValues: aggregate.activityDays.map {
                (calendar.startOfDay(for: $0.date), $0.characters)
            }
        )
        let maxDailyCharacters = charactersByDay.values.max() ?? 0
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? today
        let dayCount = calendar.dateComponents([.day], from: activityStart, to: endOfWeek).day.map { $0 + 1 } ?? 0
        let days = (0..<dayCount).compactMap { offset -> HomeActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: activityStart) else {
                return nil
            }
            let characters = charactersByDay[day, default: 0]
            return HomeActivityDay(
                date: day,
                characters: characters,
                level: activityLevel(for: characters, maxDailyCharacters: maxDailyCharacters)
            )
        }
        let thisWeekCharacters = charactersByDay
            .filter { day, _ in day >= currentWeekStart && day <= today }
            .reduce(0) { $0 + $1.value }
        activity = HomeActivitySummary(
            days: days,
            thisWeekCharacters: thisWeekCharacters,
            maxDailyCharacters: maxDailyCharacters
        )
    }

    private func streakDays(from activeDays: Set<Date>, referenceDay: Date) -> Int {
        var cursor = referenceDay
        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }

    private func reloadHistoryPage() throws {
        let dateRange = selectedActivityDate.map { day -> (Date, Date?) in
            let start = calendar.startOfDay(for: day)
            return (start, calendar.date(byAdding: .day, value: 1, to: start))
        }
        var page = try homeHistoryRepository.page(
            query: HomeHistoryQuery(
                searchText: searchText,
                startDate: dateRange?.0,
                endDate: dateRange?.1,
                limit: pageSize,
                offset: (currentPage - 1) * pageSize
            )
        )
        totalHistoryCount = page.totalCount
        let lastPage = totalPages
        if currentPage > lastPage {
            currentPage = lastPage
            page = try homeHistoryRepository.page(
                query: HomeHistoryQuery(
                    searchText: searchText,
                    startDate: dateRange?.0,
                    endDate: dateRange?.1,
                    limit: pageSize,
                    offset: (currentPage - 1) * pageSize
                )
            )
        }
        canLoadMoreHistory = canGoToNextPage
        historyGroups = makeHistoryGroups(records: page.records)
    }

    private func makeHistoryGroups(records: [HomeHistoryRecord]) -> [HomeHistoryGroup] {
        let items = records.map { record in
            HomeHistoryItem(
                id: record.id,
                finalText: record.finalText,
                rawText: record.rawText,
                appName: record.appName,
                appBundleID: record.appBundleID,
                charCount: record.charCount,
                cpm: record.cpm,
                createdAt: record.createdAt,
                taskMode: record.taskMode,
                taskStatus: record.taskStatus
            )
        }
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            HomeHistoryGroup(
                id: Self.dayIDFormatter.string(from: day),
                title: title(for: day, preferExplicitDate: selectedActivityDate != nil),
                date: day,
                items: grouped[day] ?? []
            )
        }
    }

    private static func makeDefaultTextPipeline(environment: any AppServiceProviding) -> any TextProcessing {
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore
        )
        let styleSelector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: LLMApplicationStyleClassifier(refiner: refiner)
        )
        return DefaultTextProcessingPipeline(
            refiner: refiner,
            styleSelector: styleSelector
        )
    }

    private func scopedEntries(_ entries: [DictationHistoryEntry]) -> [DictationHistoryEntry] {
        guard let selectedActivityDate else {
            return entries
        }
        return entries.filter { calendar.isDate($0.createdAt, inSameDayAs: selectedActivityDate) }
    }

    private func makeStats(from entries: [DictationHistoryEntry], focusDay: Date? = nil) -> HomeDashboardStats {
        let validEntries = entries.filter { $0.durationMS >= 300 && $0.charCount > 0 }
        let totalCharacters = validEntries.reduce(0) { $0 + $1.charCount }
        let today = focusDay ?? calendar.startOfDay(for: environment.clock.now)
        let todayCharacters = entries
            .filter { calendar.isDate($0.createdAt, inSameDayAs: today) }
            .reduce(0) { $0 + $1.charCount }
        let totalDurationMS = validEntries.reduce(0) { $0 + max(0, $1.durationMS) }
        let totalMinutes = max(Double(totalDurationMS) / 60_000.0, 1.0 / 60_000.0)
        let averageCPM = validEntries.isEmpty ? 0 : Int((Double(totalCharacters) / totalMinutes).rounded())
        return HomeDashboardStats(
            totalCharacters: totalCharacters,
            todayCharacters: todayCharacters,
            averageCPM: averageCPM,
            streakDays: streakDays(from: entries, referenceDay: today)
        )
    }

    private func makeActivity(from entries: [DictationHistoryEntry]) -> HomeActivitySummary {
        let today = calendar.startOfDay(for: environment.clock.now)
        let currentWeekStart = startOfWeek(containing: today)
        guard let startDay = calendar.date(byAdding: .day, value: -51 * 7, to: currentWeekStart),
              let endDay = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else {
            return HomeActivitySummary()
        }

        var charactersByDay: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            guard day >= startDay, day <= today else {
                continue
            }
            charactersByDay[day, default: 0] += max(0, entry.charCount)
        }

        let maxDailyCharacters = charactersByDay.values.max() ?? 0
        let dayCount = calendar.dateComponents([.day], from: startDay, to: endDay).day.map { $0 + 1 } ?? 0
        let days = (0..<dayCount).compactMap { offset -> HomeActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            let characters = charactersByDay[day, default: 0]
            return HomeActivityDay(
                date: day,
                characters: characters,
                level: activityLevel(for: characters, maxDailyCharacters: maxDailyCharacters)
            )
        }

        let thisWeekCharacters = charactersByDay
            .filter { day, _ in day >= currentWeekStart && day <= today }
            .reduce(0) { $0 + $1.value }

        return HomeActivitySummary(
            days: days,
            thisWeekCharacters: thisWeekCharacters,
            maxDailyCharacters: maxDailyCharacters
        )
    }

    private func activityLevel(for characters: Int, maxDailyCharacters: Int) -> Int {
        guard characters > 0, maxDailyCharacters > 0 else {
            return 0
        }

        let ratio = Double(characters) / Double(maxDailyCharacters)
        switch ratio {
        case ...0.25:
            return 1
        case ...0.5:
            return 2
        case ...0.75:
            return 3
        default:
            return 4
        }
    }

    private func startOfWeek(containing day: Date) -> Date {
        let weekday = calendar.component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }

    private func streakDays(from entries: [DictationHistoryEntry], referenceDay: Date? = nil) -> Int {
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        var cursor = referenceDay ?? calendar.startOfDay(for: environment.clock.now)
        var streak = 0

        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }

    private func historyEntriesForGroups(
        query: String,
        fallback: [DictationHistoryEntry]
    ) throws -> [DictationHistoryEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return fallback
        }
        return try environment.historyRepository.search(trimmedQuery, limit: historyLimit)
    }

    private func makeHistoryGroups(
        entries: [DictationHistoryEntry],
        query: String
    ) -> [HomeHistoryGroup] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskItems = recentAgentTasks
            .filter { task in
                guard !trimmedQuery.isEmpty else { return true }
                return [
                    task.rawTranscript,
                    task.finalText,
                    task.targetAppName,
                    task.targetWindowTitle,
                ]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            }
            .filter { task in
                guard let selectedActivityDate else { return true }
                return calendar.isDate(task.createdAt, inSameDayAs: selectedActivityDate)
            }
            .map(HomeHistoryItem.init(task:))
        let historyItems = scopedEntries(entries).map(HomeHistoryItem.init(entry:))
        let sortedItems = (historyItems + taskItems)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(historyLimit)
        canLoadMoreHistory = sortedItems.count > visibleHistoryItemLimit
        let allItems = Array(sortedItems.prefix(visibleHistoryItemLimit))
        let grouped = Dictionary(grouping: allItems) { item in
            calendar.startOfDay(for: item.createdAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? [])
                .sorted { $0.createdAt > $1.createdAt }
            return HomeHistoryGroup(
                id: Self.dayIDFormatter.string(from: day),
                title: title(for: day, preferExplicitDate: selectedActivityDate != nil),
                date: day,
                items: items
            )
        }
    }

    private func title(for day: Date, preferExplicitDate: Bool = false) -> String {
        if preferExplicitDate {
            return dateTitle(for: day)
        }

        let today = calendar.startOfDay(for: environment.clock.now)
        if calendar.isDate(day, inSameDayAs: today) {
            return "今天"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨天"
        }

        return dateTitle(for: day)
    }

    private func dateTitle(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day)
    }

    private func normalizedFinalText(from result: TextProcessingResult, fallback: String) -> String {
        let trimmed = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func updatedHistoryEntry(
        from entry: DictationHistoryEntry,
        finalText: String,
        processingResult: TextProcessingResult
    ) -> DictationHistoryEntry {
        let charCount = finalText.count
        let durationMinutes = max(Double(entry.durationMS) / 60_000.0, 1.0 / 60_000.0)
        let now = environment.clock.now

        return DictationHistoryEntry(
            id: entry.id,
            rawText: entry.rawText,
            finalText: finalText,
            language: entry.language,
            asrProviderID: entry.asrProviderID,
            llmProviderID: processingResult.llmProviderID,
            styleID: processingResult.styleID,
            durationMS: entry.durationMS,
            charCount: charCount,
            cpm: Double(charCount) / durationMinutes,
            targetAppBundleID: entry.targetAppBundleID,
            targetAppName: entry.targetAppName,
            processingWarningsJSON: warningsJSON(processingResult.warnings),
            processingTraceJSON: traceJSON(processingResult.trace, diagnosticID: entry.id),
            createdAt: entry.createdAt,
            updatedAt: now,
            deletedAt: entry.deletedAt
        )
    }

    private func warningsJSON(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty,
              let data = try? JSONEncoder().encode(warnings) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func traceJSON(_ trace: TextProcessingTrace?, diagnosticID: String) -> String? {
        guard let trace else {
            return nil
        }
        LLMDiagnosticCapture.shared.capture(taskID: diagnosticID, trace: trace)
        guard let data = try? JSONEncoder().encode(trace.safeForPersistence()) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static let dayIDFormatter = ISO8601DateFormatter()
}

private extension HomeHistoryItem {
    init(entry: DictationHistoryEntry) {
        self.init(
            id: entry.id,
            finalText: entry.finalText,
            rawText: entry.rawText,
            appName: entry.targetAppName,
            appBundleID: entry.targetAppBundleID,
            charCount: entry.charCount,
            cpm: entry.cpm,
            createdAt: entry.createdAt,
            taskMode: nil,
            taskStatus: nil
        )
    }

    init(task: VoiceTask) {
        self.init(
            id: task.id,
            finalText: task.finalText ?? "",
            rawText: task.rawTranscript ?? "",
            appName: task.targetAppName,
            appBundleID: task.targetAppBundleID,
            charCount: task.finalText?.count ?? task.rawTranscript?.count ?? 0,
            cpm: 0,
            createdAt: task.createdAt,
            taskMode: task.mode,
            taskStatus: task.status
        )
    }
}

extension HomeHistoryItem {
    var hasTextVariants: Bool {
        rawText != finalText
    }

    func text(for variant: HomeHistoryTextVariant) -> String {
        switch variant {
        case .final:
            return finalText
        case .raw:
            return rawText
        }
    }
}

private extension HomeHistoryDetail {
    func replacingTrace(_ diagnosticTrace: TextProcessingTrace?) -> HomeHistoryDetail {
        guard let diagnosticTrace else {
            return self
        }
        return HomeHistoryDetail(
            id: id,
            rawText: rawText,
            finalText: finalText,
            language: language,
            asrProviderID: asrProviderID,
            llmProviderID: llmProviderID,
            styleID: styleID,
            appName: appName,
            appBundleID: appBundleID,
            durationMS: durationMS,
            charCount: charCount,
            cpm: cpm,
            warnings: warnings,
            trace: diagnosticTrace,
            createdAt: createdAt,
            updatedAt: updatedAt,
            taskMode: taskMode,
            taskStatus: taskStatus,
            windowTitle: windowTitle,
            contextPreview: contextPreview,
            outputResultRaw: outputResultRaw
        )
    }

    var recoverableTextForCopy: String? {
        if !finalText.isEmpty {
            return finalText
        }
        if !rawText.isEmpty {
            return rawText
        }
        return nil
    }

    var originalDictationTarget: DictationTarget? {
        guard appBundleID != nil || appName != nil || windowTitle != nil else {
            return nil
        }
        return DictationTarget(
            bundleID: appBundleID,
            appName: appName,
            windowTitle: windowTitle
        )
    }

    var outputResultKind: OutputResultKind? {
        OutputResultKind.decodePersisted(from: outputResultRaw)
    }

    init(entry: DictationHistoryEntry) {
        self.init(
            id: entry.id,
            rawText: entry.rawText,
            finalText: entry.finalText,
            language: entry.language,
            asrProviderID: entry.asrProviderID,
            llmProviderID: entry.llmProviderID,
            styleID: entry.styleID,
            appName: entry.targetAppName,
            appBundleID: entry.targetAppBundleID,
            durationMS: entry.durationMS,
            charCount: entry.charCount,
            cpm: entry.cpm,
            warnings: Self.decodeWarnings(entry.processingWarningsJSON),
            trace: Self.decodeTrace(entry.processingTraceJSON),
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            taskMode: nil,
            taskStatus: nil,
            windowTitle: nil,
            contextPreview: nil,
            outputResultRaw: nil
        )
    }

    init(task: VoiceTask) {
        let contextPreview = Self.decodeContextPreview(task.contextJson)
        self.init(
            id: task.id,
            rawText: task.rawTranscript ?? "",
            finalText: task.finalText ?? "",
            language: "",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: task.targetAppName,
            appBundleID: task.targetAppBundleID,
            durationMS: 0,
            charCount: task.finalText?.count ?? 0,
            cpm: 0,
            warnings: task.warnings,
            trace: Self.decodeTrace(task.trace),
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            taskMode: task.mode,
            taskStatus: task.status,
            windowTitle: task.targetWindowTitle,
            contextPreview: contextPreview,
            outputResultRaw: task.outputResult
        )
    }

    private static func decodeContextPreview(_ json: String?) -> String? {
        guard let json,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ContextSnapshot.self, from: data) else {
            return nil
        }
        var parts: [String] = []
        if let visible = snapshot.visibleText {
            parts.append(String(visible.prefix(200)))
        }
        if let selected = snapshot.selectedText {
            parts.append(String(selected.prefix(200)))
        }
        if let input = snapshot.inputAreaText {
            parts.append(String(input.prefix(200)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n---\n")
    }

    private static func decodeWarnings(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8),
              let warnings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return warnings
    }

    private static func decodeTrace(_ json: String?) -> TextProcessingTrace? {
        guard let data = json?.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder()
            .decode(TextProcessingTrace.self, from: data)
            .safeForPersistence()
    }
}
