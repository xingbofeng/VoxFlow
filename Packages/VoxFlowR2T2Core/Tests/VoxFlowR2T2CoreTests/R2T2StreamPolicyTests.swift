import XCTest
@testable import VoxFlowR2T2Core

/// `R2T2Stream` 里两条不依赖模型权重的本地改动（见 `PROVENANCE.md`）。
///
/// `R2T2Stream` 必须先加载 2.4 GB 权重才能构造，所以这两条决策被抽成纯函数；
/// 这里钉的就是它们的行为，不需要模型。
final class R2T2StreamPolicyTests: XCTestCase {
    func testFinalDecodeIsIssuedWhenAudioWasProcessedEvenWithEmptyTail() {
        XCTAssertTrue(
            R2T2StreamPolicy.shouldIssueFinalDecode(hasBufferedTail: false, consumedSamples: 5_120),
            "录音结束在 chunk 边界上时仍需 final decode，否则最后一个非 final step 回滚的 token 永远不提交"
        )
    }

    func testFinalDecodeIsIssuedWhenOnlyATailIsBuffered() {
        XCTAssertTrue(
            R2T2StreamPolicy.shouldIssueFinalDecode(hasBufferedTail: true, consumedSamples: 0)
        )
    }

    func testFinalDecodeIsSkippedWhenTheSessionNeverReceivedAudio() {
        XCTAssertFalse(
            R2T2StreamPolicy.shouldIssueFinalDecode(hasBufferedTail: false, consumedSamples: 0),
            "没有音频的会话不得触发模型调用"
        )
    }

    func testStepHistoryIsDroppedOnlyWhenTheRecordedLimitIsReached() {
        XCTAssertEqual(
            R2T2StreamPolicy.stepHistoryDropCount(count: 3, limit: 5),
            0,
            "未到上限时不丢弃"
        )
        XCTAssertEqual(
            R2T2StreamPolicy.stepHistoryDropCount(count: 5, limit: 5),
            1,
            "到上限时为新条目腾出一位"
        )
        XCTAssertEqual(R2T2StreamPolicy.stepHistoryDropCount(count: 9, limit: 5), 5)
    }

    func testStepHistoryDropCountTreatsNonPositiveLimitAsNoRecording() {
        XCTAssertEqual(
            R2T2StreamPolicy.stepHistoryDropCount(count: 1_000, limit: 0),
            0,
            "limit 0 表示不记录，不进入裁剪路径"
        )
    }
}
