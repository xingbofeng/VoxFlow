import XCTest
@testable import VoxFlowApp

final class VoxFlowAppResourceBundleTests: XCTestCase {
    func testResourceBundleLocatorLoadsBundledDatabaseSchema() throws {
        let schemaURL = try XCTUnwrap(
            VoxFlowAppResourceBundle.url(forResource: "AppDatabaseSchema", withExtension: "sql")
        )
        let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)

        XCTAssertTrue(schemaSQL.contains("CREATE TABLE IF NOT EXISTS dictation_history"))
    }
}
