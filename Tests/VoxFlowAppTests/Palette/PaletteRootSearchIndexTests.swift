import XCTest
@testable import VoxFlowApp

final class PaletteRootSearchIndexTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PaletteRootSearchIndexTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEmptyQueryReturnsFavoritesAndSuggestionsWithoutDuplicates() {
        let items = commandItems()
        let index = PaletteRootSearchIndex()
        let favorites = [PaletteRootItemID.command(.recentAssets)]

        let sections = index.sections(
            for: items,
            query: "",
            favoriteIDs: favorites,
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(sections.map(\.kind), [.favorites, .suggestions])
        XCTAssertEqual(sections[0].items.map(\.title), ["最近资产"])
        XCTAssertFalse(sections[1].items.map(\.title).contains("最近资产"))
        XCTAssertTrue(sections[1].items.map(\.title).contains("截图 OCR"))
    }

    func testDuplicateRootItemIDsAreDeduplicatedBeforeSectioning() {
        let duplicateSlack = appItem(id: "com.tinyspeck.slackmacgap", name: "Slack Duplicate")
        let items = commandItems() + [slackItem(), duplicateSlack]
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: items,
            query: "",
            favoriteIDs: [slackItem().id],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(sections.first?.items.map(\.title), ["Slack"])
        XCTAssertEqual(sections.flatMap(\.items).filter { $0.id == slackItem().id }.count, 1)
    }

    func testEmptyQueryWithoutFavoritesReturnsFavoriteHintAndSuggestions() {
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: commandItems(),
            query: "",
            favoriteIDs: [],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(sections.map(\.kind), [.favoriteHint, .suggestions])
        XCTAssertEqual(sections[0].items, [])
        XCTAssertEqual(sections[1].items.first?.title, "最近资产")
    }

    func testSearchMatchesApplicationsWithAcronymLikeQueries() {
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: commandItems() + [slackItem()],
            query: "slk",
            favoriteIDs: [],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(sections.map(\.kind), [.searchResults])
        XCTAssertEqual(sections.first?.items.first?.title, "Slack")
    }

    func testSearchMatchesCommandTitleAndAliases() {
        let index = PaletteRootSearchIndex()

        let ocrSections = index.sections(
            for: commandItems(),
            query: "ocr",
            favoriteIDs: [],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let dictSections = index.sections(
            for: commandItems(),
            query: "dict",
            favoriteIDs: [],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(ocrSections.first?.items.first?.title, "截图 OCR")
        XCTAssertEqual(dictSections.first?.items.first?.title, "开始听写")
    }

    func testSuggestionsUseFrecencyForEmptyQuery() {
        let usageStore = makeUsageStore()
        usageStore.recordActivation(of: .command(.screenshotOCR), at: Date(timeIntervalSince1970: 1_800_000_000))
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: commandItems(),
            query: "",
            favoriteIDs: [],
            usageStore: usageStore,
            now: Date(timeIntervalSince1970: 1_800_000_060)
        )

        XCTAssertEqual(sections.first { $0.kind == .suggestions }?.items.first?.title, "截图 OCR")
    }

    func testFavoriteBoostWinsWhenFuzzyScoresAreComparable() {
        let index = PaletteRootSearchIndex()
        let alpha = appItem(id: "com.example.alpha", name: "Alpha")
        let alpine = appItem(id: "com.example.alpine", name: "Alpine")

        let sections = index.sections(
            for: [alpha, alpine],
            query: "alp",
            favoriteIDs: [alpine.id],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(sections.first?.items.first?.title, "Alpine")
    }

    func testRecentUseCanBeatVeryOldHighFrequencyUse() {
        let usageStore = makeUsageStore()
        let oldHighFrequencyID = PaletteRootItemID.command(.recentAssets)
        let recentID = PaletteRootItemID.command(.screenshotOCR)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recentDate = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<20 {
            usageStore.recordActivation(of: oldHighFrequencyID, at: oldDate)
        }
        usageStore.recordActivation(of: recentID, at: recentDate)
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: commandItems(),
            query: "",
            favoriteIDs: [],
            usageStore: usageStore,
            now: Date(timeIntervalSince1970: 1_800_000_060)
        )

        XCTAssertEqual(sections.first { $0.kind == .suggestions }?.items.first?.title, "截图 OCR")
    }

    func testStrongFuzzyMatchBeatsFavoriteBoost() {
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: commandItems() + [slackItem()],
            query: "slk",
            favoriteIDs: [.command(.recentAssets)],
            usageStore: makeUsageStore(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(sections.first?.items.first?.title, "Slack")
    }

    func testQuerySelectionBoostsRepeatedChoiceForSameQuery() {
        let usageStore = makeUsageStore()
        usageStore.recordSelection(
            query: "code",
            itemID: .command(.startAgentDispatch),
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let index = PaletteRootSearchIndex()

        let sections = index.sections(
            for: commandItems(),
            query: "code",
            favoriteIDs: [],
            usageStore: usageStore,
            now: Date(timeIntervalSince1970: 1_800_000_060)
        )

        XCTAssertEqual(sections.first?.items.first?.title, "AI 编程")
    }

    private func commandItems() -> [PaletteRootItem] {
        PaletteCommand.rootCommands.map(PaletteRootItem.command)
    }

    private func slackItem() -> PaletteRootItem {
        appItem(id: "com.tinyspeck.slackmacgap", name: "Slack", path: "/Applications/Slack.app")
    }

    private func appItem(
        id: String,
        name: String,
        path: String? = nil
    ) -> PaletteRootItem {
        PaletteRootItem.application(
            InstalledApplication(
                id: id,
                name: name,
                bundleID: id,
                iconPath: nil,
                path: path ?? "/Applications/\(name).app",
                systemCategory: .userApplication
            )
        )
    }

    private func makeUsageStore() -> UserDefaultsPaletteUsageStore {
        UserDefaultsPaletteUsageStore(defaults: defaults)
    }
}
