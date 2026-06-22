import XCTest
@testable import VoxFlowApp

@MainActor
final class PendingCorrectionFallbackControllerTests: XCTestCase {
    func testConsumeRawTextReturnsTrimmedTextOnce() {
        let controller = PendingCorrectionFallbackController()

        let token = controller.begin(rawText: "  纠错前原文  ")

        XCTAssertNotNil(token)
        XCTAssertTrue(controller.hasPending)
        XCTAssertEqual(controller.consumeRawText(), "纠错前原文")
        XCTAssertFalse(controller.hasPending)
        XCTAssertNil(controller.consumeRawText())
    }

    func testCompletingStaleTokenDoesNotClearNewPendingText() throws {
        let controller = PendingCorrectionFallbackController()
        let staleToken = try XCTUnwrap(controller.begin(rawText: "第一段"))
        let currentToken = try XCTUnwrap(controller.begin(rawText: "第二段"))

        controller.finish(staleToken)

        XCTAssertTrue(controller.hasPending)
        XCTAssertEqual(controller.consumeRawText(), "第二段")
        controller.finish(currentToken)
        XCTAssertFalse(controller.hasPending)
    }

    func testEmptyRawTextDoesNotCreatePendingFallback() {
        let controller = PendingCorrectionFallbackController()

        XCTAssertNil(controller.begin(rawText: " \n\t "))
        XCTAssertFalse(controller.hasPending)
    }
}
