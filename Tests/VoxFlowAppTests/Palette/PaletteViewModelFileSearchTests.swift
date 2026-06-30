import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteViewModelFileSearchTests: XCTestCase {
    func testRootSearchMatchesSearchFilesAliases() throws {
        for query in ["f", "search", "search files", "find", "file", "files", "文件", "搜索文件"] {
            let viewModel = makeViewModel()

            try viewModel.updateSearchText(query)

            XCTAssertEqual(viewModel.selectedRootItem?.title, "搜索文件", "query: \(query)")
            XCTAssertEqual(viewModel.primaryKeyboardAction(), .activateCommand(.searchFiles), "query: \(query)")
        }
    }

    func testActivatingSearchFilesEntersFileSearchAndShowsRecentFiles() async throws {
        let recent = [
            makeFileItem(name: "Recent.md"),
            makeFileItem(name: "Notes.txt"),
        ]
        let recentProvider = FakePaletteRecentFileProvider(items: recent)
        let searchService = FakePaletteFileSearchService()
        let viewModel = makeViewModel(searchService: searchService, recentProvider: recentProvider)

        try viewModel.activate(.searchFiles)
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(viewModel.mode, .fileSearch)
        XCTAssertEqual(viewModel.searchPlaceholder, "搜索文件...")
        XCTAssertEqual(viewModel.fileResults, recent)
        XCTAssertEqual(viewModel.fileSearchState, .showingRecent)
        XCTAssertEqual(searchService.requests, [])
    }

    func testSingleCharacterSearchCallsFileSearchServiceWithPrefixBudget() async throws {
        let searchService = FakePaletteFileSearchService(responseItems: [
            makeFileItem(name: "126")
        ])
        let viewModel = makeViewModel(searchService: searchService)
        try viewModel.activate(.searchFiles)
        try await Task.sleep(nanoseconds: 60_000_000)

        try viewModel.updateSearchText("1")
        try await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(searchService.requests.map(\.query), ["1"])
        XCTAssertEqual(searchService.requests.first?.strategy, .prefixThenContains)
        XCTAssertEqual(searchService.requests.first?.limit, 30)
        XCTAssertEqual(viewModel.fileResults.map(\.name), ["126"])
        XCTAssertEqual(viewModel.fileSearchState, .completed)
    }

    func testCachedResultIsShownBeforeSearchCompletes() async throws {
        let cached = makeFileItem(name: "README.md")
        let cache = PaletteFileSearchCache(now: { Date(timeIntervalSince1970: 100) })
        cache.store(
            [cached],
            for: PaletteFileSearchCacheKey(
                normalizedQuery: "README",
                scope: .userHome,
                strategy: .contains
            )
        )
        let searchService = FakePaletteFileSearchService(responseItems: [
            makeFileItem(name: "README-new.md")
        ])
        searchService.delayNanoseconds = 200_000_000
        let viewModel = makeViewModel(searchService: searchService, cache: cache)
        try viewModel.activate(.searchFiles)
        try await Task.sleep(nanoseconds: 60_000_000)

        try viewModel.updateSearchText("README")

        XCTAssertEqual(viewModel.fileResults.map(\.name), ["README.md"])
        XCTAssertEqual(viewModel.fileSearchState, .searching)

        try await Task.sleep(nanoseconds: 460_000_000)
        XCTAssertEqual(viewModel.fileResults.map(\.name), ["README-new.md"])
    }

    func testNewQueryIgnoresOlderSearchResult() async throws {
        let searchService = SequencedPaletteFileSearchService(responses: [
            PaletteFileSearchResponse(
                query: "1",
                items: [makeFileItem(name: "old.txt")],
                completion: .completed
            ),
            PaletteFileSearchResponse(
                query: "12",
                items: [makeFileItem(name: "new.txt")],
                completion: .completed
            ),
        ])
        searchService.delayNanoseconds = 300_000_000
        let viewModel = makeViewModel(searchService: searchService)
        try viewModel.activate(.searchFiles)
        try await Task.sleep(nanoseconds: 60_000_000)

        try viewModel.updateSearchText("1")
        try await Task.sleep(nanoseconds: 80_000_000)
        try viewModel.updateSearchText("12")
        try await Task.sleep(nanoseconds: 650_000_000)

        XCTAssertEqual(viewModel.fileResults.map(\.name), ["new.txt"])
    }

    func testFileSearchKeyboardAndActionPanelUseFileActions() async throws {
        let selected = makeFileItem(name: "README.md")
        let viewModel = makeViewModel(recentProvider: FakePaletteRecentFileProvider(items: [selected]))
        try viewModel.activate(.searchFiles)
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(
            viewModel.primaryKeyboardAction(),
            .performFileAction(.open, fileID: selected.id)
        )
        XCTAssertEqual(
            viewModel.fileActionPanelActionsForSelectedFile(),
            [.open, .showInFinder, .quickLook, .copyPath, .copyName]
        )
        viewModel.presentActionPanel()
        XCTAssertEqual(viewModel.selectedFileActionPanelAction(), .open)
        XCTAssertNil(viewModel.selectedActionPanelAction())
    }

    func testBackFromFileSearchReturnsHomeAndClearsFileState() async throws {
        let viewModel = makeViewModel(recentProvider: FakePaletteRecentFileProvider(items: [
            makeFileItem(name: "README.md")
        ]))
        try viewModel.activate(.searchFiles)
        try await Task.sleep(nanoseconds: 60_000_000)

        viewModel.goBack()

        XCTAssertEqual(viewModel.mode, .home)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.fileResults.isEmpty)
        XCTAssertEqual(viewModel.fileSearchState, .idle)
        XCTAssertNil(viewModel.selectedFile)
    }

    private func makeViewModel(
        searchService: any PaletteFileSearching = FakePaletteFileSearchService(),
        recentProvider: any PaletteRecentFileProviding = FakePaletteRecentFileProvider(items: []),
        cache: PaletteFileSearchCache = PaletteFileSearchCache()
    ) -> PaletteViewModel {
        PaletteViewModel(
            repository: CapturingPaletteAssetRepository(),
            favoritesStore: InMemoryPaletteFavoritesStore(favoriteIDs: []),
            usageStore: InMemoryPaletteUsageStore(),
            fileSearchService: searchService,
            recentFileProvider: recentProvider,
            fileSearchCache: cache,
            fileSearchDebounceNanoseconds: 20_000_000
        )
    }
}

