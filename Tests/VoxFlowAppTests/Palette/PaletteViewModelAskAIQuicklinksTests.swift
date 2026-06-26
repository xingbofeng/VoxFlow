import Combine
import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteViewModelAskAIQuicklinksTests: XCTestCase {
    private func makeViewModel(
        favorites: [PaletteRootItemID] = [],
        usageStore: PaletteUsageStoring = InMemoryPaletteUsageStore(),
        applicationProvider: (any InstalledApplicationProviding)? = nil
    ) -> PaletteViewModel {
        PaletteViewModel(
            repository: StubPaletteAssetRepository(),
            applicationProvider: applicationProvider,
            favoritesStore: InMemoryPaletteFavoritesStore(favoriteIDs: favorites),
            usageStore: usageStore,
            showsAskAI: true
        )
    }

    // MARK: - Empty query suggestions

    func testEmptyQueryShowsAskAIAndQuicklinksSuggestions() {
        let viewModel = makeViewModel()

        let titles = viewModel.visibleRootItems.map(\.title)
        XCTAssertTrue(titles.contains("问 AI"), "空搜索应包含问 AI 建议")
        XCTAssertTrue(titles.contains("Google"), "空搜索应包含 Google Quicklink")
        XCTAssertTrue(titles.contains("淘宝"), "空搜索应包含淘宝 Quicklink")
    }

    func testEmptyQueryAskAISubtitleIsDefaultPrompt() {
        let viewModel = makeViewModel()

        let askAI = viewModel.visibleRootItems.first { $0.title == "问 AI" }
        XCTAssertEqual(askAI?.subtitle, "直接向已配置模型提问")
    }

    // MARK: - URL detection ranks first

    func testURLInputRanksOpenURLFirstAndAutoSelected() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("github.com/openai/codex")

        let first = viewModel.visibleRootItems.first
        XCTAssertEqual(first?.title, "打开网址")
        XCTAssertEqual(first?.subtitle, "https://github.com/openai/codex")
        XCTAssertEqual(viewModel.selectedRootItem?.title, "打开网址")
    }

    func testPrimaryActionForOpenURL() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("github.com/openai/codex")

        XCTAssertEqual(
            viewModel.primaryKeyboardAction(),
            .openURL("https://github.com/openai/codex")
        )
    }

    func testURLHasHighestPriorityOverAskAIAndQuicklinks() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("github.com/openai/codex")

        let titles = viewModel.visibleRootItems.map(\.title)
        XCTAssertEqual(titles.first, "打开网址")
        XCTAssertTrue(titles.contains("问 AI"))
    }

    func testSchemeURLPreserved() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("http://localhost:3000/docs")

        XCTAssertEqual(viewModel.visibleRootItems.first?.title, "打开网址")
        XCTAssertEqual(viewModel.visibleRootItems.first?.subtitle, "http://localhost:3000/docs")
    }

    // MARK: - Ask AI high priority for plain query

    func testAskAIRankedBeforeCommandsForPlainQuery() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("解释 SwiftUI StateObject")

        let titles = viewModel.visibleRootItems.map(\.title)
        // 无 URL 时，问 AI 是第一项（高优先级动作）
        XCTAssertEqual(titles.first, "问 AI")
        // 问 AI 之后才是 Quicklinks 与命令/应用匹配结果
        let askAIIndex = titles.firstIndex(of: "问 AI")
        XCTAssertNotNil(askAIIndex)
        if let commandIndex = titles.firstIndex(where: { $0 == "最近资产" || $0 == "截图 OCR" }) {
            XCTAssertLessThan(askAIIndex!, commandIndex)
        }
    }

    func testAskAISubtitleIncludesPrompt() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("解释 SwiftUI StateObject")

        let askAI = viewModel.visibleRootItems.first { $0.title == "问 AI" }
        XCTAssertEqual(askAI?.subtitle, "询问 解释 SwiftUI StateObject")
    }

    func testPrimaryActionForAskAI() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("解释 SwiftUI StateObject")

        // 第一项是问 AI（无 URL），自动选中
        XCTAssertEqual(viewModel.selectedRootItem?.title, "问 AI")
        XCTAssertEqual(
            viewModel.primaryKeyboardAction(),
            .askAI(prompt: "解释 SwiftUI StateObject")
        )
    }

    func testStrongInstalledApplicationMatchRanksBeforeGenericQuicklinks() throws {
        let jdID = PaletteRootItemID.quicklink(PaletteQuicklinkCatalog.quicklink(id: "jd")!)
        let viewModel = makeViewModel(
            favorites: [jdID],
            applicationProvider: FakePaletteInstalledApplicationProvider(applications: [
                InstalledApplication(
                    id: "com.microsoft.VSCode",
                    name: "Code",
                    bundleID: "com.microsoft.VSCode",
                    iconPath: nil,
                    path: "/Applications/Visual Studio Code.app",
                    systemCategory: .userApplication
                )
            ])
        )

        try viewModel.updateSearchText("vscode")

        XCTAssertEqual(viewModel.visibleRootItems.first?.title, "Code")
        XCTAssertEqual(viewModel.selectedRootItem?.title, "Code")
        XCTAssertEqual(
            viewModel.primaryKeyboardAction(),
            .openApplication(
                path: "/Applications/Visual Studio Code.app",
                itemID: PaletteRootItemID(rawValue: "application:com.microsoft.VSCode")
            )
        )
        XCTAssertLessThan(
            viewModel.visibleRootItems.firstIndex { $0.title == "Code" }!,
            viewModel.visibleRootItems.firstIndex { $0.title == "京东搜索" }!
        )
    }

    // MARK: - Quicklink alias matching

    func testQuicklinkAliasHitRanksFirstAndRefinesQuery() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("taobao macbook stand")

        let firstQuicklink = viewModel.visibleRootItems.first { $0.kind == .quicklink }
        XCTAssertEqual(firstQuicklink?.title, "淘宝搜索")
        XCTAssertEqual(firstQuicklink?.subtitle, "搜索 macbook stand")
    }

    func testPrimaryActionForQuicklinkWithAliasRefinedQuery() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("taobao macbook stand")

        let taobaoIndex = viewModel.visibleRootItems.firstIndex { $0.title == "淘宝搜索" }
        XCTAssertNotNil(taobaoIndex)
        viewModel.selectHomeResult(at: taobaoIndex!)

        let taobao = PaletteQuicklinkCatalog.quicklink(id: "taobao")!
        XCTAssertEqual(
            viewModel.primaryKeyboardAction(),
            .activateQuicklink(taobao, query: "macbook stand")
        )
    }

    func testQuicklinkAliasEnglishAndChineseMatch() throws {
        let viewModel = makeViewModel()

        try viewModel.updateSearchText("github swift markdown")
        XCTAssertEqual(
            viewModel.visibleRootItems.first { $0.kind == .quicklink }?.title,
            "GitHub搜索"
        )

        try viewModel.updateSearchText("淘宝 macbook stand")
        XCTAssertEqual(
            viewModel.visibleRootItems.first { $0.kind == .quicklink }?.title,
            "淘宝搜索"
        )
    }

    func testOnlyMatchedQuicklinkRemovesAliasFromSearchQuery() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("github")

        let githubItem = viewModel.visibleRootItems.first { $0.title == "GitHub" }
        let googleItem = viewModel.visibleRootItems.first { $0.title == "Google搜索" }

        if case let .quicklink(_, query) = githubItem?.activation {
            XCTAssertEqual(query, "")
        } else {
            XCTFail("期望 GitHub quicklink")
        }
        if case let .quicklink(_, query) = googleItem?.activation {
            XCTAssertEqual(query, "github")
        } else {
            XCTFail("期望 Google quicklink")
        }
    }

    func testTranslateActionUsesInputTextAndRemovesLeadingAlias() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("翻译 hello world")

        let translateItem = viewModel.visibleRootItems.first { $0.title == "翻译" }

        XCTAssertEqual(translateItem?.subtitle, "翻译 hello world")
        if case let .translate(text) = translateItem?.activation {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("期望 translate activation")
        }
    }

    func testQuicklinkSearchURLEncodingFromActivationQuery() throws {
        let viewModel = makeViewModel()
        try viewModel.updateSearchText("taobao macbook stand")

        let taobaoItem = viewModel.visibleRootItems.first { $0.title == "淘宝搜索" }
        // 验证 activation 携带的 query 经 searchURL 生成正确编码 URL
        if case let .quicklink(link, query) = taobaoItem?.activation {
            XCTAssertEqual(link.id, "taobao")
            XCTAssertEqual(query, "macbook stand")
            XCTAssertEqual(link.searchURL(for: query), "https://s.taobao.com/search?q=macbook%20stand")
        } else {
            XCTFail("期望 quicklink activation")
        }
    }

    // MARK: - First result always selected

    func testFirstResultAlwaysSelectedOnQueryChange() throws {
        let viewModel = makeViewModel()

        try viewModel.updateSearchText("github.com/openai/codex")
        XCTAssertEqual(viewModel.selectedRootItem?.title, "打开网址")

        try viewModel.updateSearchText("解释 SwiftUI")
        XCTAssertEqual(viewModel.selectedRootItem?.title, "问 AI")

        try viewModel.updateSearchText("taobao macbook stand")
        // 无 URL，第一项是问 AI
        XCTAssertEqual(viewModel.selectedRootItem?.title, "问 AI")
    }

    // MARK: - Quicklinks participate in favorites/usage

    func testQuicklinkCanFavoriteAndUsageRanking() throws {
        let googleID = PaletteRootItemID.quicklink(PaletteQuicklinkCatalog.quicklink(id: "google")!)
        let viewModel = makeViewModel(favorites: [googleID])

        try viewModel.updateSearchText("swift concurrency")
        let titles = viewModel.visibleRootItems.map(\.title)
        // favorite google 应在非 favorite quicklink 之前（alias 均未命中）
        let googleIndex = titles.firstIndex(of: "Google搜索")
        let bingIndex = titles.firstIndex(of: "Bing搜索")
        XCTAssertNotNil(googleIndex)
        XCTAssertNotNil(bingIndex)
        XCTAssertLessThan(googleIndex!, bingIndex!)
    }

    func testOpenURLFavoriteReturnsToFavoritesOnEmptyQuery() throws {
        let favoritesStore = InMemoryPaletteFavoritesStore(favoriteIDs: [])
        let viewModel = PaletteViewModel(
            repository: StubPaletteAssetRepository(),
            applicationProvider: nil,
            favoritesStore: favoritesStore,
            usageStore: InMemoryPaletteUsageStore(),
            showsAskAI: true
        )
        try viewModel.updateSearchText("miora.design")

        XCTAssertEqual(viewModel.selectedRootItem?.title, "打开网址")
        _ = viewModel.performRootAction(.addFavorite)

        try viewModel.updateSearchText("")
        XCTAssertEqual(viewModel.rootSections.first?.kind, .favorites)
        XCTAssertTrue(
            viewModel.rootSections.first?.items.contains {
                $0.title == "打开网址" && $0.subtitle == "https://miora.design"
            } ?? false
        )
    }

    // MARK: - No "匹配 xxx" text shown

    func testNoMatchingPrefixShownInResults() throws {
        let viewModel = makeViewModel()

        try viewModel.updateSearchText("github.com/openai/codex")
        for item in viewModel.visibleRootItems {
            XCTAssertFalse(item.title.hasPrefix("匹配"), "不应显示 匹配 xxx 标题：\(item.title)")
            XCTAssertFalse(item.subtitle.hasPrefix("匹配"), "不应显示 匹配 xxx 副标题：\(item.subtitle)")
        }

        try viewModel.updateSearchText("taobao macbook stand")
        for item in viewModel.visibleRootItems {
            XCTAssertFalse(item.title.hasPrefix("匹配"), "不应显示 匹配 xxx 标题：\(item.title)")
            XCTAssertFalse(item.subtitle.hasPrefix("匹配"), "不应显示 匹配 xxx 副标题：\(item.subtitle)")
        }
    }
}

