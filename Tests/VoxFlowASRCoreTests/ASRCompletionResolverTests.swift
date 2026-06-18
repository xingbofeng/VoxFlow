import XCTest
import VoxFlowASRCore

final class ASRCompletionResolverTests: XCTestCase {
    func testFinalTimeoutDoesNotPromoteLatestPartialToCompletedFinal() {
        let sessionID = ASRSessionID(rawValue: "completion-session")
        let timeout = ASRError(
            category: .finalTimeout,
            message: "Timed out waiting for explicit final."
        )
        var resolver = ASRCompletionResolver(sessionID: sessionID)

        XCTAssertEqual(
            resolver.apply(Self.partial(sessionID: sessionID, text: "latest partial", revision: 1)),
            .awaitingFinal(recoverablePartial: "latest partial")
        )
        XCTAssertEqual(
            resolver.apply(.failure(sessionID: sessionID, revision: 2, error: timeout)),
            .failed(error: timeout, recoverablePartial: "latest partial")
        )
    }

    func testExplicitFinalCompletesWithFinalText() {
        let sessionID = ASRSessionID(rawValue: "completion-session")
        var resolver = ASRCompletionResolver(sessionID: sessionID)

        _ = resolver.apply(Self.partial(sessionID: sessionID, text: "latest partial", revision: 1))

        XCTAssertEqual(
            resolver.apply(.final(sessionID: sessionID, revision: 2, text: "true final")),
            .completed(finalText: "true final")
        )
    }

    private static func partial(
        sessionID: ASRSessionID,
        text: String,
        revision: UInt64
    ) -> ASREvent {
        .partial(
            sessionID: sessionID,
            transcript: PartialTranscript(
                stablePrefix: "",
                unstableSuffix: text,
                revision: revision,
                audioDuration: .zero
            )
        )
    }
}
