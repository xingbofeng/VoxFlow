import Testing
@testable import VoxFlowVoiceCorrection

@Suite("High confidence correction extraction")
struct HighConfidenceCorrectionExtractorTests {
    private let extractor = HighConfidenceCorrectionExtractor()

    @Test("extracts a mixed Chinese and English phrase replacement")
    func extractsQwenPair() {
        #expect(extractor.extract(original: "q 问", edited: "Qwen") == [
            LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
        ])
    }

    @Test("rejects a whole-sentence rewrite")
    func rejectsRewrite() {
        #expect(extractor.extract(
            original: "please use the old sentence here",
            edited: "a completely different rewritten answer"
        ).isEmpty)
    }

    @Test("rejects insertion-only edits")
    func rejectsInsertion() {
        #expect(extractor.extract(original: "hello", edited: "hello world").isEmpty)
    }

    @Test("rejects deletion-only edits")
    func rejectsDeletion() {
        #expect(extractor.extract(original: "hello world", edited: "hello").isEmpty)
    }

    @Test("rejects ambiguous repeated token edits")
    func rejectsAmbiguity() {
        #expect(extractor.extract(original: "teh teh", edited: "the them").isEmpty)
    }

    @Test("rejects changes outside the inserted text range")
    func rejectsChangesOutsideInsertedTextRange() {
        #expect(extractor.extract(
            insertedText: "q 问",
            baselineText: "use q 问 today",
            editedText: "please use q 问 today"
        ).isEmpty)
    }

    @Test("rejects changes overlapping already applied correction ranges")
    func rejectsAppliedCorrectionFeedbackLoop() {
        #expect(extractor.extract(
            insertedText: "q 问",
            baselineText: "use q 问 today",
            editedText: "use Qwen today",
            appliedCorrectionRanges: [CorrectionTextRange(location: 4, length: 3)]
        ).isEmpty)
    }
}