@MainActor
private final class FakePaletteFileSearchService: PaletteFileSearching {
    private(set) var requests: [PaletteFileSearchRequest] = []
    var responseItems: [PaletteFileItem]
    var delayNanoseconds: UInt64 = 0

    init(responseItems: [PaletteFileItem] = []) {
        self.responseItems = responseItems
    }

    func search(_ request: PaletteFileSearchRequest) async -> PaletteFileSearchResponse {
        requests.append(request)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return PaletteFileSearchResponse(
            query: request.query,
            items: responseItems,
            completion: .completed
        )
    }
}

@MainActor
private final class SequencedPaletteFileSearchService: PaletteFileSearching {
    private var responses: [PaletteFileSearchResponse]
    var delayNanoseconds: UInt64 = 0

    init(responses: [PaletteFileSearchResponse]) {
        self.responses = responses
    }

    func search(_ request: PaletteFileSearchRequest) async -> PaletteFileSearchResponse {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return responses.isEmpty
            ? PaletteFileSearchResponse(query: request.query, items: [], completion: .completed)
            : responses.removeFirst()
    }
}

@MainActor
private final class FakePaletteRecentFileProvider: PaletteRecentFileProviding {
    let items: [PaletteFileItem]

    init(items: [PaletteFileItem]) {
        self.items = items
    }

    func recentFiles(limit: Int) async -> [PaletteFileItem] {
        Array(items.prefix(limit))
    }
}

private final class CapturingPaletteAssetRepository: AssetRepository {
    func save(_ item: AssetItem) throws {}
    func asset(id: String) throws -> AssetItem? { nil }
    func page(query: AssetQuery) throws -> AssetPage { AssetPage(items: [], totalCount: 0) }
    func softDelete(id: String, deletedAt: Date) throws {}
}

private final class InMemoryPaletteFavoritesStore: PaletteFavoritesStoring {
    private var ids: [PaletteRootItemID]

    init(favoriteIDs: [PaletteRootItemID]) {
        self.ids = favoriteIDs
    }

    func favoriteIDs() -> [PaletteRootItemID] { ids }
    func isFavorite(_ id: PaletteRootItemID) -> Bool { ids.contains(id) }
    func addFavorite(_ id: PaletteRootItemID) { ids.append(id) }
    func removeFavorite(_ id: PaletteRootItemID) { ids.removeAll { $0 == id } }
}

private final class InMemoryPaletteUsageStore: PaletteUsageStoring {
    func usage(for id: PaletteRootItemID) -> PaletteUsageSnapshot { .empty }
    func recordActivation(of id: PaletteRootItemID, at date: Date) {}
    func querySelection(for query: String, itemID: PaletteRootItemID) -> PaletteQuerySelectionSnapshot { .empty }
    func recordSelection(query: String, itemID: PaletteRootItemID, at date: Date) {}
}

private func makeFileItem(name: String) -> PaletteFileItem {
    PaletteFileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        displayPath: "/tmp",
        isDirectory: false,
        contentTypeIdentifier: "public.data",
        modifiedAt: Date(timeIntervalSince1970: 1)
    )
}
