import XCTest
@testable import VoxFlowApp

final class PausePreOutputSessionTests: XCTestCase {
    private func makeConfiguration(
        minimumSegmentCharacterCount: Int = 2
    ) -> PausePreOutputConfiguration {
        PausePreOutputConfiguration(
            silenceThresholdNanoseconds: 700_000_000,
            minimumSegmentCharacterCount: minimumSegmentCharacterCount
        )
    }

    func testTakeDeltaReturnsTrimmedFullTextWhenNothingDeliveredYet() {
        var session = PausePreOutputSession(configuration: makeConfiguration())

        XCTAssertEqual(
            session.takeDelta(from: "  你好世界 ", enforcingMinimumCharacterCount: true),
            .text("你好世界")
        )
    }

    func testTakeDeltaReturnsDeltaBeyondDeliveredPrefixAfterAdvance() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "你好世界", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(
            session.takeDelta(from: "你好世界 下午好 ", enforcingMinimumCharacterCount: true),
            .text(" 下午好")
        )
    }

    func testDeltaPreservesWordAndParagraphSeparators() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "hello", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(session.takeDelta(from: "hello world", enforcingMinimumCharacterCount: true), .text(" world"))
        XCTAssertEqual(session.takeDelta(from: "hello world\nnext paragraph", enforcingMinimumCharacterCount: true), .text("\nnext paragraph"))
    }

    func testTakeDeltaReturnsNoDeltaWhenDeltaBelowMinimumCharacterCount() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "你好世界", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(
            session.takeDelta(from: "你好世界好", enforcingMinimumCharacterCount: true),
            .noDelta
        )

        XCTAssertEqual(
            session.takeDelta(from: "你好世界好", enforcingMinimumCharacterCount: false),
            .text("好")
        )
    }

    func testTakeDeltaReturnsNoDeltaWhenNoNewTextBeyondWatermark() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "你好世界", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(
            session.takeDelta(from: "你好世界", enforcingMinimumCharacterCount: true),
            .noDelta
        )
    }

    func testTakeDeltaToleratesPunctuationInsertedAtDeliveredPrefixBoundary() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "今天下午开会", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(
            session.takeDelta(from: "今天下午开会，讨论排期", enforcingMinimumCharacterCount: true),
            .text("，讨论排期")
        )
    }

    func testTakeDeltaTreatsPunctuationOnlyRemainderAsNoDeltaWhenEnforcingMinimum() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "今天下午开会", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(
            session.takeDelta(from: "今天下午开会，", enforcingMinimumCharacterCount: true),
            .noDelta
        )
    }

    func testTakeDeltaMarksSessionBrokenWhenEngineRevisesDeliveredPrefix() {
        var session = PausePreOutputSession(configuration: makeConfiguration())
        _ = session.takeDelta(from: "你好世界", enforcingMinimumCharacterCount: true)

        XCTAssertEqual(
            session.takeDelta(from: "你们好世界下午", enforcingMinimumCharacterCount: true),
            .revised
        )
        XCTAssertEqual(
            session.takeDelta(from: "你们好世界下午好", enforcingMinimumCharacterCount: true),
            .revised
        )
    }
}
