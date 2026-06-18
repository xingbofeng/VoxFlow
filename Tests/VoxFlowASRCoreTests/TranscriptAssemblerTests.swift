import XCTest
import VoxFlowASRCore

final class TranscriptAssemblerTests: XCTestCase {
    func testAssemblerHandlesEmptyPartial() {
        let sessionID = ASRSessionID(rawValue: "session")
        var assembler = TranscriptAssembler(sessionID: sessionID)

        let state = assembler.apply(
            .partial(
                sessionID: sessionID,
                transcript: PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: "",
                    revision: 1,
                    audioDuration: .zero
                )
            )
        )

        XCTAssertEqual(state?.stablePrefix, "")
        XCTAssertEqual(state?.unstableSuffix, "")
        XCTAssertEqual(state?.revision, 1)
    }

    func testAssemblerDiscardsOldSessionAndOldRevisionEvents() {
        let sessionID = ASRSessionID(rawValue: "current")
        var assembler = TranscriptAssembler(sessionID: sessionID)

        XCTAssertNil(
            assembler.apply(
                .partial(
                    sessionID: ASRSessionID(rawValue: "old"),
                    transcript: PartialTranscript(
                        stablePrefix: "old",
                        unstableSuffix: "",
                        revision: 1,
                        audioDuration: .zero
                    )
                )
            )
        )

        _ = assembler.apply(Self.partial(sessionID: sessionID, stable: "hello", unstable: " wor", revision: 2))
        XCTAssertNil(assembler.apply(Self.partial(sessionID: sessionID, stable: "hello", unstable: " old", revision: 1)))
        XCTAssertEqual(assembler.state.stablePrefix, "hello")
        XCTAssertEqual(assembler.state.unstableSuffix, " wor")
    }

    func testAssemblerProtectsStablePrefixAndAllowsUnstableRewrite() {
        let sessionID = ASRSessionID(rawValue: "session")
        var assembler = TranscriptAssembler(sessionID: sessionID)

        _ = assembler.apply(Self.partial(sessionID: sessionID, stable: "hello ", unstable: "wor", revision: 1))
        let rewritten = assembler.apply(Self.partial(sessionID: sessionID, stable: "hello ", unstable: "world", revision: 2))
        let conflictingStable = assembler.apply(Self.partial(sessionID: sessionID, stable: "hell", unstable: "x", revision: 3))

        XCTAssertEqual(rewritten?.stablePrefix, "hello ")
        XCTAssertEqual(rewritten?.unstableSuffix, "world")
        XCTAssertEqual(conflictingStable?.stablePrefix, "hello ")
    }

    func testAssemblerSupportsDoubleFinalReplacement() {
        let sessionID = ASRSessionID(rawValue: "session")
        var assembler = TranscriptAssembler(sessionID: sessionID)

        _ = assembler.apply(.final(sessionID: sessionID, revision: 10, text: "first final"))
        let replacement = assembler.apply(.final(sessionID: sessionID, revision: 11, text: "better final"))

        XCTAssertEqual(replacement?.finalText, "better final")
        XCTAssertEqual(replacement?.stablePrefix, "better final")
        XCTAssertEqual(replacement?.unstableSuffix, "")
    }

    func testAssemblerDoesNotTruncateGraphemeClusters() {
        let sessionID = ASRSessionID(rawValue: "session")
        var assembler = TranscriptAssembler(sessionID: sessionID)
        let family = "👨‍👩‍👧‍👦 "

        _ = assembler.apply(Self.partial(sessionID: sessionID, stable: family, unstable: "open", revision: 1))
        let state = assembler.apply(Self.partial(sessionID: sessionID, stable: family, unstable: "open file", revision: 2))

        XCTAssertEqual(state?.stablePrefix, family)
        XCTAssertEqual(state?.stablePrefix.count, 2)
    }

    private static func partial(
        sessionID: ASRSessionID,
        stable: String,
        unstable: String,
        revision: UInt64
    ) -> ASREvent {
        .partial(
            sessionID: sessionID,
            transcript: PartialTranscript(
                stablePrefix: stable,
                unstableSuffix: unstable,
                revision: revision,
                audioDuration: .zero
            )
        )
    }
}
