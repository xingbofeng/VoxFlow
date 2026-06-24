import AppKit
import Combine
import Foundation

struct HomeDashboardStats: Equatable {
    var totalAssets = 0
    var focusedAssets = 0
    var sourceBreakdown = HomeSourceBreakdown()
    var reusableAssets = 0
}

struct HomeSourceBreakdown: Equatable {
    var dictation = 0
    var screenshot = 0
    var clipboard = 0

    var total: Int {
        dictation + screenshot + clipboard
    }

    var summaryText: String {
        guard total > 0 else { return "暂无" }
        return [
            ("语音", dictation),
            ("截图", screenshot),
            ("剪切板", clipboard)
        ]
        .filter { $0.1 > 0 }
        .map { "\($0.0) \($0.1)" }
        .joined(separator: " / ")
    }

    mutating func increment(source: AssetSource) {
        switch source {
        case .dictation:
            dictation += 1
        case .screenshot:
            screenshot += 1
        case .clipboard:
            clipboard += 1
        }
    }
}

struct HomeActivityDay: Equatable, Identifiable {
    let date: Date
    let assetCount: Int
    let sourceBreakdown: HomeSourceBreakdown
    let level: Int

    var id: Date { date }
}

struct HomeActivitySummary: Equatable {
    var days: [HomeActivityDay] = []
    var thisWeekAssets = 0
    var maxDailyAssets = 0
}

struct HomeAssetItem: Equatable, Identifiable {
    let asset: AssetItem
    let voiceKind: VoiceAssetKind?

    init(asset: AssetItem, voiceKind: VoiceAssetKind? = nil) {
        self.asset = asset
        self.voiceKind = voiceKind
    }

    var id: String { asset.id }
    var title: String { asset.title }
    var previewText: String {
        asset.previewText
            ?? asset.text
            ?? asset.url
            ?? asset.filePath
            ?? asset.colorValue
            ?? ""
    }
    var imagePath: String? { asset.imagePath }
    var createdAt: Date { asset.createdAt }
    var sourceTitle: String {
        if let voiceKind {
            switch voiceKind {
            case .dictation:
                return "语音"
            case .agentCompose:
                return "任务助手"
            case .agentDispatch:
                return "AI 编程"
            case .selectionTranslation:
                return "划词翻译"
            case .selectionSummary:
                return "划词总结"
            case .selectionAgent:
                return "划词任务助手"
            }
        }
        switch asset.source {
        case .dictation:
            return "语音"
        case .screenshot:
            return "截图"
        case .clipboard:
            return "剪切板"
        }
    }
    var contentTypeTitle: String {
        switch asset.contentType {
        case .text:
            return "文本"
        case .image:
            return "图片"
        case .file:
            return "文件"
        case .link:
            return "链接"
        case .color:
            return "颜色"
        }
    }
    var systemImage: String {
        switch asset.contentType {
        case .text:
            return asset.source == .dictation ? "waveform" : "doc.text"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .link:
            return "link"
        case .color:
            return "paintpalette"
        }
    }
}

struct HomeAssetGroup: Equatable, Identifiable {
    let id: String
    let title: String
    let date: Date
    let items: [HomeAssetItem]
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

enum HomeDetailSelection: Equatable, Identifiable {
    case voice(HomeHistoryDetail)
    case asset(HomeAssetItem)

    var id: String {
        switch self {
        case .voice(let detail):
            return "voice-\(detail.id)"
        case .asset(let detail):
            return "asset-\(detail.id)"
        }
    }
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
    @Published private(set) var assetGroups: [HomeAssetGroup] = []
    @Published private(set) var totalAssetCount = 0
    @Published private(set) var selectedHomeDetail: HomeDetailSelection?
    @Published private(set) var selectedAssetIDs: Set<String> = []
    @Published private(set) var isReprocessing = false
    @Published private(set) var assetCurrentPage = 1
    @Published private(set) var pageSize: Int
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
    private let historyPageSize: Int
    private let voiceTaskRepository: VoiceTaskRepository
    private var cancellables: Set<AnyCancellable> = []
    private var hasLoaded = false

