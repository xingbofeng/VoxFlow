import Combine
import Foundation

enum PaletteMode: Equatable, Sendable {
    case home
    case recentAssets
    case fileSearch
}

enum PaletteCommand: String, Equatable, Sendable {
    case recentAssets
    case assetHistory
    case searchFiles
    case screenshotOCR
    case startAgentCompose
    case startAgentDispatch
    case startDictation
}

struct PaletteHomeResult: Equatable, Identifiable, Sendable {
    let command: PaletteCommand
    let title: String
    let subtitle: String

    var id: PaletteCommand { command }
}

enum PaletteAssetTypeFilter: Equatable, CaseIterable, Sendable {
    case all
    case text
    case image
    case file
    case link
    case color

    var title: String {
        switch self {
        case .all:
            return L10n.localize("palette.filter.all", comment: "")
        case .text:
            return L10n.localize("palette.content_type.text", comment: "")
        case .image:
            return L10n.localize("palette.content_type.image", comment: "")
        case .file:
            return L10n.localize("palette.content_type.file", comment: "")
        case .link:
            return L10n.localize("palette.content_type.link", comment: "")
        case .color:
            return L10n.localize("palette.content_type.color", comment: "")
        }
    }

    var contentTypes: Set<AssetContentType> {
        switch self {
        case .all:
            return []
        case .text:
            return [.text]
        case .image:
            return [.image]
        case .file:
            return [.file]
        case .link:
            return [.link]
        case .color:
            return [.color]
        }
    }
}

enum PaletteDefaultAction: Equatable, Sendable {
    case assetAction(AssetAction)
    case openURL(String)
}

enum PaletteKeyboardAction: Equatable, Sendable {
    case none
    case activateCommand(PaletteCommand)
    case openApplication(path: String, itemID: PaletteRootItemID)
    case performAssetAction(PaletteDefaultAction, assetID: String)
    case performFileAction(PaletteFileAction, fileID: String)
    case askAI(prompt: String)
    case translate(text: String)
    case activateQuicklink(PaletteQuicklink, query: String)
    case openURL(String)
}

enum PaletteViewModelError: Error, Equatable {
    case noSelectedAsset
    case unsupportedCommand
}

@MainActor
final class PaletteViewModel: ObservableObject {
    private let repository: any AssetRepository
    private let actionService: AssetActionService?
    private let favoritesStore: any PaletteFavoritesStoring
    private let usageStore: any PaletteUsageStoring
    private let searchIndex: PaletteRootSearchIndex
    private let composer: PaletteRootComposer
    private let fileSearchService: any PaletteFileSearching
    private let recentFileProvider: any PaletteRecentFileProviding
    private let fileSearchCache: PaletteFileSearchCache
    private let fileMetadataProvider: any PaletteFileMetadataProviding
    private let fileSearchDebounceNanoseconds: UInt64
    private let now: () -> Date
    private let rootItems: [PaletteRootItem]
    private var fileSearchTask: Task<Void, Never>?
    private var fileMetadataTask: Task<Void, Never>?

    /// 是否启用 Palette 动态能力（问 AI / Quicklinks / URL 打开）。
    /// 默认 false 保留纯 launcher 行为；生产环境由装配层显式传 true 启用。
    let showsAskAI: Bool

    @Published private(set) var mode: PaletteMode = .home
    @Published private(set) var selectedTypeFilter: PaletteAssetTypeFilter = .all
    @Published private(set) var assets: [AssetItem] = []
    @Published private(set) var selectedHomeResultIndex: Int = 0
    @Published private(set) var selectedRootItemID: PaletteRootItemID?
    @Published private(set) var selectedAssetIndex: Int = 0
    @Published private(set) var selectedFileIndex: Int = 0
    @Published private(set) var selectedActionIndex: Int = 0
    @Published private(set) var searchText: String = ""
    @Published private(set) var fileResults: [PaletteFileItem] = []
    @Published private(set) var fileSearchState: PaletteFileSearchState = .idle
    @Published private(set) var selectedFileMetadata: PaletteFileMetadata?
    @Published private(set) var searchFocusRequestID: Int = 0
    @Published var isActionPanelPresented = false
    @Published var isTypeFilterPresented = false

