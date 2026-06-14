import XCTest
@testable import VoiceInputApp

final class TranscriptionSessionTests: XCTestCase {
    func testFinalResultAfterReleaseCompletesImmediately() {
        var session = TranscriptionSession()

        XCTAssertNil(session.update(text: "部分", isFinal: false))
        XCTAssertNil(session.release())
        XCTAssertEqual(session.update(text: "最终文本", isFinal: true), "最终文本")
    }

    func testFinalResultBeforeReleaseCompletesWhenReleased() {
        var session = TranscriptionSession()

        XCTAssertNil(session.update(text: "最终文本", isFinal: true))
        XCTAssertEqual(session.release(), "最终文本")
    }

    func testTimeoutUsesLatestPartialResult() {
        var session = TranscriptionSession()

        XCTAssertNil(session.update(text: "最新 partial", isFinal: false))
        XCTAssertNil(session.release())
        XCTAssertEqual(session.timeout(), "最新 partial")
    }

    func testEmptyFinalAfterPartialCompletesWithLatestPartial() {
        var session = TranscriptionSession()

        XCTAssertNil(session.update(text: "保留这段 partial", isFinal: false))
        XCTAssertNil(session.release())
        XCTAssertEqual(session.update(text: "", isFinal: true), "保留这段 partial")
    }

    func testFallbackUsesLatestPartialEvenBeforeRelease() {
        var session = TranscriptionSession()

        XCTAssertNil(session.update(text: "最新 partial", isFinal: false))
        XCTAssertEqual(session.fallbackToLatestText(), "最新 partial")
        XCTAssertNil(session.update(text: "迟到文本", isFinal: true))
    }

    func testSessionCanOnlyCompleteOnce() {
        var session = TranscriptionSession()

        _ = session.update(text: "文本", isFinal: false)
        _ = session.release()

        XCTAssertEqual(session.timeout(), "文本")
        XCTAssertNil(session.update(text: "迟到的 final", isFinal: true))
        XCTAssertNil(session.timeout())
    }
}