    var openHistoryDetailRequests: AnyPublisher<String, Never> {
        environment.openHistoryDetailPublisher
    }

    var selectedDetail: HomeHistoryDetail? {
        guard case .voice(let detail) = selectedHomeDetail else {
            return nil
        }
        return detail
    }

    var selectedAssetDetail: HomeAssetItem? {
        guard case .asset(let detail) = selectedHomeDetail else {
            return nil
        }
        return detail
    }

    init(
        environment: any AppServiceProviding & AppEventRouting,
        clipboardWriter: ClipboardWriting = GeneralPasteboardWriter(),
        outputService: (any OutputService)? = nil,
        targetProvider: (any DictationTargetProviding)? = nil,
        textPipeline: (any TextProcessing)? = nil,
        calendar: Calendar = .current,
        historyLimit: Int = 1_000,
        historyPageSize: Int = 20
    ) {
        self.environment = environment
        self.clipboardWriter = clipboardWriter
        self.outputService = outputService
        self.targetProvider = targetProvider
        self.textPipeline = textPipeline ?? Self.makeDefaultTextPipeline(environment: environment)
        self.calendar = calendar
        self.historyPageSize = max(1, historyPageSize)
        self.pageSize = max(1, historyPageSize)
        self.voiceTaskRepository = VoiceTaskRepository(
            databaseQueue: environment.databaseQueue,
            clock: environment.clock
        )
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
            try reloadAssetPage()
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
        assetCurrentPage = 1
        refreshAssetPage()
    }

    func selectActivityDay(_ date: Date) {
        selectedActivityDate = calendar.startOfDay(for: date)
        assetCurrentPage = 1
        refreshScopedDashboardState()
    }

    func clearActivityDaySelection() {
        selectedActivityDate = nil
        assetCurrentPage = 1
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

    func copyAssetItem(id: String) {
        guard let item = assetGroups.flatMap(\.items).first(where: { $0.id == id }) else {
            return
        }
        let text = item.previewText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "该资产没有可复制文本。"
            return
        }
        clipboardWriter.copy(text)
        lastError = nil
        lastActionMessage = "已复制资产内容"
        lastActionTone = .success
    }

