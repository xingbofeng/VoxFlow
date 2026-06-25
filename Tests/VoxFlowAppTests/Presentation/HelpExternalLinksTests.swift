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
        XCTAssertTrue(source.contains("鼠标中键"))
        XCTAssertTrue(source.contains("再次点击结束"))
    }

    func testHelpViewDocumentsCurrentWorkbenchAndUpdateEntry() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HelpView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("命令面板"))
        XCTAssertTrue(source.contains("截图 OCR"))
        XCTAssertTrue(source.contains("AI 编程"))
        XCTAssertTrue(source.contains("文件转写"))
        XCTAssertTrue(source.contains("笔记"))
        XCTAssertTrue(source.contains("易错词"))
        XCTAssertTrue(source.contains("检查更新"))
        XCTAssertTrue(source.contains("onCheckForUpdates()"))
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
