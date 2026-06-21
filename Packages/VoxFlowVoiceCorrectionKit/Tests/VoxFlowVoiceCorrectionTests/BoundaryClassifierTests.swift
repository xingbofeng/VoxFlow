import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Boundary classification")
struct BoundaryClassifierTests {
    private let classifier = BoundaryClassifier()

    @Test("accepts a standalone English word and rejects a compound word")
    func englishWordBoundary() {
        #expect(isBoundaryMatch(pattern: "teh", in: "fix teh now"))
        #expect(!isBoundaryMatch(pattern: "teh", in: "other"))
    }

    @Test("treats digits as word constituents")
    func numberBoundary() {
        #expect(isBoundaryMatch(pattern: "v2", in: "use v2."))
        #expect(!isBoundaryMatch(pattern: "v2", in: "use v20"))
    }

    @Test("does not match a short CJK term inside a longer CJK word")
    func cjkBoundary() {
        #expect(isBoundaryMatch(pattern: "问", in: "问。"))
        #expect(!isBoundaryMatch(pattern: "问", in: "请问"))
    }

    @Test("allows punctuation and emoji tokens")
    func punctuationAndEmojiBoundary() {
        #expect(isBoundaryMatch(pattern: "¿", in: "¿Como estas?"))
        #expect(isBoundaryMatch(pattern: "🙂", in: "hello🙂world"))
    }

    @Test("classifies boundaries independently from letter casing")
    func casingDoesNotChangeBoundary() {
        #expect(isBoundaryMatch(pattern: "QWEN", in: "use QWEN now"))
        #expect(!isBoundaryMatch(pattern: "QWEN", in: "use XQWEN2 now"))
    }

    private func isBoundaryMatch(pattern: String, in text: String) -> Bool {
        guard let range = text.range(of: pattern) else {
            return false
        }
        return classifier.isBoundaryMatch(in: text, range: range)
    }
}
