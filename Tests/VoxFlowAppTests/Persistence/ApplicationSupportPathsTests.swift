import XCTest
@testable import VoxFlowApp

final class ApplicationSupportPathsTests: XCTestCase {
    func testPathsUseVoxFlowApplicationSupportLayout() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let paths = ApplicationSupportPaths(applicationSupportDirectory: applicationSupportURL)

        XCTAssertEqual(paths.rootDirectory.path, "/tmp/Application Support/VoxFlow")
        XCTAssertEqual(paths.databaseURL.path, "/tmp/Application Support/VoxFlow/voxflow.sqlite")
        XCTAssertEqual(paths.exportsDirectory.path, "/tmp/Application Support/VoxFlow/Exports")
        XCTAssertEqual(paths.modelsDirectory.path, "/tmp/Application Support/VoxFlow/Models")
    }

    func testEnsureDirectoriesCreatesRequiredDirectories() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowPaths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let paths = ApplicationSupportPaths(applicationSupportDirectory: temporaryRoot)

        try paths.ensureDirectories()

        XCTAssertTrue(FileManager.default.directoryExists(at: paths.rootDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: paths.exportsDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: paths.modelsDirectory))
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
