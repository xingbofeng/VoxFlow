import XCTest
@testable import VoxFlowApp

final class PaletteUsageStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PaletteUsageStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordActivationIncrementsCountAndUpdatesLastUsedAt() {
        let store = makeStore()
        let id = PaletteRootItemID.command(.screenshotOCR)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = Date(timeIntervalSince1970: 1_800_000_120)

        store.recordActivation(of: id, at: first)
        store.recordActivation(of: id, at: second)

        XCTAssertEqual(store.usage(for: id), PaletteUsageSnapshot(useCount: 2, lastUsedAt: second))
        XCTAssertEqual(makeStore().usage(for: id), PaletteUsageSnapshot(useCount: 2, lastUsedAt: second))
    }

    func testUsageIsEmptyWhenActivationIsNotRecorded() {
        let store = makeStore()

        XCTAssertEqual(store.usage(for: .command(.screenshotOCR)), .empty)
    }

    func testRecordQuerySelectionNormalizesQueryAndAccumulatesCount() {
        let store = makeStore()
        let id = PaletteRootItemID.command(.startDictation)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = Date(timeIntervalSince1970: 1_800_000_120)

        store.recordSelection(query: "  DICT  ", itemID: id, at: first)
        store.recordSelection(query: "dict", itemID: id, at: second)

        XCTAssertEqual(
            store.querySelection(for: " dict ", itemID: id),
            PaletteQuerySelectionSnapshot(selectionCount: 2, lastSelectedAt: second)
        )
        XCTAssertEqual(
            makeStore().querySelection(for: "DICT", itemID: id),
            PaletteQuerySelectionSnapshot(selectionCount: 2, lastSelectedAt: second)
        )
    }

    func testBlankQuerySelectionIsIgnored() {
        let store = makeStore()
        let id = PaletteRootItemID.command(.startDictation)

        store.recordSelection(query: "   ", itemID: id, at: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(store.querySelection(for: " ", itemID: id), .empty)
    }

    func testCorruptedUsageDataFallsBackToEmptySnapshots() {
        defaults.set(Data([0xFF, 0x00]), forKey: UserDefaultsPaletteUsageStore.usageKey)
        defaults.set(Data([0xFF, 0x00]), forKey: UserDefaultsPaletteUsageStore.querySelectionKey)

        XCTAssertEqual(makeStore().usage(for: .command(.recentAssets)), .empty)
        XCTAssertEqual(makeStore().querySelection(for: "asset", itemID: .command(.recentAssets)), .empty)
    }

    private func makeStore() -> UserDefaultsPaletteUsageStore {
        UserDefaultsPaletteUsageStore(defaults: defaults)
    }
}
