import Combine
import Foundation

enum PaletteMode: Equatable, Sendable {
    case home
    case recentAssets
}

enum PaletteCommand: String, Equatable, Sendable {
    case recentAssets
    case assetHistory
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
            return "全部类型"
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
    case performAssetAction(PaletteDefaultAction, assetID: String)
}

enum PaletteViewModelError: Error, Equatable {
    case noSelectedAsset
    case unsupportedCommand
}

@MainActor
final class PaletteViewModel: ObservableObject {
    private let repository: any AssetRepository
    private let actionService: AssetActionService?

    @Published private(set) var mode: PaletteMode = .home
    @Published private(set) var selectedTypeFilter: PaletteAssetTypeFilter = .all
    @Published private(set) var assets: [AssetItem] = []
    @Published private(set) var selectedHomeResultIndex: Int = 0
    @Published private(set) var selectedAssetIndex: Int = 0
    @Published private(set) var selectedActionIndex: Int = 0
    @Published private(set) var searchText: String = ""
    @Published var isActionPanelPresented = false
    @Published var isTypeFilterPresented = false

    init(
        repository: any AssetRepository,
        actionService: AssetActionService? = nil
    ) {
        self.repository = repository
        self.actionService = actionService
    }

    var showsAskAI: Bool { false }

    var searchPlaceholder: String {
        switch mode {
        case .home:
            return "搜索应用、命令、资产..."
        case .recentAssets:
            return "搜索资产..."
        }
    }

    var homeResults: [PaletteHomeResult] {
        [
            PaletteHomeResult(command: .recentAssets, title: "最近资产", subtitle: "打开最近的语音、截图和剪切板"),
            PaletteHomeResult(command: .assetHistory, title: "历史资产", subtitle: "查看全部历史资产"),
            PaletteHomeResult(command: .screenshotOCR, title: "截图 OCR", subtitle: "框选截图并识别文字"),
            PaletteHomeResult(command: .startAgentCompose, title: "帮我说", subtitle: "口述需求，生成可直接输入的文本"),
            PaletteHomeResult(command: .startAgentDispatch, title: "AI 编程", subtitle: "语音触发 AI 编程控制台"),
            PaletteHomeResult(command: .startDictation, title: "开始听写", subtitle: "按住快捷键说话"),
        ]
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
        selectedActionIndex = 0
        searchText = ""
        isActionPanelPresented = false
        isTypeFilterPresented = false
    }

    func updateSearchText(_ text: String) throws {
        searchText = text
        guard mode == .recentAssets else { return }
        try reloadAssets()
    }

    func selectTypeFilter(_ filter: PaletteAssetTypeFilter) throws {
        selectedTypeFilter = filter
        selectedAssetIndex = 0
        isTypeFilterPresented = false
        isActionPanelPresented = false
        try reloadAssets()
    }

    func selectHomeResult(at index: Int) {
        guard homeResults.indices.contains(index) else { return }
        selectedHomeResultIndex = index
    }

    func selectAsset(at index: Int) {
        guard assets.indices.contains(index) else { return }
        selectedAssetIndex = index
        selectedActionIndex = 0
        isActionPanelPresented = false
    }

    func moveSelectionDown() {
        switch mode {
        case .home:
            selectedHomeResultIndex = Self.wrappedIndex(after: selectedHomeResultIndex, count: homeResults.count)
        case .recentAssets:
            selectedAssetIndex = Self.wrappedIndex(after: selectedAssetIndex, count: assets.count)
            isActionPanelPresented = false
        }
    }

    func moveSelectionUp() {
        switch mode {
        case .home:
            selectedHomeResultIndex = Self.wrappedIndex(before: selectedHomeResultIndex, count: homeResults.count)
        case .recentAssets:
            selectedAssetIndex = Self.wrappedIndex(before: selectedAssetIndex, count: assets.count)
            isActionPanelPresented = false
        }
    }

    func primaryKeyboardAction() -> PaletteKeyboardAction {
        switch mode {
        case .home:
            guard let command = selectedHomeResult?.command else {
                return .none
            }
            return .activateCommand(command)
        case .recentAssets:
            guard let selectedAsset else {
                return .none
            }
            return .performAssetAction(defaultAction(for: selectedAsset), assetID: selectedAsset.id)
        }
    }

    func presentActionPanel() {
        guard selectedAsset != nil else {
            isActionPanelPresented = false
            return
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
        guard let actions = try? actionPanelActionsForSelectedAsset(), !actions.isEmpty else { return }
        selectedActionIndex = Self.wrappedIndex(after: selectedActionIndex, count: actions.count)
    }

    func moveActionSelectionUp() {
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

    var selectedHomeResult: PaletteHomeResult? {
        guard homeResults.indices.contains(selectedHomeResultIndex) else { return nil }
        return homeResults[selectedHomeResultIndex]
    }

    var footerPrimaryActionTitle: String {
        guard let selectedAsset else {
            return "打开"
        }
        switch defaultAction(for: selectedAsset) {
        case .openURL:
            return "打开链接"
        case let .assetAction(action):
            switch action {
            case .pasteFilePath:
                return "粘贴文件路径"
            case .paste:
                return "粘贴"
            default:
                return action.displayTitle
            }
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

    private static func wrappedIndex(after index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    private static func wrappedIndex(before index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index - 1 + count) % count
    }
}
