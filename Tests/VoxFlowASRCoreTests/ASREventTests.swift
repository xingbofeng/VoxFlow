import XCTest
import VoxFlowASRCore

final class ASREventTests: XCTestCase {
    func testPartialTranscriptSeparatesStableAndUnstableText() {
        let partial = PartialTranscript(
            stablePrefix: "打开 ",
            unstableSuffix: "SettingsView",
            revision: 3,
            audioDuration: .seconds(2)
        )

        XCTAssertEqual(partial.stablePrefix, "打开 ")
        XCTAssertEqual(partial.unstableSuffix, "SettingsView")
        XCTAssertEqual(partial.revision, 3)
        XCTAssertEqual(partial.audioDuration, .seconds(2))
    }

    func testASREventsCarrySessionIDAndRevision() {
        let sessionID = ASRSessionID(rawValue: "session-1")
        let partial = PartialTranscript(
            stablePrefix: "hello",
            unstableSuffix: " wor",
            revision: 4,
            audioDuration: .milliseconds(1500)
        )

        XCTAssertEqual(
            ASREvent.partial(sessionID: sessionID, transcript: partial).sessionID,
            sessionID
        )
        XCTAssertEqual(
            ASREvent.partial(sessionID: sessionID, transcript: partial).revision,
            4
        )
        XCTAssertEqual(
            ASREvent.final(sessionID: sessionID, revision: 5, text: "hello world").revision,
            5
        )
    }

    func testASRErrorCategoriesCoverRequiredCoreFailures() {
        let requiredErrors: Set<ASRErrorCategory> = [
            .modelNotInstalled,
            .modelCorrupt,
            .runtimeUnsupported,
            .hardwareUnsupported,
            .unsupportedLanguage,
            .preparationFailed,
            .firstPartialTimeout,
            .streamStalled,
            .finalTimeout,
            .emptyTranscript,
            .workerCrashed,
            .audioDropped,
            .cancelled,
        ]

        XCTAssertEqual(Set(ASRErrorCategory.allCases), requiredErrors)
    }
}
