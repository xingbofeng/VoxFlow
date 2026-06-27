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

    func testScreenRecordingRequestExcludesOnlyOverlayControlsAndRecordingHUD() throws {
        let root = try Self.repositoryRoot()
        let appDelegate = try source(
            at: root.appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        )
        let method = try XCTUnwrap(
            appDelegate.range(
                of: #"private func handleScreenRecordingSelection\([\s\S]*?\n    private func stopActiveScreenRecording"#,
                options: .regularExpression
            ).map { String(appDelegate[$0]) }
        )

        let hud = try XCTUnwrap(method.range(of: "let hudPanel = ScreenRecordingHUDPanel()"))
        let exclusions = try XCTUnwrap(method.range(of: "overlayControls.excludedWindowIDs()"))
        let request = try XCTUnwrap(method.range(of: "ScreenRecordingRequest("))
        XCTAssertLessThan(hud.lowerBound, exclusions.lowerBound)
        XCTAssertLessThan(exclusions.lowerBound, request.lowerBound)
        XCTAssertTrue(method.contains("CGWindowID(hudPanel.windowNumber)"))
        XCTAssertTrue(method.contains("excludedWindowIDs: excludedWindowIDs"))
        XCTAssertFalse(method.contains("ScreenCaptureWindowExclusion.currentProcessWindowIDs()"))
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