    init(
        repository: any AssetRepository,
        actionService: AssetActionService? = nil,
        applicationProvider: (any InstalledApplicationProviding)? = nil,
        favoritesStore: (any PaletteFavoritesStoring)? = nil,
        usageStore: (any PaletteUsageStoring)? = nil,
        searchIndex: PaletteRootSearchIndex = PaletteRootSearchIndex(),
        fileSearchService: (any PaletteFileSearching)? = nil,
        recentFileProvider: (any PaletteRecentFileProviding)? = nil,
        fileSearchCache: PaletteFileSearchCache = PaletteFileSearchCache(),
        fileMetadataProvider: (any PaletteFileMetadataProviding)? = nil,
        fileSearchDebounceNanoseconds: UInt64 = 200_000_000,
        showsAskAI: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.actionService = actionService
        self.favoritesStore = favoritesStore ?? UserDefaultsPaletteFavoritesStore()
        self.usageStore = usageStore ?? UserDefaultsPaletteUsageStore()
        self.searchIndex = searchIndex
        self.fileSearchService = fileSearchService ?? SystemPaletteFileSearchService()
        self.recentFileProvider = recentFileProvider ?? SystemPaletteRecentFileProvider()
        self.fileSearchCache = fileSearchCache
        self.fileMetadataProvider = fileMetadataProvider ?? SystemPaletteFileMetadataProvider()
        self.fileSearchDebounceNanoseconds = fileSearchDebounceNanoseconds
        self.showsAskAI = showsAskAI
        self.composer = PaletteRootComposer(searchIndex: searchIndex, now: now)
        self.now = now
        self.rootItems = PaletteCommand.rootCommands.map(PaletteRootItem.command)
            + (applicationProvider?.scanInstalledApplications().map(PaletteRootItem.application) ?? [])
        syncSelectedRootItemID()
    }

    var searchPlaceholder: String {
        switch mode {
        case .home:
            return L10n.localize("palette.search.home_placeholder", comment: "")
        case .recentAssets:
            return L10n.localize("palette.search.assets_placeholder", comment: "")
        case .fileSearch:
            return L10n.localize("palette.search.files_placeholder", comment: "")
        }
    }

    var homeResults: [PaletteHomeResult] {
        visibleRootItems.compactMap { item in
            guard case let .command(command) = item.activation else { return nil }
            return PaletteHomeResult(command: command, title: item.title, subtitle: item.subtitle)
        }
    }

    var rootSections: [PaletteRootSection] {
        composer.sections(
            for: rootItems,
            query: searchText,
            favoriteIDs: favoritesStore.favoriteIDs(),
            usageStore: usageStore,
            includesDynamic: showsAskAI
        )
    }

    var visibleRootItems: [PaletteRootItem] {
        rootSections.flatMap(\.items)
    }

    var homeResultListIdentity: String {
        visibleRootItems.map(\.id.rawValue).joined(separator: "|")
    }

    var typeFilters: [PaletteAssetTypeFilter] {
        PaletteAssetTypeFilter.allCases
    }

    func activate(_ command: PaletteCommand) throws {
        switch command {
        case .recentAssets, .assetHistory:
            mode = .recentAssets
            selectedTypeFilter = .all
            searchText = ""
            selectedAssetIndex = 0
            selectedActionIndex = 0
            isActionPanelPresented = false
            isTypeFilterPresented = false
            try reloadAssets()
        case .searchFiles:
            mode = .fileSearch
            selectedTypeFilter = .all
            searchText = ""
            selectedFileIndex = 0
            selectedActionIndex = 0
            isActionPanelPresented = false
            isTypeFilterPresented = false
            loadRecentFiles()
        case .screenshotOCR, .startAgentCompose, .startAgentDispatch, .startDictation:
            throw PaletteViewModelError.unsupportedCommand
        }
    }

