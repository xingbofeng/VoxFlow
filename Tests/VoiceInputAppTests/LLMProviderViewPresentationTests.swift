import XCTest
@testable import VoiceInputApp

final class LLMProviderViewPresentationTests: XCTestCase {
    func testProviderActionIconsUseStandardSymbols() {
        XCTAssertEqual(LLMProviderActionIcon.edit, "square.and.pencil")
        XCTAssertEqual(LLMProviderActionIcon.testConnection, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(LLMProviderActionIcon.delete, "trash")
    }

    func testDefaultEnabledProviderSelectionAreaIsNotDisabled() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoiceInputApp/LLMProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".disabled(provider.isDefault || !provider.enabled)"))
    }
}
