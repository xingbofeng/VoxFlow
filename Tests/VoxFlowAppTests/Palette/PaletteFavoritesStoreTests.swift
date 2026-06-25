import XCTest
@testable import VoxFlowApp

final class PaletteFavoritesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PaletteFavoritesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstReadSeedsDefaultFavorite() {
        let store = makeStore()

        XCTAssertEqual(store.favoriteIDs(), [.command(.recentAssets)])
    }

    func testAddFavoritePersistsAndDoesNotDuplicate() {
        let store = makeStore()
        let screenshotOCR = PaletteRootItemID.command(.screenshotOCR)

        store.addFavorite(screenshotOCR)
        store.addFavorite(screenshotOCR)

        XCTAssertEqual(store.favoriteIDs(), [.command(.recentAssets), screenshotOCR])
        XCTAssertEqual(makeStore().favoriteIDs(), [.command(.recentAssets), screenshotOCR])
    }

    func testRemoveFavoritePersistsAndMissingRemoveKeepsOrder() {
        let store = makeStore()
        let screenshotOCR = PaletteRootItemID.command(.screenshotOCR)
        let slack = PaletteRootItemID(rawValue: "application:com.tinyspeck.slackmacgap")

        store.addFavorite(screenshotOCR)
        store.addFavorite(slack)
        store.removeFavorite(screenshotOCR)
        store.removeFavorite(PaletteRootItemID.command(.startDictation))

        XCTAssertEqual(store.favoriteIDs(), [.command(.recentAssets), slack])
        XCTAssertEqual(makeStore().favoriteIDs(), [.command(.recentAssets), slack])
    }

    func testRemovingSeededFavoriteMarksStoreCustomizedAndDoesNotSeedAgain() {
        let store = makeStore()

        store.removeFavorite(.command(.recentAssets))

        XCTAssertEqual(store.favoriteIDs(), [])
        XCTAssertEqual(makeStore().favoriteIDs(), [])
    }

    func testCorruptedFavoritesDataFallsBackToSeedBeforeCustomization() {
        defaults.set(Data([0xFF, 0x00]), forKey: UserDefaultsPaletteFavoritesStore.favoritesKey)

        XCTAssertEqual(makeStore().favoriteIDs(), [.command(.recentAssets)])
    }

    func testCorruptedFavoritesDataFallsBackToEmptyAfterCustomization() {
        defaults.set(true, forKey: UserDefaultsPaletteFavoritesStore.customizedKey)
        defaults.set(Data([0xFF, 0x00]), forKey: UserDefaultsPaletteFavoritesStore.favoritesKey)

        XCTAssertEqual(makeStore().favoriteIDs(), [])
    }

    private func makeStore() -> UserDefaultsPaletteFavoritesStore {
        UserDefaultsPaletteFavoritesStore(
            defaults: defaults,
            seed: [.command(.recentAssets)]
        )
    }
}
