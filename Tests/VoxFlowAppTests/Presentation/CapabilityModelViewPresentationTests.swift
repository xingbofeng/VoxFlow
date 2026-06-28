import XCTest
@testable import VoxFlowApp

final class CapabilityModelViewPresentationTests: XCTestCase {
    func testCapabilityModelCardsExposeDownloadActionAndProgress() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/CapabilityModelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("downloadModel(id: model.id)"))
        XCTAssertTrue(source.contains("ProgressView(value: viewModel.downloadProgress)"))
        XCTAssertTrue(source.contains("Label(L10n.localize(\"model.capability.download_button\""))
    }

    func testCapabilityModelCardsUseRowSelectionInsteadOfUseButton() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/CapabilityModelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("viewModel.selectModel(id: model.id)"))
        XCTAssertFalse(source.contains("Label(\"使用\", systemImage: \"circle\")"))
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
            domain: "CapabilityModelViewPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
