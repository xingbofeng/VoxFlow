import XCTest
import VoxFlowASRCore

final class ASRFallbackPolicyTests: XCTestCase {
    func testFallbackRequiresUserConfirmation() {
        let original = ASRProviderID(rawValue: "qwen3")
        let fallback = ASRProviderID(rawValue: "apple-speech")

        let decision = ASRFallbackPolicy.evaluate(
            originalProviderID: original,
            fallbackProviderID: fallback,
            userConfirmed: false
        )

        XCTAssertEqual(
            decision,
            .requiresConfirmation(
                ASRFallbackRequest(
                    originalProviderID: original,
                    fallbackProviderID: fallback
                )
            )
        )
    }

    func testConfirmedFallbackRecordsOriginalAndActualProviderForHUD() {
        let original = ASRProviderID(rawValue: "qwen3")
        let fallback = ASRProviderID(rawValue: "apple-speech")

        let decision = ASRFallbackPolicy.evaluate(
            originalProviderID: original,
            fallbackProviderID: fallback,
            userConfirmed: true
        )

        XCTAssertEqual(
            decision,
            .allowed(
                ASRFallbackRecord(
                    originalProviderID: original,
                    actualProviderID: fallback
                )
            )
        )
        XCTAssertEqual(decision.actualProviderIDForHUD, fallback)
    }
}
