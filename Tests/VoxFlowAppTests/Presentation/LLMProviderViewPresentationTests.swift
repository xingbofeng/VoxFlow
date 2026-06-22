import XCTest
@testable import VoxFlowApp

final class LLMProviderViewPresentationTests: XCTestCase {
    func testProviderActionIconsUseStandardSymbols() {
        XCTAssertEqual(LLMProviderActionIcon.edit, "square.and.pencil")
        XCTAssertEqual(LLMProviderActionIcon.testConnection, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(LLMProviderActionIcon.delete, "trash")
    }

    func testDefaultEnabledProviderSelectionAreaIsNotDisabled() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/LLMProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".disabled(provider.isDefault || !provider.enabled)"))
    }

    func testProviderRowsUseDisplayNameInitialBadges() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/LLMProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("displayName: provider.displayName"))
        XCTAssertTrue(source.contains("ProviderInitialBadge("))
        XCTAssertFalse(source.contains("systemImage: \"sparkles\""))
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
            domain: "LLMProviderViewPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
