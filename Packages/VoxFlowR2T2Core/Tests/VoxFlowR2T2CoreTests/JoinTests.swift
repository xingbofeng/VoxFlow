import XCTest
@testable import VoxFlowR2T2Core

/// `R2T2Text.joining` — what the stream EMITS when the loop restarts from an empty prefix (after a
/// pause longer than the window, or a hallucination reset). Upstream concatenates verbatim, so
/// English after a 20 s pause read "the lakesOn August" (ML[X] Audio Studio M14-C item 6).
final class JoinTests: XCTestCase {
    func testARestartAfterEnglishGetsASpace() {
        XCTAssertEqual(R2T2Text.joining("On August", after: "if ever she visited the lakes", restarted: true), " On August")
        XCTAssertEqual(R2T2Text.joining("Come, come", after: "she writes", restarted: true), " Come, come")
        XCTAssertEqual(R2T2Text.joining("Then", after: "she writes.", restarted: true), " Then")
    }

    func testMidStreamDeltasAreNeverTouched() {
        // Subword continuations: a space here would split the word.
        XCTAssertEqual(R2T2Text.joining("er", after: "a glean", restarted: false), "er")
        XCTAssertEqual(R2T2Text.joining(" bringing", after: "a gleaner", restarted: false), " bringing")
    }

    func testUnspacedScriptsNeverGetOne() {
        XCTAssertEqual(R2T2Text.joining("之前有顾客", after: "不让喝。", restarted: true), "之前有顾客")
        XCTAssertEqual(R2T2Text.joining("Hello", after: "你好", restarted: true), "Hello")
        XCTAssertEqual(R2T2Text.joining("今日は", after: "ありがとう", restarted: true), "今日は")
    }

    func testPunctuationWhitespaceAndTheFirstPieceAreLeftAlone() {
        XCTAssertEqual(R2T2Text.joining(", yes", after: "no", restarted: true), ", yes")
        XCTAssertEqual(R2T2Text.joining(" On", after: "lakes", restarted: true), " On")
        XCTAssertEqual(R2T2Text.joining("On", after: "lakes ", restarted: true), "On")
        XCTAssertEqual(R2T2Text.joining("On", after: "", restarted: true), "On")
        XCTAssertEqual(R2T2Text.joining("", after: "lakes", restarted: true), "")
    }
}
