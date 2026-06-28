import XCTest
@testable import VoxFlowApp

final class HelpExternalLinksTests: XCTestCase {
    func testProjectHomepageUsesLandingPage() {
        XCTAssertEqual(HelpExternalLinks.projectHomepage, "https://xingbofeng.github.io/VoxFlow/")
    }

    func testGitHubRepositoryRemainsSeparateEntry() {
        XCTAssertEqual(HelpExternalLinks.githubRepository, "https://github.com/xingbofeng/VoxFlow")
    }

    func testHelpViewDocumentsMiddleMouseToggleWhenEnabled() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HelpView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settingsViewModel.middleMouseRecordingEnabled"))
        XCTAssertTrue(source.contains("help.shortcuts.display_name_with_middle_mouse"))
        XCTAssertTrue(source.contains("help.shortcuts.subtitle_toggle_with_middle_mouse"))
    }

    func testHelpViewDocumentsCurrentWorkbenchAndUpdateEntry() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HelpView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("help.cards.command_panel_title"))
        XCTAssertTrue(source.contains("help.cards.screenshot_ocr_title"))
        XCTAssertTrue(source.contains("help.cards.ai_coding_title"))
        XCTAssertTrue(source.contains("help.cards.transcription_notes_title"))
        XCTAssertTrue(source.contains("help.cards.easy_correction_title"))
        XCTAssertTrue(source.contains("help.actions.check_updates_title"))
        XCTAssertTrue(source.contains("onCheckForUpdates()"))
    }

    func testHelpViewDocumentsSupportProjectAndCommunityEntry() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HelpView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("help.actions.community_title"))
        XCTAssertTrue(source.contains("help.overlay.github_star_title"))
        XCTAssertTrue(source.contains("help.overlay.subtitle"))
    }

    func testHelpFeatureCardsUseAConsistentFixedHeight() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HelpView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("static let cardHeight"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: Self.cardHeight"))
        XCTAssertTrue(source.contains(".frame(height: Self.cardHeight)"))
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
            domain: "HelpExternalLinksTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