    func goBack() {
        mode = .home
        selectedTypeFilter = .all
        assets = []
        selectedHomeResultIndex = 0
        selectedAssetIndex = 0
        selectedFileIndex = 0
        selectedActionIndex = 0
        searchText = ""
        fileSearchTask?.cancel()
        fileMetadataTask?.cancel()
        fileResults = []
        fileSearchState = .idle
        selectedFileMetadata = nil
        isActionPanelPresented = false
        isTypeFilterPresented = false
        syncSelectedRootItemID()
    }

    func requestSearchFocus() {
        searchFocusRequestID += 1
    }

    func updateSearchText(_ text: String) throws {
        searchText = text
        selectedHomeResultIndex = 0
        isActionPanelPresented = false
        syncSelectedRootItemID()
        switch mode {
        case .home:
            return
        case .recentAssets:
            try reloadAssets()
        case .fileSearch:
            scheduleFileSearch(for: text)
        }
    }

    func selectTypeFilter(_ filter: PaletteAssetTypeFilter) throws {
        selectedTypeFilter = filter
        selectedAssetIndex = 0
        isTypeFilterPresented = false
        isActionPanelPresented = false
        try reloadAssets()
    }

    func selectHomeResult(at index: Int) {
        guard visibleRootItems.indices.contains(index) else { return }
        selectedHomeResultIndex = index
        syncSelectedRootItemID()
    }

    func selectAsset(at index: Int) {
        guard assets.indices.contains(index) else { return }
        selectedAssetIndex = index
        selectedActionIndex = 0
        isActionPanelPresented = false
    }

    func selectFile(at index: Int) {
        guard fileResults.indices.contains(index) else { return }
        selectedFileIndex = index
        selectedActionIndex = 0
        isActionPanelPresented = false
        loadSelectedFileMetadata()
    }

    func moveSelectionDown() {
        switch mode {
        case .home:
            selectedHomeResultIndex = Self.wrappedIndex(after: selectedHomeResultIndex, count: visibleRootItems.count)
            syncSelectedRootItemID()
        case .recentAssets:
            selectedAssetIndex = Self.wrappedIndex(after: selectedAssetIndex, count: assets.count)
            isActionPanelPresented = false
        case .fileSearch:
            selectedFileIndex = Self.wrappedIndex(after: selectedFileIndex, count: fileResults.count)
            selectedActionIndex = 0
            isActionPanelPresented = false
            loadSelectedFileMetadata()
        }
    }

    func moveSelectionUp() {
        switch mode {
        case .home:
            selectedHomeResultIndex = Self.wrappedIndex(before: selectedHomeResultIndex, count: visibleRootItems.count)
            syncSelectedRootItemID()
        case .recentAssets:
            selectedAssetIndex = Self.wrappedIndex(before: selectedAssetIndex, count: assets.count)
            isActionPanelPresented = false
        case .fileSearch:
            selectedFileIndex = Self.wrappedIndex(before: selectedFileIndex, count: fileResults.count)
            selectedActionIndex = 0
            isActionPanelPresented = false
            loadSelectedFileMetadata()
        }
    }

    func primaryKeyboardAction() -> PaletteKeyboardAction {
        switch mode {
        case .home:
            guard let selectedRootItem else {
                return .none
            }
            switch selectedRootItem.activation {
            case let .command(command):
                return .activateCommand(command)
            case let .application(application):
                return .openApplication(path: application.path, itemID: selectedRootItem.id)
            case let .askAI(prompt):
                return .askAI(prompt: prompt)
            case let .translate(text):
                return .translate(text: text)
            case let .quicklink(link, query):
                return .activateQuicklink(link, query: query)
            case let .openURL(url):
                return .openURL(url)
            }
        case .recentAssets:
            guard let selectedAsset else {
                return .none
            }
            return .performAssetAction(defaultAction(for: selectedAsset), assetID: selectedAsset.id)
        case .fileSearch:
            guard let selectedFile else {
                return .none
            }
            return .performFileAction(.open, fileID: selectedFile.id)
        }
    }

