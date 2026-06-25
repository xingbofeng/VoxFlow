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

    @Test("extracts a short Chinese hallucination to a Latin product name")
    func extractsShortChinesePhraseToLatinName() {
        #expect(extractor.extract(original: "偷看案子。", edited: "tokenhub") == [
            LearnedCorrectionPair(original: "偷看案子", replacement: "tokenhub"),
        ])
    }

    @Test("extracts repeated short Chinese phrase to repeated Latin token")
    func extractsRepeatedShortChinesePhraseToRepeatedLatinToken() {
        #expect(extractor.extract(original: "偷看，偷看。", edited: "token token") == [
            LearnedCorrectionPair(original: "偷看", replacement: "token"),
        ])
    }

    @Test("rejects a whole-sentence rewrite")
    func rejectsRewrite() {
        #expect(extractor.extract(
            original: "please use the old sentence here",
            edited: "a completely different rewritten answer"
        ).isEmpty)
    }

    @Test("rejects an unsegmented Chinese sentence rewrite")
    func rejectsChineseSentenceRewrite() {
        #expect(extractor.extract(
            original: "这个方案不好",
            edited: "我想换一个完整说法"
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

    @Test("extracts terminal command edits before shell output is appended")
    func extractsTerminalCommandEditBeforeShellOutput() {
        #expect(extractor.extract(
            insertedText: "偷看",
            baselineText: "➜ 偷看",
            editedText: "➜ token\nfish: Unknown command: token\n➜ "
        ) == [
            LearnedCorrectionPair(original: "偷看", replacement: "token"),
        ])
    }

    @Test("extracts terminal edits from full AX text buffer")
    func extractsTerminalEditsFromFullAXTextBuffer() {
        let baselineText = """
        counter repo $ token
        fish: Unknown command: token
        counter repo $
        counter repo $ 偷看
        """
        let editedText = """
        counter repo $ token
        fish: Unknown command: token
        counter repo $
        counter repo $ token
        """

        #expect(extractor.extract(
            insertedText: "偷看",
            baselineText: baselineText,
            editedText: editedText
        ) == [
            LearnedCorrectionPair(original: "偷看", replacement: "token"),
        ])
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