    func deleteAssetItem(id: String) {
        do {
            let asset = try environment.assetRepository.asset(id: id)
            try environment.assetRepository.softDelete(id: id, deletedAt: environment.clock.now)
            try deleteBackingVoiceRecordIfNeeded(for: asset)
            try reloadAssetPage()
            selectedAssetIDs.remove(id)
            if selectedAssetDetail?.id == id {
                selectedHomeDetail = nil
            }
            lastError = nil
            lastActionMessage = "已删除资产"
            lastActionTone = .destructive
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectAssetItem(id: String) {
        do {
            guard let asset = try environment.assetRepository.asset(id: id) else {
                selectedHomeDetail = nil
                lastError = "未找到资产。"
                return
            }
            if selectVoiceDetailIfAvailable(for: asset) {
                lastError = nil
                return
            }
            selectedHomeDetail = .asset(homeAssetItem(for: asset))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleAssetSelection(id: String) {
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    func toggleVisibleAssetSelection() {
        if visibleAssetIDs.isEmpty {
            return
        }
        if areVisibleAssetsSelected {
            selectedAssetIDs.subtract(visibleAssetIDs)
        } else {
            selectedAssetIDs.formUnion(visibleAssetIDs)
        }
    }

    func deleteSelectedAssets() {
        let ids = selectedAssetIDs
        guard !ids.isEmpty else { return }
        do {
            let assets = try ids.compactMap { try environment.assetRepository.asset(id: $0) }
            try environment.assetRepository.softDelete(ids: Array(ids), deletedAt: environment.clock.now)
            for asset in assets {
                try deleteBackingVoiceRecordIfNeeded(for: asset)
            }
            selectedAssetIDs = []
            selectedHomeDetail = nil
            try reloadAssetPage()
            lastError = nil
            lastActionMessage = "已删除 \(ids.count) 条资产"
            lastActionTone = .destructive
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearAllAssets() {
        do {
            let assets = try allAssetsForDeletion()
            try environment.assetRepository.clearAll(deletedAt: environment.clock.now)
            for asset in assets {
                try deleteBackingVoiceRecordIfNeeded(for: asset)
            }
            selectedAssetIDs = []
            selectedHomeDetail = nil
            try reloadAssetPage()
            lastError = nil
            lastActionMessage = "已清空资产"
            lastActionTone = .destructive
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectHistoryItem(id: String) {
        do {
            if let entry = try environment.historyRepository.entry(id: id), entry.deletedAt == nil {
                selectedHomeDetail = .voice(
                    HomeHistoryDetail(entry: entry)
                        .replacingTrace(LLMDiagnosticCapture.shared.trace(taskID: id))
                )
                lastError = nil
                return
            }
            if let task = try voiceTaskRepository.fetch(id: id) {
                selectedHomeDetail = .voice(
                    HomeHistoryDetail(task: task)
                        .replacingTrace(LLMDiagnosticCapture.shared.trace(taskID: id))
                )
                lastError = nil
                return
            }
            selectedHomeDetail = nil
            lastError = "未找到历史记录。"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearSelectedHomeDetail() {
        selectedHomeDetail = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    var totalAssetPages: Int {
        max(1, Int(ceil(Double(totalAssetCount) / Double(pageSize))))
    }

    var visibleAssetIDs: Set<String> {
        Set(assetGroups.flatMap(\.items).map(\.id))
    }

    var areVisibleAssetsSelected: Bool {
        !visibleAssetIDs.isEmpty && visibleAssetIDs.isSubset(of: selectedAssetIDs)
    }

    var canGoToPreviousAssetPage: Bool { assetCurrentPage > 1 }
    var canGoToNextAssetPage: Bool { assetCurrentPage < totalAssetPages }

    func goToAssetPage(_ page: Int) {
        let target = min(max(1, page), totalAssetPages)
        guard target != assetCurrentPage else { return }
        assetCurrentPage = target
        do {
            try reloadAssetPage()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func previousAssetPage() {
        goToAssetPage(assetCurrentPage - 1)
    }

    func nextAssetPage() {
        goToAssetPage(assetCurrentPage + 1)
    }

    func updateAssetPageSize(_ size: Int) {
        guard size > 0, size != pageSize else { return }
        pageSize = size
        assetCurrentPage = 1
        refreshAssetPage()
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

    var focusedAssetsTitle: String {
        guard let selectedActivityDate else {
            return "今日新增"
        }
        return "\(dateTitle(for: selectedActivityDate))新增"
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
                selectedHomeDetail = nil
                lastError = "未找到历史记录。"
                return
            }

            let result = await textPipeline.process(entry.rawText)
            let finalText = normalizedFinalText(from: result, fallback: entry.rawText)
            let updatedEntry = updatedHistoryEntry(from: entry, finalText: finalText, processingResult: result)
            try environment.historyRepository.save(updatedEntry)
            try updateDictationAssetIfAvailable(for: updatedEntry)
            environment.notifyHistoryDidChange()
            load()
            selectedHomeDetail = .voice(HomeHistoryDetail(entry: updatedEntry))
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
            try reloadAssetPage()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshAssetPage() {
        do {
            try reloadAssetPage()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reloadDashboardAggregate() throws {
        try reloadAssetDashboardAggregate()
    }

    private func reloadAssetDashboardAggregate() throws {
        let page = try environment.assetRepository.page(
            query: AssetQuery(limit: 10_000, offset: 0)
        )

        let today = calendar.startOfDay(for: environment.clock.now)
        let focusDay = selectedActivityDate.map(calendar.startOfDay(for:)) ?? today
        let currentWeekStart = startOfWeek(containing: today)
        let activityStart = calendar.date(byAdding: .day, value: -51 * 7, to: currentWeekStart)
            ?? currentWeekStart
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? today
        let focusedItems = page.items.filter { calendar.isDate($0.createdAt, inSameDayAs: focusDay) }
        let scopedItems = selectedActivityDate == nil ? page.items : focusedItems

        var assetCountsByDay: [Date: Int] = [:]
        var sourceBreakdownByDay: [Date: HomeSourceBreakdown] = [:]
        for item in page.items {
            let day = calendar.startOfDay(for: item.createdAt)
            guard day >= activityStart, day <= today else { continue }
            assetCountsByDay[day, default: 0] += 1
            sourceBreakdownByDay[day, default: HomeSourceBreakdown()].increment(source: item.source)
        }
        stats = HomeDashboardStats(
            totalAssets: page.totalCount,
            focusedAssets: focusedItems.count,
            sourceBreakdown: Self.sourceBreakdown(from: scopedItems),
            reusableAssets: scopedItems.filter(Self.isReusableAsset).count
        )

        let maxDailyAssets = assetCountsByDay.values.max() ?? 0
        let dayCount = calendar.dateComponents([.day], from: activityStart, to: endOfWeek).day.map { $0 + 1 } ?? 0
        let days = (0..<dayCount).compactMap { offset -> HomeActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: activityStart) else {
                return nil
            }
            let assetCount = assetCountsByDay[day, default: 0]
            return HomeActivityDay(
                date: day,
                assetCount: assetCount,
                sourceBreakdown: sourceBreakdownByDay[day, default: HomeSourceBreakdown()],
                level: activityLevel(for: assetCount, maxDailyAssets: maxDailyAssets)
            )
        }
        let thisWeekAssets = assetCountsByDay
            .filter { day, _ in day >= currentWeekStart && day <= today }
            .reduce(0) { $0 + $1.value }
        activity = HomeActivitySummary(
            days: days,
            thisWeekAssets: thisWeekAssets,
            maxDailyAssets: maxDailyAssets
        )
    }

    private static func sourceBreakdown(from items: [AssetItem]) -> HomeSourceBreakdown {
        items.reduce(into: HomeSourceBreakdown()) { result, item in
            result.increment(source: item.source)
        }
    }

    private static func isReusableAsset(_ item: AssetItem) -> Bool {
        switch item.contentType {
        case .text:
            return item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .image:
            return item.imagePath?.isEmpty == false
                || item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .file:
            return item.filePath?.isEmpty == false
        case .link:
            return item.url?.isEmpty == false
                || item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .color:
            return item.colorValue?.isEmpty == false
        }
    }

    private func reloadAssetPage() throws {
        let dateRange = selectedActivityDate.map { day -> (Date, Date?) in
            let start = calendar.startOfDay(for: day)
            return (start, calendar.date(byAdding: .day, value: 1, to: start))
        }
        var page = try environment.assetRepository.page(
            query: AssetQuery(
                searchText: searchText,
                startDate: dateRange?.0,
                endDate: dateRange?.1,
                limit: pageSize,
                offset: (assetCurrentPage - 1) * pageSize
            )
        )
        totalAssetCount = page.totalCount
        let lastPage = totalAssetPages
        if assetCurrentPage > lastPage {
            assetCurrentPage = lastPage
            page = try environment.assetRepository.page(
                query: AssetQuery(
                    searchText: searchText,
                    startDate: dateRange?.0,
                    endDate: dateRange?.1,
                    limit: pageSize,
                    offset: (assetCurrentPage - 1) * pageSize
                )
            )
            totalAssetCount = page.totalCount
        }
        assetGroups = makeAssetGroups(items: page.items)
    }

    private func selectVoiceDetailIfAvailable(for asset: AssetItem) -> Bool {
        guard asset.source == .dictation,
              let recordID = Self.voiceRecordID(fromAssetID: asset.id) else {
            return false
        }
        do {
            if let entry = try environment.historyRepository.entry(id: recordID), entry.deletedAt == nil {
                selectedHomeDetail = .voice(
                    HomeHistoryDetail(entry: entry)
                        .replacingTrace(LLMDiagnosticCapture.shared.trace(taskID: recordID))
                )
                return true
            }
            if let task = try voiceTaskRepository.fetch(id: recordID) {
                selectedHomeDetail = .voice(
                    HomeHistoryDetail(task: task)
                        .replacingTrace(LLMDiagnosticCapture.shared.trace(taskID: recordID))
                )
                return true
            }
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    private static func voiceRecordID(fromAssetID id: String) -> String? {
        let prefix = "dictation-"
        guard id.hasPrefix(prefix) else { return nil }
        let recordID = String(id.dropFirst(prefix.count))
        return recordID.isEmpty ? nil : recordID
    }

    private func makeAssetGroups(items: [AssetItem]) -> [HomeAssetGroup] {
        let grouped = Dictionary(grouping: items.map(homeAssetItem(for:))) { item in
            calendar.startOfDay(for: item.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? [])
                .sorted { $0.createdAt > $1.createdAt }
            return HomeAssetGroup(
                id: Self.dayIDFormatter.string(from: day),
                title: title(for: day, preferExplicitDate: selectedActivityDate != nil),
                date: day,
                items: items
            )
        }
    }

    private func homeAssetItem(for asset: AssetItem) -> HomeAssetItem {
        HomeAssetItem(asset: asset, voiceKind: voiceKind(for: asset))
    }

    private func voiceKind(for asset: AssetItem) -> VoiceAssetKind? {
        guard asset.source == .dictation,
              let recordID = Self.voiceRecordID(fromAssetID: asset.id) else {
            return nil
        }
        if let entry = try? environment.historyRepository.entry(id: recordID),
           entry.deletedAt == nil {
            return .dictation
        }
        guard let task = try? voiceTaskRepository.fetch(id: recordID) else {
            return voiceKindFromRawVoiceTaskMode(id: recordID)
        }
        return VoiceAssetKind(rawValue: task.mode.rawValue)
    }

    private func voiceKindFromRawVoiceTaskMode(id: String) -> VoiceAssetKind? {
        try? environment.databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT mode
                FROM voice_tasks
                WHERE id = ? AND status != 'inProgress'
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                return nil
            }
            return VoiceAssetKind(rawValue: statement.columnString(at: 0))
        }
    }

    private func deleteBackingVoiceRecordIfNeeded(for asset: AssetItem?) throws {
        guard let asset,
              asset.source == .dictation,
              let recordID = Self.voiceRecordID(fromAssetID: asset.id) else {
            return
        }
        if let entry = try environment.historyRepository.entry(id: recordID),
           entry.deletedAt == nil {
            try environment.historyRepository.softDelete(id: recordID, deletedAt: environment.clock.now)
            return
        }
        if try voiceTaskRepository.fetch(id: recordID) != nil {
            try voiceTaskRepository.delete(id: recordID)
        }
    }

    private func allAssetsForDeletion() throws -> [AssetItem] {
        var items: [AssetItem] = []
        while true {
            let page = try environment.assetRepository.page(
                query: AssetQuery(limit: 500, offset: items.count)
            )
            guard !page.items.isEmpty else { break }
            items.append(contentsOf: page.items)
        }
        return items
    }

    private func updateDictationAssetIfAvailable(for entry: DictationHistoryEntry) throws {
        let assetID = "dictation-\(entry.id)"
        guard let asset = try environment.assetRepository.asset(id: assetID) else {
            return
        }
        let updatedAsset = AssetItem(
            id: asset.id,
            source: asset.source,
            contentType: asset.contentType,
            title: entry.finalText,
            previewText: entry.finalText,
            text: entry.finalText,
            rawText: entry.rawText,
            imagePath: asset.imagePath,
            filePath: asset.filePath,
            url: asset.url,
            colorValue: asset.colorValue,
            sourceAppName: asset.sourceAppName,
            sourceAppBundleID: asset.sourceAppBundleID,
            contentHash: asset.contentHash,
            captureReason: asset.captureReason,
            metadataJSON: asset.metadataJSON,
            createdAt: asset.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: asset.deletedAt
        )
        try environment.assetRepository.save(updatedAsset)
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

    private func activityLevel(for assetCount: Int, maxDailyAssets: Int) -> Int {
        guard assetCount > 0, maxDailyAssets > 0 else {
            return 0
        }

        let ratio = Double(assetCount) / Double(maxDailyAssets)
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