    func presentActionPanel() {
        switch mode {
        case .home:
            guard selectedRootItem != nil else {
                isActionPanelPresented = false
                return
            }
        case .recentAssets:
            guard selectedAsset != nil else {
                isActionPanelPresented = false
                return
            }
        case .fileSearch:
            guard selectedFile != nil else {
                isActionPanelPresented = false
                return
            }
        }
        selectedActionIndex = 0
        isActionPanelPresented = true
        isTypeFilterPresented = false
    }

    func toggleActionPanel() {
        if isActionPanelPresented {
            isActionPanelPresented = false
        } else {
            presentActionPanel()
        }
    }

    func dismissActionPanel() {
        isActionPanelPresented = false
    }

    func moveActionSelectionDown() {
        if mode == .home {
            let actions = rootActionPanelActionsForSelectedRootItem()
            guard !actions.isEmpty else { return }
            selectedActionIndex = Self.wrappedIndex(after: selectedActionIndex, count: actions.count)
            return
        }
        if mode == .fileSearch {
            let actions = fileActionPanelActionsForSelectedFile()
            guard !actions.isEmpty else { return }
            selectedActionIndex = Self.wrappedIndex(after: selectedActionIndex, count: actions.count)
            return
        }
        guard let actions = try? actionPanelActionsForSelectedAsset(), !actions.isEmpty else { return }
        selectedActionIndex = Self.wrappedIndex(after: selectedActionIndex, count: actions.count)
    }

    func moveActionSelectionUp() {
        if mode == .home {
            let actions = rootActionPanelActionsForSelectedRootItem()
            guard !actions.isEmpty else { return }
            selectedActionIndex = Self.wrappedIndex(before: selectedActionIndex, count: actions.count)
            return
        }
        if mode == .fileSearch {
            let actions = fileActionPanelActionsForSelectedFile()
            guard !actions.isEmpty else { return }
            selectedActionIndex = Self.wrappedIndex(before: selectedActionIndex, count: actions.count)
            return
        }
        guard let actions = try? actionPanelActionsForSelectedAsset(), !actions.isEmpty else { return }
        selectedActionIndex = Self.wrappedIndex(before: selectedActionIndex, count: actions.count)
    }

    func selectedActionPanelAction() -> AssetAction? {
        guard let actions = try? actionPanelActionsForSelectedAsset(),
              actions.indices.contains(selectedActionIndex) else {
            return nil
        }
        return actions[selectedActionIndex]
    }

    func fileActionPanelActionsForSelectedFile() -> [PaletteFileAction] {
        guard selectedFile != nil else { return [] }
        return [.open, .showInFinder, .quickLook, .copyPath, .copyName]
    }

    func selectedFileActionPanelAction() -> PaletteFileAction? {
        let actions = fileActionPanelActionsForSelectedFile()
        guard actions.indices.contains(selectedActionIndex) else { return nil }
        return actions[selectedActionIndex]
    }

    func rootActionPanelActionsForSelectedRootItem() -> [PaletteRootAction] {
        guard let selectedRootItem else { return [] }
        return [
            .open,
            favoritesStore.isFavorite(selectedRootItem.id) ? .removeFavorite : .addFavorite,
        ]
    }

    func selectedRootActionPanelAction() -> PaletteRootAction? {
        let actions = rootActionPanelActionsForSelectedRootItem()
        guard actions.indices.contains(selectedActionIndex) else { return nil }
        return actions[selectedActionIndex]
    }

