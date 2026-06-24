import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteViewModelTests: XCTestCase {
    func testHomeStartsAsSingleListLauncherWithoutAskAI() throws {
        let viewModel = PaletteViewModel(repository: CapturingPaletteAssetRepository())

        XCTAssertEqual(viewModel.mode, .home)
        XCTAssertEqual(viewModel.searchPlaceholder, "搜索应用、命令、资产...")
        XCTAssertFalse(viewModel.showsAskAI)
        XCTAssertEqual(viewModel.homeResults.map(\.title), ["最近资产", "历史资产", "截图 OCR", "帮我说", "AI 编程", "开始听写"])
        XCTAssertEqual(viewModel.selectedHomeResultIndex, 0)
        XCTAssertEqual(viewModel.selectedHomeResult?.command, .recentAssets)
    }

    func testHomeKeyboardSelectionDefaultsToRecentAssetsAndWrapsWithArrowKeys() {
        let viewModel = PaletteViewModel(repository: CapturingPaletteAssetRepository())

        viewModel.moveSelectionDown()
        XCTAssertEqual(viewModel.selectedHomeResult?.command, .assetHistory)

        viewModel.moveSelectionUp()
        XCTAssertEqual(viewModel.selectedHomeResult?.command, .recentAssets)

        viewModel.moveSelectionUp()
        XCTAssertEqual(viewModel.selectedHomeResult?.command, .startDictation)

        viewModel.moveSelectionDown()
        XCTAssertEqual(viewModel.selectedHomeResult?.command, .recentAssets)
    }

    func testPrimaryKeyboardActionOnHomeUsesSelectedCommand() {
        let viewModel = PaletteViewModel(repository: CapturingPaletteAssetRepository())
        viewModel.moveSelectionDown()

        XCTAssertEqual(viewModel.primaryKeyboardAction(), .activateCommand(.assetHistory))
    }

    func testPaletteVoiceCommandsRouteToDedicatedVoiceActions() {
        let viewModel = PaletteViewModel(repository: CapturingPaletteAssetRepository())

        viewModel.selectHomeResult(at: 3)
        XCTAssertEqual(viewModel.primaryKeyboardAction(), .activateCommand(.startAgentCompose))

        viewModel.selectHomeResult(at: 4)
        XCTAssertEqual(viewModel.primaryKeyboardAction(), .activateCommand(.startAgentDispatch))

        viewModel.selectHomeResult(at: 5)
        XCTAssertEqual(viewModel.primaryKeyboardAction(), .activateCommand(.startDictation))
    }

    func testEnterOnRecentAssetsOpensSecondLevelAssetsPage() throws {
        let viewModel = PaletteViewModel(repository: CapturingPaletteAssetRepository())

        try viewModel.activate(.recentAssets)

        XCTAssertEqual(viewModel.mode, .recentAssets)
        XCTAssertEqual(viewModel.searchPlaceholder, "搜索资产...")
        XCTAssertEqual(viewModel.typeFilters.map(\.title), ["全部类型", "文本", "图片", "文件", "链接", "颜色"])
    }

    func testBackFromRecentAssetsReturnsToLauncherAndClearsAssetState() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "text", contentType: .text, text: "hello")
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        viewModel.goBack()

        XCTAssertEqual(viewModel.mode, .home)
        XCTAssertEqual(viewModel.searchPlaceholder, "搜索应用、命令、资产...")
        XCTAssertTrue(viewModel.assets.isEmpty)
        XCTAssertEqual(viewModel.selectedTypeFilter, .all)
    }

    func testRecentAssetsPageLoadsAndFiltersAssetsByType() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "text", contentType: .text, text: "hello"),
            makeAsset(id: "image", contentType: .image, imagePath: "/tmp/a.png"),
            makeAsset(id: "file", contentType: .file, filePath: "/tmp/a.pdf"),
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        XCTAssertEqual(viewModel.assets.map(\.id), ["text", "image", "file"])

        try viewModel.selectTypeFilter(.image)

        XCTAssertEqual(viewModel.assets.map(\.id), ["image"])
        XCTAssertEqual(repository.lastQuery?.contentTypes, [.image])
    }

    func testAssetKeyboardSelectionWrapsWithArrowKeys() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "text", contentType: .text, text: "hello"),
            makeAsset(id: "image", contentType: .image, imagePath: "/tmp/a.png"),
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        viewModel.moveSelectionDown()
        XCTAssertEqual(viewModel.selectedAsset?.id, "image")

        viewModel.moveSelectionDown()
        XCTAssertEqual(viewModel.selectedAsset?.id, "text")

        viewModel.moveSelectionUp()
        XCTAssertEqual(viewModel.selectedAsset?.id, "image")
    }

    func testActionPanelSelectionWrapsWithArrowKeys() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "text", contentType: .text, text: "hello"),
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)
        viewModel.presentActionPanel()

        viewModel.moveActionSelectionUp()
        XCTAssertEqual(viewModel.selectedActionPanelAction(), .delete)

        viewModel.moveActionSelectionDown()
        XCTAssertEqual(viewModel.selectedActionPanelAction(), .paste)
    }

    func testRecentAssetsSearchReloadsAssetsWithSearchText() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "voice", source: .dictation, contentType: .text, text: "老师"),
            makeAsset(id: "image", source: .screenshot, contentType: .image, text: "错误提示", imagePath: "/tmp/a.png"),
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        try viewModel.updateSearchText("错误")

        XCTAssertEqual(repository.lastQuery?.searchText, "错误")
        XCTAssertEqual(viewModel.assets.map(\.id), ["image"])
    }

    func testCommandKActionsUseAssetActionServiceListAndExcludePhaseTwoActions() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(source: .screenshot, contentType: .image, text: "ocr", imagePath: "/tmp/a.png")
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        let actions = try viewModel.actionPanelActionsForSelectedAsset()

        XCTAssertTrue(actions.contains(.copyImage))
        XCTAssertTrue(actions.contains(.pasteOCRText))
        XCTAssertFalse(actions.contains(.pin))
        XCTAssertFalse(actions.contains(.rerunOCR))
        XCTAssertFalse(actions.contains(.attachToAIChat))
    }

    func testDefaultEnterActionMatchesAssetContentType() {
        let viewModel = PaletteViewModel(repository: CapturingPaletteAssetRepository())

        XCTAssertEqual(
            viewModel.defaultAction(for: makeAsset(source: .dictation, contentType: .text, text: "hello")),
            .assetAction(.paste)
        )
        XCTAssertEqual(
            viewModel.defaultAction(for: makeAsset(source: .screenshot, contentType: .image, imagePath: "/tmp/a.png")),
            .assetAction(.paste)
        )
        XCTAssertEqual(
            viewModel.defaultAction(for: makeAsset(contentType: .file, filePath: "/tmp/a.pdf")),
            .assetAction(.pasteFilePath)
        )
        XCTAssertEqual(
            viewModel.defaultAction(for: makeAsset(contentType: .link, text: "https://example.com", url: "https://example.com")),
            .openURL("https://example.com")
        )
        XCTAssertEqual(
            viewModel.defaultAction(for: makeAsset(contentType: .color, text: "#08745f", colorValue: "#08745f")),
            .assetAction(.paste)
        )
    }

    func testFooterPrimaryActionTitleFollowsSelectedAsset() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "text", contentType: .text, text: "hello"),
            makeAsset(id: "file", contentType: .file, filePath: "/tmp/a.pdf"),
            makeAsset(id: "link", contentType: .link, text: "https://example.com", url: "https://example.com"),
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        XCTAssertEqual(viewModel.footerPrimaryActionTitle, "粘贴")

        viewModel.selectAsset(at: 1)
        XCTAssertEqual(viewModel.footerPrimaryActionTitle, "粘贴文件路径")

        viewModel.selectAsset(at: 2)
        XCTAssertEqual(viewModel.footerPrimaryActionTitle, "打开链接")
    }

    func testPrimaryKeyboardActionOnAssetsUsesSelectedAssetDefaultAction() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "file", contentType: .file, filePath: "/tmp/a.pdf")
        ])
        let viewModel = PaletteViewModel(repository: repository)
        try viewModel.activate(.recentAssets)

        XCTAssertEqual(
            viewModel.primaryKeyboardAction(),
            .performAssetAction(.assetAction(.pasteFilePath), assetID: "file")
        )
    }

    func testCommandKTogglesActionPanelOnlyWhenAnAssetIsSelected() throws {
        let repository = CapturingPaletteAssetRepository(items: [
            makeAsset(id: "text", contentType: .text, text: "hello")
        ])
        let viewModel = PaletteViewModel(repository: repository)

        viewModel.toggleActionPanel()
        XCTAssertFalse(viewModel.isActionPanelPresented)

        try viewModel.activate(.recentAssets)
        viewModel.toggleActionPanel()
        XCTAssertTrue(viewModel.isActionPanelPresented)

        viewModel.toggleActionPanel()
        XCTAssertFalse(viewModel.isActionPanelPresented)
    }
}

