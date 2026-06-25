import XCTest
@testable import VoxFlowApp

final class UpdateCheckStateStoreTests: XCTestCase {
    func testPersistsLastAutomaticCheckDate() {
        let defaults = makeDefaults()
        let store = UpdateCheckStateStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        store.lastAutomaticCheckAt = date

        XCTAssertEqual(UpdateCheckStateStore(defaults: defaults).lastAutomaticCheckAt, date)
    }

    func testPersistsIgnoredVersion() {
        let defaults = makeDefaults()
        let store = UpdateCheckStateStore(defaults: defaults)

        store.ignoredVersion = "1.6.2"

        XCTAssertEqual(UpdateCheckStateStore(defaults: defaults).ignoredVersion, "1.6.2")
    }

    func testPersistsDeferredVersionAndUntilDate() {
        let defaults = makeDefaults()
        let store = UpdateCheckStateStore(defaults: defaults)
        let deferredUntil = Date(timeIntervalSince1970: 1_800_086_400)

        store.deferredVersion = "1.6.2"
        store.deferredUntil = deferredUntil

        let restored = UpdateCheckStateStore(defaults: defaults)
        XCTAssertEqual(restored.deferredVersion, "1.6.2")
        XCTAssertEqual(restored.deferredUntil, deferredUntil)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdateCheckStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
