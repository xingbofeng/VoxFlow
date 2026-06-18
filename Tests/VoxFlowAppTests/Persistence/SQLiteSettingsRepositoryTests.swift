import XCTest
@testable import VoxFlowApp

final class SQLiteSettingsRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteSettingsRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteSettingsRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        queue = nil
        super.tearDown()
    }

    func testSaveAndReadSetting() throws {
        try repository.set("shortcut.longPressMs", jsonValue: #"{"value":500}"#)

        XCTAssertEqual(
            try repository.value(forKey: "shortcut.longPressMs"),
            #"{"value":500}"#
        )
    }

    func testSavingExistingSettingUpdatesValue() throws {
        try repository.set("dictation.mode", jsonValue: #"{"value":"hold"}"#)
        try repository.set("dictation.mode", jsonValue: #"{"value":"toggle"}"#)

        XCTAssertEqual(
            try repository.value(forKey: "dictation.mode"),
            #"{"value":"toggle"}"#
        )
    }

    func testDeleteSettingRemovesValue() throws {
        try repository.set("audio.feedback", jsonValue: #"{"enabled":true}"#)

        try repository.deleteValue(forKey: "audio.feedback")

        XCTAssertNil(try repository.value(forKey: "audio.feedback"))
    }

    func testListSettingsReturnsSortedRecords() throws {
        try repository.set("z.setting", jsonValue: #"{"value":2}"#)
        try repository.set("a.setting", jsonValue: #"{"value":1}"#)

        let records = try repository.list()

        XCTAssertEqual(records.map(\.key), ["a.setting", "z.setting"])
        XCTAssertEqual(records.map(\.valueJSON), [#"{"value":1}"#, #"{"value":2}"#])
    }
}
