import XCTest
@testable import VoxFlowApp

final class LLMProviderViewPresentationTests: XCTestCase {
    func testProviderActionIconsUseStandardSymbols() {
        XCTAssertEqual(LLMProviderActionIcon.edit, "square.and.pencil")
        XCTAssertEqual(LLMProviderActionIcon.testConnection, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(LLMProviderActionIcon.delete, "trash")
    }

}
