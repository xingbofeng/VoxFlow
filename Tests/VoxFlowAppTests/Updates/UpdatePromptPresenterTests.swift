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

    func testUpdatePromptUsesMainShellOverlayInsteadOfFullScreenPanel() throws {
        let root = try Self.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Updates/UpdatePromptPresenter.swift"),
            encoding: .utf8
        )
        let shellSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/MainShellView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("final class UpdatePromptPresentationStore: ObservableObject"))
        XCTAssertTrue(shellSource.contains("@ObservedObject var updatePromptStore: UpdatePromptPresentationStore"))
        XCTAssertTrue(shellSource.contains("if let updatePrompt = updatePromptStore.presentation"))
        XCTAssertTrue(shellSource.contains("UpdatePromptOverlayView(presentation: updatePrompt"))
        XCTAssertTrue(source.contains("Color.black.opacity(0.18)"))
        XCTAssertTrue(source.contains("RoundedRectangle(cornerRadius: 28"))
        XCTAssertTrue(source.contains(".shadow(color: .black.opacity(0.16), radius: 28, y: 12)"))
        XCTAssertFalse(source.contains("UpdatePromptPanel"))
        XCTAssertFalse(source.contains("styleMask: [.borderless]"))
        XCTAssertFalse(source.contains("overlayFrame"))
        XCTAssertFalse(source.contains("window.level = .modalPanel"))
        XCTAssertFalse(source.contains("Spacer(minLength: 0)"))
        XCTAssertFalse(source.contains("window.center()"))
        XCTAssertFalse(source.contains("styleMask: [.titled, .closable]"))
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