private final class CapturingPaletteAssetRepository: AssetRepository {
    var items: [AssetItem]
    private(set) var lastQuery: AssetQuery?

    init(items: [AssetItem] = []) {
        self.items = items
    }

    func save(_ item: AssetItem) throws {}

    func asset(id: String) throws -> AssetItem? {
        items.first { $0.id == id }
    }

    func page(query: AssetQuery) throws -> AssetPage {
        lastQuery = query
        let filtered = query.contentTypes.isEmpty
            ? items
            : items.filter { query.contentTypes.contains($0.contentType) }
        let searched = query.searchText.isEmpty
            ? filtered
            : filtered.filter { item in
                [item.title, item.previewText, item.text, item.url, item.filePath, item.colorValue]
                    .compactMap(\.self)
                    .contains { $0.localizedCaseInsensitiveContains(query.searchText) }
            }
        return AssetPage(items: searched, totalCount: searched.count)
    }

    func softDelete(id: String, deletedAt: Date) throws {}
}

private func makeAsset(
    id: String = UUID().uuidString,
    source: AssetSource = .clipboard,
    contentType: AssetContentType,
    text: String? = nil,
    imagePath: String? = nil,
    filePath: String? = nil,
    url: String? = nil,
    colorValue: String? = nil
) -> AssetItem {
    AssetItem(
        id: id,
        source: source,
        contentType: contentType,
        title: id,
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
        captureReason: .userCopied,
        metadataJSON: nil,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
        deletedAt: nil
    )
}