// MARK: - Test helpers

private final class StubPaletteAssetRepository: AssetRepository {
    func save(_ item: AssetItem) throws {}
    func asset(id: String) throws -> AssetItem? { nil }
    func page(query: AssetQuery) throws -> AssetPage {
        AssetPage(items: [], totalCount: 0)
    }
    func softDelete(id: String, deletedAt: Date) throws {}
}

private struct FakePaletteInstalledApplicationProvider: InstalledApplicationProviding {
    let applications: [InstalledApplication]

    func scanInstalledApplications() -> [InstalledApplication] {
        applications
    }
}

private final class InMemoryPaletteFavoritesStore: PaletteFavoritesStoring {
    private var ids: [PaletteRootItemID]
    init(favoriteIDs: [PaletteRootItemID]) { self.ids = favoriteIDs }
    func favoriteIDs() -> [PaletteRootItemID] { ids }
    func isFavorite(_ id: PaletteRootItemID) -> Bool { ids.contains(id) }
    func addFavorite(_ id: PaletteRootItemID) {
        guard !ids.contains(id) else { return }
        ids.append(id)
    }
    func removeFavorite(_ id: PaletteRootItemID) { ids.removeAll { $0 == id } }
}

private final class InMemoryPaletteUsageStore: PaletteUsageStoring {
    private var usage: [PaletteRootItemID: PaletteUsageSnapshot] = [:]
    private var querySelections: [String: [PaletteRootItemID: PaletteQuerySelectionSnapshot]] = [:]
    func usage(for id: PaletteRootItemID) -> PaletteUsageSnapshot { usage[id] ?? .empty }
    func recordActivation(of id: PaletteRootItemID, at date: Date) {
        var snapshot = usage[id] ?? .empty
        snapshot.useCount += 1
        snapshot.lastUsedAt = date
        usage[id] = snapshot
    }
    func querySelection(for query: String, itemID: PaletteRootItemID) -> PaletteQuerySelectionSnapshot {
        let key = PaletteUsageStoreQueryKey(query)
        return querySelections[key]?[itemID] ?? .empty
    }
    func recordSelection(query: String, itemID: PaletteRootItemID, at date: Date) {
        let key = PaletteUsageStoreQueryKey(query)
        var itemRecords = querySelections[key] ?? [:]
        var snapshot = itemRecords[itemID] ?? .empty
        snapshot.selectionCount += 1
        snapshot.lastSelectedAt = date
        itemRecords[itemID] = snapshot
        querySelections[key] = itemRecords
    }
}

private func PaletteUsageStoreQueryKey(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
