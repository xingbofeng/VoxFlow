import XCTest

final class UpdatePromptPresenterTests: XCTestCase {
    func testUpdatePromptUsesCustomModalInsteadOfNSAlert() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Updates/UpdatePromptPresenter.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("NSAlert"))
        XCTAssertTrue(source.contains("UpdatePromptWindowController"))
        XCTAssertTrue(source.contains("NSHostingController"))
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "UpdatePromptPresenterTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