    func performRootAction(_ action: PaletteRootAction) -> PaletteKeyboardAction {
        guard let selectedRootItem else { return .none }
        switch action {
        case .open:
            return primaryKeyboardAction()
        case .addFavorite:
            favoritesStore.addFavorite(selectedRootItem.id)
            syncSelectedRootItemID()
            selectedActionIndex = 0
            isActionPanelPresented = false
            return .none
        case .removeFavorite:
            favoritesStore.removeFavorite(selectedRootItem.id)
            selectedHomeResultIndex = min(selectedHomeResultIndex, max(visibleRootItems.count - 1, 0))
            syncSelectedRootItemID()
            selectedActionIndex = 0
            isActionPanelPresented = false
            return .none
        }
    }

    func recordRootActivation(itemID: PaletteRootItemID) {
        usageStore.recordActivation(of: itemID, at: now())
        usageStore.recordSelection(query: searchText, itemID: itemID, at: now())
    }

    func toggleTypeFilter() {
        isTypeFilterPresented.toggle()
        if isTypeFilterPresented {
            isActionPanelPresented = false
        }
    }

    func reloadAssets() throws {
        let page = try repository.page(
            query: AssetQuery(
                searchText: searchText,
                contentTypes: selectedTypeFilter.contentTypes,
                limit: 50,
                offset: 0
            )
        )
        assets = page.items
        selectedAssetIndex = min(selectedAssetIndex, max(assets.count - 1, 0))
    }

    func actionPanelActionsForSelectedAsset() throws -> [AssetAction] {
        guard let asset = selectedAsset else {
            throw PaletteViewModelError.noSelectedAsset
        }
        if let actionService {
            return actionService.availableActions(for: asset)
        }
        return defaultActionList(for: asset)
    }

