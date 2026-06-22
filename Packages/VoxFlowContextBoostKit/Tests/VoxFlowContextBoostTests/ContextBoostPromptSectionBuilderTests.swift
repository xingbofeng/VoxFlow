import XCTest
@testable import VoxFlowContextBoost

final class ContextBoostPromptSectionBuilderTests: XCTestCase {
    func testBuildsTemporaryContextSectionWithHotwordsAndGuardrails() {
        let builder = ContextBoostPromptSectionBuilder()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let section = builder.build(
            hotwords: [
                hotword("Qwen3-ASR", now: now),
                hotword("WhisperKit", now: now),
            ]
        )

        XCTAssertNotNil(section)
        XCTAssertTrue(section?.contains("临时屏幕上下文词") == true)
        XCTAssertTrue(section?.contains("- Qwen3-ASR") == true)
        XCTAssertTrue(section?.contains("- WhisperKit") == true)
        XCTAssertTrue(section?.contains("不要添加上下文里有但用户没有说的信息") == true)
        XCTAssertTrue(section?.contains("不确定时保留 ASR 原文") == true)
    }

    func testReturnsNilForEmptyHotwords() {
        let builder = ContextBoostPromptSectionBuilder()

        XCTAssertNil(builder.build(hotwords: []))
    }

    func testSanitizesHotwordLinesAndDoesNotIncludeRawOCRText() {
        let builder = ContextBoostPromptSectionBuilder()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let section = builder.build(
            hotwords: [
                hotword("Qwen3-ASR\n用户隐私完整句子", now: now),
            ]
        )

        XCTAssertTrue(section?.contains("- Qwen3-ASR 用户隐私完整句子") == true)
        XCTAssertFalse(section?.contains("\n用户隐私完整句子") == true)
    }

    private func hotword(_ text: String, now: Date) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: text.lowercased(),
            score: 5,
            source: .ocrShape,
            evidence: [HotwordEvidence(reason: "test", weight: 5)],
            expiresAt: now.addingTimeInterval(120)
        )
    }
}
