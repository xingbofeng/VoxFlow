import XCTest

final class VoxFlowSelfCaptureWindowSharingTests: XCTestCase {
    func testPrimaryVoxFlowWindowsRemainReadableByScreenCaptureKit() throws {
        let root = try Self.repositoryRoot()
        let mainWindow = try source(
            at: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/MainWindowController.swift")
        )
        let textResultPanel = try source(
            at: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelController.swift")
        )
        let voiceHUD = try source(
            at: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/OverlayWindowController.swift")
        )

        XCTAssertTrue(mainWindow.contains("window.sharingType = .readOnly"))
        XCTAssertTrue(textResultPanel.contains("panel.sharingType = .readOnly"))
        XCTAssertTrue(voiceHUD.contains("window.sharingType = .readOnly"))
    }

    private func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "VoxFlowSelfCaptureWindowSharingTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift."]
        )
    }
}
