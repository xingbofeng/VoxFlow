import XCTest
@testable import Shared

final class AppGroupDiagnosticTests: XCTestCase {
    func testRunProbeReportsDefaultsAndFileRoundTrips() throws {
        let suiteName = "test.app-group-diagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-group-diagnostic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let result = AppGroupDiagnostic.run(
            defaults: defaults,
            containerURL: root,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(result.canWrite)
        XCTAssertTrue(result.canRead)
        XCTAssertTrue(result.canWriteFile)
        XCTAssertTrue(result.canReadFile)
        XCTAssertTrue(result.containerExists)
        XCTAssertTrue(result.isHealthy)
        XCTAssertEqual(result.fileName, "mashangxie-app-group-probe.txt")
        XCTAssertEqual(result.fileValue, "ok-1800000000.0")
    }

    func testRunProbeReportsUnavailableFileContainerWithoutFailingDefaults() throws {
        let suiteName = "test.app-group-diagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let result = AppGroupDiagnostic.run(
            defaults: defaults,
            containerURL: nil as URL?,
            now: Date(timeIntervalSince1970: 1_800_000_001)
        )

        XCTAssertTrue(result.canWrite)
        XCTAssertTrue(result.canRead)
        XCTAssertFalse(result.canWriteFile)
        XCTAssertFalse(result.canReadFile)
        XCTAssertFalse(result.containerExists)
        XCTAssertFalse(result.isHealthy)
    }

}
