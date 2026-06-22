import XCTest
@testable import VoxFlowContextBoost

final class RakeKeywordExtractorTests: XCTestCase {
    func testExtractsHighSignalEnglishPhrases() {
        let extractor = RakeKeywordExtractor()

        let phrases = extractor.extractPhrases(
            from: """
            Review token budget manager before release.
            Update token budget manager tests.
            Open Project Apollo release notes.
            """
        )

        XCTAssertTrue(phrases.contains("token budget manager"))
        XCTAssertTrue(phrases.contains("Project Apollo release notes"))
        XCTAssertFalse(phrases.contains("Review"))
        XCTAssertFalse(phrases.contains("before"))
    }

    func testKeepsHyphenUnderscoreAndDotInsideTokens() {
        let extractor = RakeKeywordExtractor()

        let phrases = extractor.extractPhrases(
            from: "Compare speech-swift Package.swift context_boost trace."
        )

        XCTAssertTrue(phrases.contains("speech-swift Package.swift context_boost trace"))
    }

    func testLimitsPhraseLengthAndResultCount() {
        let extractor = RakeKeywordExtractor(maxPhraseWords: 4, maxPhrases: 2)

        let phrases = extractor.extractPhrases(
            from: """
            Alpha Beta Gamma Delta Epsilon Zeta
            Project Apollo Release Notes
            Token Budget Manager
            """
        )

        XCTAssertLessThanOrEqual(phrases.count, 2)
        XCTAssertFalse(phrases.contains { $0.split(separator: " ").count > 4 })
    }

    func testRakeExtractionStaysFastForLargeOCRText() {
        let extractor = RakeKeywordExtractor()
        let line = "Review token budget manager Project Apollo release notes Package.swift speech-swift Qwen3-ASR.\n"
        let text = String(repeating: line, count: 200)

        measure {
            _ = extractor.extractPhrases(from: text)
        }
    }
}
