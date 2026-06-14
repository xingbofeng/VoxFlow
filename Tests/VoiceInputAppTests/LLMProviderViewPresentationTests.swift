import XCTest
@testable import VoiceInputApp

final class LLMProviderViewPresentationTests: XCTestCase {
    func testProviderActionIconsUseStandardSymbols() {
        XCTAssertEqual(LLMProviderActionIcon.edit, "square.and.pencil")
        XCTAssertEqual(LLMProviderActionIcon.testConnection, "checkmark.circle")
        XCTAssertEqual(LLMProviderActionIcon.delete, "trash")
    }
}
