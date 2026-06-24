import XCTest
@testable import VoxFlowApp

final class AppDatabaseSchemaDriftTests: XCTestCase {
    func testBundledSchemaMatchesRepositoryExpectations() throws {
        let connection = try SQLiteConnection.inMemory()
        try connection.execute(AppDatabase.loadBundledSchemaSQL())

        try AppDatabaseSchemaValidator.validate(connection: connection)
    }

    func testValidatorReportsMissingExpectedIndex() throws {
        let connection = try SQLiteConnection.inMemory()
        try connection.execute(AppDatabase.loadBundledSchemaSQL())
        try connection.execute("DROP INDEX IF EXISTS idx_asset_items_content_hash")

        XCTAssertThrowsError(try AppDatabaseSchemaValidator.validate(connection: connection)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("idx_asset_items_content_hash"),
                "Unexpected error: \(error)"
            )
        }
    }
}
