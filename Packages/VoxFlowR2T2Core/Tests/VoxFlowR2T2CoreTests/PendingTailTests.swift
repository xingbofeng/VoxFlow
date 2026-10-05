import XCTest
@testable import VoxFlowR2T2Core

/// `R2T2Text.pendingTail` — 本步被回滚（扣下）的尾部文本。
///
/// 上游每一步只提交解码结果去掉 `unfixedTokens` 个 token 之后的部分（`rollback`），扣下的尾部
/// 留到下一步带更多上下文重新解码。这部分文本过去完全不出 driver，HUD 因此恒定落后一个 token：
/// 中文口述时表现为「最后一个字不显示」，末尾正好是双字词 token 时表现为「最后两个字不显示」。
///
/// 这些 token 仍可能被下一步改写，所以它只能进 `PartialTranscript.unstableSuffix`（实时预览），
/// 永远不能进最终文本。
final class PendingTailTests: XCTestCase {
    func testTheRolledBackTailIsReturned() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "这是一句话", committed: "这是一句"), "话")
    }

    func testNothingIsPendingWhenEverythingWasCommitted() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "这是一句话", committed: "这是一句话"), "")
    }

    /// 词表里 `今天` `我们` `什么` 这类双字词本身就是单个 token，回滚 1 个 token 会扣下两个字。
    /// 这解释了同一现象为什么有时掉一个字、有时掉两个字。
    func testAMultiCharacterTokenIsWithheldWhole() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "我们今天", committed: "我们"), "今天")
    }

    /// 什么都没有提交时，整个解码结果都还在待定区。
    func testTheWholeDecodeIsPendingWhenNothingWasCommitted() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "话", committed: ""), "话")
    }

    func testEnglishKeepsTheWordBoundarySpace() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "hello world", committed: "hello "), "world")
    }

    /// BPE 编解码往返并非恒等，或调用方传错时：宁可什么都不暴露，也不要把错位的文本交给 HUD。
    func testNothingIsExposedWhenTheCommitIsNotAPrefix() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "这是一句话", committed: "那句话"), "")
    }

    func testAnEmptyDecodeHasNoPendingTail() {
        XCTAssertEqual(R2T2Text.pendingTail(rawDecoded: "", committed: ""), "")
    }
}
