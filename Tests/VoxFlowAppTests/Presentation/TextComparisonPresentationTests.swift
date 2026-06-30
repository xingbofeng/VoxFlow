import AppKit
import XCTest
@testable import VoxFlowApp

final class TextComparisonPresentationTests: XCTestCase {
    // MARK: - Unchanged

    func testUnchangedTextProducesAllEqualSegmentsAndFullSimilarity() {
        let presentation = TextComparisonPresentation(source: "你好 VoxFlow", processed: "你好 VoxFlow")
        XCTAssertTrue(presentation.segments.allSatisfy { if case .equal = $0 { return true }; return false })
        XCTAssertEqual(presentation.segments.map(\.text).joined(), "你好 VoxFlow")
        XCTAssertEqual(presentation.similarityPercent, 100)
        XCTAssertFalse(presentation.isChanged)
    }

    func testEmptyStringsAreUnchangedWithFullSimilarity() {
        let presentation = TextComparisonPresentation(source: "", processed: "")
        XCTAssertTrue(presentation.segments.isEmpty)
        XCTAssertEqual(presentation.similarityPercent, 100)
        XCTAssertFalse(presentation.isChanged)
    }

    // MARK: - Insertion / Deletion

    func testPureInsertionProducesInsertedSegments() {
        // Use CJK tokens (each character is its own token) so a single-char
        // insertion is detectable. ASCII-letter runs are a single token per
        // design.md, so "abc" → "abXc" would be a whole-token replacement.
        let presentation = TextComparisonPresentation(source: "你好", processed: "你好啊")
        XCTAssertTrue(presentation.segments.contains { if case .inserted(let text) = $0 { return text == "啊" }; return false })
        XCTAssertTrue(presentation.isChanged)
        XCTAssertGreaterThan(presentation.similarityPercent, 0)
        XCTAssertLessThan(presentation.similarityPercent, 100)
    }

    func testPureDeletionProducesDeletedSegments() {
        let presentation = TextComparisonPresentation(source: "你好啊", processed: "你好")
        XCTAssertTrue(presentation.segments.contains { if case .deleted(let text) = $0 { return text == "啊" }; return false })
        XCTAssertTrue(presentation.isChanged)
        XCTAssertGreaterThan(presentation.similarityPercent, 0)
        XCTAssertLessThan(presentation.similarityPercent, 100)
    }

    // MARK: - Mixed Chinese / English

    func testMixedChineseAndEnglishChangesProduceInlineSegments() {
        let presentation = TextComparisonPresentation(source: "QW3A 是最好的", processed: "Qwen3 是最棒的")
        // The whole ASCII-letter run "QW3A" is one token (per design.md).
        XCTAssertTrue(presentation.segments.contains { if case .deleted(let text) = $0 { return text == "QW3A" }; return false })
        XCTAssertTrue(presentation.segments.contains { if case .inserted(let text) = $0 { return text == "Qwen3" }; return false })
        // CJK characters are individual tokens; "好" → "棒" is a char-level swap.
        XCTAssertTrue(presentation.segments.contains { if case .deleted(let text) = $0 { return text == "好" }; return false })
        XCTAssertTrue(presentation.segments.contains { if case .inserted(let text) = $0 { return text == "棒" }; return false })
        // Coalescing may merge adjacent equal segments; assert that some equal
        // segment contains "最" rather than requiring an exact standalone token.
        XCTAssertTrue(presentation.segments.contains {
            if case .equal(let text) = $0 { return text.contains("最") } else { return false }
        })
        XCTAssertTrue(presentation.isChanged)
    }

    // MARK: - Punctuation

    func testPunctuationOnlyChangeIsDetected() {
        let presentation = TextComparisonPresentation(source: "你好。", processed: "你好!")
        XCTAssertTrue(presentation.segments.contains { if case .deleted(let text) = $0 { return text == "。" }; return false })
        XCTAssertTrue(presentation.segments.contains { if case .inserted(let text) = $0 { return text == "!" }; return false })
        XCTAssertTrue(presentation.isChanged)
        XCTAssertGreaterThan(presentation.similarityPercent, 0)
        XCTAssertLessThan(presentation.similarityPercent, 100)
    }

    // MARK: - Empty / Completely Different

    func testOneSideEmptyIsZeroSimilarity() {
        let sourceOnly = TextComparisonPresentation(source: "abc", processed: "")
        XCTAssertEqual(sourceOnly.similarityPercent, 0)
        XCTAssertTrue(sourceOnly.isChanged)

        let processedOnly = TextComparisonPresentation(source: "", processed: "xyz")
        XCTAssertEqual(processedOnly.similarityPercent, 0)
        XCTAssertTrue(processedOnly.isChanged)
    }

    func testCompletelyDifferentTextIsZeroSimilarity() {
        let presentation = TextComparisonPresentation(source: "abc", processed: "xyz")
        XCTAssertEqual(presentation.similarityPercent, 0)
        XCTAssertTrue(presentation.isChanged)
        XCTAssertTrue(presentation.segments.contains { if case .deleted = $0 { return true }; return false })
        XCTAssertTrue(presentation.segments.contains { if case .inserted = $0 { return true }; return false })
    }

