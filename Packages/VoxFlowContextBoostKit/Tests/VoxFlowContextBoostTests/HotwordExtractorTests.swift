import XCTest
@testable import VoxFlowContextBoost

final class HotwordExtractorTests: XCTestCase {
    func testExtractsRakeStyleKeyPhrasesFromNonTechnicalWindowText() {
        let extractor = HotwordExtractor()
        let text = """
        Project Apollo release plan
        Customer feedback about Project Apollo
        Schedule review and launch risk
        """

        let candidates = extractor.extract(from: text, namedEntities: [])

        XCTAssertTrue(candidates.containsText("Project Apollo"))
        XCTAssertTrue(candidates.contains { $0.text == "Project Apollo" && $0.source == .ocrKeyphrase })
    }

    func testExtractsRakeScoredKeyphrasesFromOCRText() {
        let extractor = HotwordExtractor()

        let hotwords = extractor.extract(
            from: """
            Review token budget manager before release.
            Update token budget manager tests.
            """
            ,
            namedEntities: [],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let phrase = hotwords.first { $0.text == "token budget manager" }
        XCTAssertNotNil(phrase)
        XCTAssertTrue(phrase?.evidence.contains { $0.reason == "rake_phrase" } == true)
    }

    func testExtractsNamedEntityCandidatesAsEvidence() {
        let extractor = HotwordExtractor()

        let candidates = extractor.extract(
            from: "Meeting notes with OpenAI and Shanghai team",
            namedEntities: [
                NamedEntityCandidate(text: "OpenAI", kind: .organization),
                NamedEntityCandidate(text: "Shanghai", kind: .place),
            ]
        )

        let openAI = candidates.first { $0.text == "OpenAI" }
        XCTAssertEqual(openAI?.source, .ocrNamedEntity)
        XCTAssertTrue(openAI?.evidence.contains { $0.reason == "named_entity:organization" } == true)
        XCTAssertTrue(candidates.containsText("Shanghai"))
    }

    func testExtractsShapeBasedIdentifiersAndFilenames() {
        let extractor = HotwordExtractor()
        let text = "Open Package.swift and update CorrectionContext for Qwen3-ASR and VNRecognizeTextRequest."

        let candidates = extractor.extract(from: text, namedEntities: [])

        XCTAssertTrue(candidates.containsText("Package.swift"))
        XCTAssertTrue(candidates.containsText("CorrectionContext"))
        XCTAssertTrue(candidates.containsText("Qwen3-ASR"))
        XCTAssertTrue(candidates.containsText("VNRecognizeTextRequest"))
    }

    func testShapeTokensRemainHigherWeightThanGenericRakePhrases() {
        let extractor = HotwordExtractor()

        let hotwords = extractor.extract(
            from: """
            Qwen3-ASR release checklist
            token budget manager
            """
            ,
            namedEntities: [],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let qwen = hotwords.first { $0.text == "Qwen3-ASR" }
        let phrase = hotwords.first { $0.text == "token budget manager" }

        XCTAssertNotNil(qwen)
        XCTAssertNotNil(phrase)
        XCTAssertGreaterThan(qwen?.score ?? 0, phrase?.score ?? 0)
    }

    func testExtractsShortChinesePhraseCandidatesWithoutKeepingGenericUIOrLongSentences() {
        let extractor = HotwordExtractor()
        let text = """
        取消
        确定
        码上写 发布计划
        语音键盘 体验反馈
        这是一个非常长的中文句子用来描述普通内容不应该整体进入热词列表
        """

        let candidates = extractor.extract(from: text, namedEntities: [])

        XCTAssertTrue(candidates.containsText("码上写"))
        XCTAssertTrue(candidates.containsText("语音键盘"))
        XCTAssertFalse(candidates.containsText("取消"))
        XCTAssertFalse(candidates.containsText("确定"))
        XCTAssertFalse(candidates.containsText("这是一个非常长的"))
        XCTAssertFalse(candidates.containsText("中文句子用来描述"))
        XCTAssertFalse(candidates.containsText("这是一个非常长的中文句子用来描述普通内容不应该整体进入热词列表"))
    }

    func testExtractionCapsInputAndCandidateCount() {
        let extractor = HotwordExtractor(maxCharacters: 120, maxCandidates: 5)
        let text = (0..<80)
            .map { "Project\($0) Token\($0)" }
            .joined(separator: "\n")

        let candidates = extractor.extract(from: text, namedEntities: [])

        XCTAssertLessThanOrEqual(candidates.count, 5)
        XCTAssertFalse(candidates.contains { $0.text.contains("Project79") })
    }
}

private extension Array where Element == TemporaryHotword {
    func containsText(_ text: String) -> Bool {
        contains { $0.text == text }
    }
}