    func defaultAction(for asset: AssetItem) -> PaletteDefaultAction {
        switch asset.contentType {
        case .file:
            return .assetAction(.pasteFilePath)
        case .link:
            if let url = asset.url?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                return .openURL(url)
            }
            return .assetAction(.paste)
        case .text, .image, .color:
            return .assetAction(.paste)
        }
    }

    var selectedAsset: AssetItem? {
        guard assets.indices.contains(selectedAssetIndex) else { return nil }
        return assets[selectedAssetIndex]
    }

    var selectedFile: PaletteFileItem? {
        guard fileResults.indices.contains(selectedFileIndex) else { return nil }
        return fileResults[selectedFileIndex]
    }

    var selectedHomeResult: PaletteHomeResult? {
        guard let selectedRootItem,
              case let .command(command) = selectedRootItem.activation else {
            return nil
        }
        return PaletteHomeResult(command: command, title: selectedRootItem.title, subtitle: selectedRootItem.subtitle)
    }

    var selectedRootItem: PaletteRootItem? {
        guard visibleRootItems.indices.contains(selectedHomeResultIndex) else { return nil }
        return visibleRootItems[selectedHomeResultIndex]
    }

    var footerPrimaryActionTitle: String {
        if mode == .fileSearch {
            return PaletteFileAction.open.displayTitle
        }
        guard let selectedAsset else {
            return L10n.localize("palette.root_item.action.open", comment: "")
        }
        switch defaultAction(for: selectedAsset) {
        case .openURL:
            return L10n.localize("palette.root_item.action.open_link", comment: "")
        case let .assetAction(action):
            switch action {
            case .pasteFilePath:
                return L10n.localize("palette.root_item.action.paste_file_path", comment: "")
            case .paste:
                return L10n.localize("palette.root_item.action.paste", comment: "")
            default:
                return action.displayTitle
            }
        }
    }

    var footerSelectionTitle: String {
        switch mode {
        case .home:
            return selectedRootItem?.title ?? ""
        case .recentAssets:
            return selectedAsset?.title ?? L10n.localize("palette.root_item.title.recent_assets", comment: "")
        case .fileSearch:
            return selectedFile?.name ?? L10n.localize("palette.root_item.title.search_files", comment: "")
        }
    }

    private func loadRecentFiles() {
        fileSearchTask?.cancel()
        selectedFileIndex = 0
        selectedActionIndex = 0
        isActionPanelPresented = false
        fileSearchState = fileResults.isEmpty ? .searching : .showingRecent
        loadSelectedFileMetadata()
        fileSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let recent = await recentFileProvider.recentFiles(limit: PaletteFileSearchQuery.recentLimit)
            guard !Task.isCancelled else { return }
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            fileResults = recent
            selectedFileIndex = 0
            fileSearchState = recent.isEmpty ? .idle : .showingRecent
            loadSelectedFileMetadata()
        }
    }

    private func scheduleFileSearch(for text: String) {
        let plan = PaletteFileSearchQuery.plan(for: text)
        selectedFileIndex = 0
        selectedActionIndex = 0
        isActionPanelPresented = false
        fileSearchTask?.cancel()

        guard plan.strategy != .recentOnly else {
            loadRecentFiles()
            return
        }

        let cacheKey = PaletteFileSearchCacheKey(
            normalizedQuery: plan.normalizedQuery,
            scope: plan.scope,
            strategy: plan.strategy
        )
        if let cached = fileSearchCache.results(for: cacheKey) {
            fileResults = cached
        } else {
            let filtered = fileResults.filter { item in
                item.name.localizedCaseInsensitiveContains(plan.normalizedQuery)
                    || item.displayPath.localizedCaseInsensitiveContains(plan.normalizedQuery)
            }
            if !filtered.isEmpty {
                fileResults = Array(filtered.prefix(plan.limit))
            }
        }
        loadSelectedFileMetadata()
        fileSearchState = .searching

        fileSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: fileSearchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            let request = PaletteFileSearchRequest(
                query: plan.normalizedQuery,
                scope: plan.scope,
                strategy: plan.strategy,
                limit: plan.limit,
                timeoutMilliseconds: plan.timeoutMilliseconds
            )
            let response = await fileSearchService.search(request)
            guard !Task.isCancelled else { return }
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == plan.normalizedQuery else { return }
            guard response.query == plan.normalizedQuery else { return }
            fileResults = response.items
            selectedFileIndex = min(selectedFileIndex, max(fileResults.count - 1, 0))
            loadSelectedFileMetadata()
            if response.completion == .completed {
                fileSearchCache.store(response.items, for: cacheKey)
                fileSearchState = .completed
            } else if response.completion == .timedOut {
                fileSearchState = .timedOut
            } else {
                fileSearchState = .idle
            }
        }
    }

    private func loadSelectedFileMetadata() {
        fileMetadataTask?.cancel()
        selectedFileMetadata = nil
        guard let file = selectedFile else { return }
        fileMetadataTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let metadata = await fileMetadataProvider.metadata(for: file)
            guard !Task.isCancelled else { return }
            guard selectedFile?.id == file.id else { return }
            selectedFileMetadata = metadata
        }
    }

    private func defaultActionList(for asset: AssetItem) -> [AssetAction] {
        var actions: [AssetAction] = [
            .paste,
            .copy,
            .pasteAndKeepOpen,
            .quickLook,
            .saveAsFile,
        ]
        if asset.source == .screenshot || asset.contentType == .image {
            actions.append(.copyImage)
            if asset.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                actions.append(contentsOf: [.pasteOCRText, .copyOCRText])
            }
        }
        if asset.contentType == .file {
            actions.append(contentsOf: [.pasteFile, .copyFile, .pasteFilePath, .copyFilePath])
        }
        actions.append(.delete)
        return actions
    }

    private func syncSelectedRootItemID() {
        selectedRootItemID = selectedRootItem?.id
    }

    private static func wrappedIndex(after index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    private static func wrappedIndex(before index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index - 1 + count) % count
    }
}