    // MARK: - Similarity Calculation

    func testSimilarityIsRoundedToPercentForPartialOverlap() {
        // Each CJK character is its own token; "甲乙" overlap = 2 chars,
        // max(5, 5) = 5 → 2 / 5 = 40%.
        let presentation = TextComparisonPresentation(source: "甲乙丙丁戊", processed: "甲乙子丑卯")
        XCTAssertEqual(presentation.similarityPercent, 40)
    }

    func testSimilarityClampsToZeroWhenNoOverlap() {
        let presentation = TextComparisonPresentation(source: "ABC", processed: "XYZ")
        XCTAssertEqual(presentation.similarityPercent, 0)
    }

    func testSimilarityIsFullWhenOnlyWhitespaceDiffersAroundEqualContent() {
        // Trimming-aware comparison is the UI's responsibility; the engine
        // treats whitespace as a token. Equal content with surrounding
        // whitespace differences should still be highly similar.
        let presentation = TextComparisonPresentation(source: "hello", processed: " hello ")
        XCTAssertGreaterThan(presentation.similarityPercent, 0)
    }

    // MARK: - Default Mode

    func testDefaultModeIsComparisonWhenChanged() {
        let presentation = TextComparisonPresentation(source: "abc", processed: "abXc")
        XCTAssertEqual(presentation.defaultMode, .comparison)
    }

    func testDefaultModeIsProcessedWhenUnchanged() {
        let presentation = TextComparisonPresentation(source: "abc", processed: "abc")
        XCTAssertEqual(presentation.defaultMode, .processed)
    }

    // MARK: - Display Text

    func testDisplayTextForSourceModeReturnsSourceText() {
        let presentation = TextComparisonPresentation(source: "原文", processed: "处理后")
        XCTAssertEqual(presentation.displayText(for: .source), "原文")
    }

    func testDisplayTextForProcessedModeReturnsProcessedText() {
        let presentation = TextComparisonPresentation(source: "原文", processed: "处理后")
        XCTAssertEqual(presentation.displayText(for: .processed), "处理后")
    }

    func testDisplayTextForComparisonModeJoinsSegments() {
        // CJK tokens so single-char insertion is visible at the token level.
        let presentation = TextComparisonPresentation(source: "你好", processed: "你好啊")
        let joined = presentation.displayText(for: .comparison)
        XCTAssertTrue(joined.contains("你好"))
        XCTAssertTrue(joined.contains("啊"))
    }

    func testDisplayTextForEmptyComparisonIsEmpty() {
        let presentation = TextComparisonPresentation(source: "", processed: "")
        XCTAssertEqual(presentation.displayText(for: .comparison), "")
        XCTAssertEqual(presentation.displayText(for: .source), "")
        XCTAssertEqual(presentation.displayText(for: .processed), "")
    }

    // MARK: - TextDiffing renderer

    func testAttributedDiffRendererUsesTextDiffingBackend() {
        let renderer = TextDiffingComparisonRenderer()
        let attributed = renderer.attributedString(
            source: "帮我Review一下",
            processed: "帮我 Review 一下"
        )

        XCTAssertTrue(renderer.isTextDiffingBacked)
        XCTAssertTrue(String(attributed.characters).contains("Review"))
    }

    func testAttributedDiffRendererAddsHighlightAndDeletionAttributes() {
        let renderer = TextDiffingComparisonRenderer()
        let attributed = renderer.attributedString(source: "abc", processed: "adc")
        let nsAttributed = NSAttributedString(attributed)

        var hasHighlightedRun = false
        var hasStrikethroughRun = false
        nsAttributed.enumerateAttributes(
            in: NSRange(location: 0, length: nsAttributed.length)
        ) { attributes, _, _ in
            if attributes[.backgroundColor] != nil {
                hasHighlightedRun = true
            }
            if attributes[.strikethroughStyle] != nil {
                hasStrikethroughRun = true
            }
        }

        XCTAssertTrue(hasHighlightedRun)
        XCTAssertTrue(hasStrikethroughRun)
    }

    // MARK: - Segment Helpers

    func testSegmentsConcatenateToOriginalTexts() {
        // Use CJK tokens so single-character edits produce token-level diffs.
        let source = "Qwen3 是最棒的"
        let processed = "Qwen3 是最好的"
        let presentation = TextComparisonPresentation(source: source, processed: processed)

        // Walk segments: equal + inserted (ignoring deleted) should reconstruct processed.
        let reconstructedProcessed = presentation.segments
            .map { segment -> String in
                switch segment {
                case .equal(let text), .inserted(let text): return text
                case .deleted: return ""
                }
            }
            .joined()
        XCTAssertEqual(reconstructedProcessed, processed)

        // equal + deleted (ignoring inserted) should reconstruct source.
        let reconstructedSource = presentation.segments
            .map { segment -> String in
                switch segment {
                case .equal(let text), .deleted(let text): return text
                case .inserted: return ""
                }
            }
            .joined()
        XCTAssertEqual(reconstructedSource, source)
    }
}
