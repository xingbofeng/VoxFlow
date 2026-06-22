import Foundation
import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Correction target terms")
struct CorrectionTargetTermTests {
    @Test("normalizes target text for case-insensitive grouping")
    func normalizesTargetText() throws {
        let target = CorrectionTargetTerm(text: " Qwen ")

        #expect(target.text == "Qwen")
        #expect(target.normalizedText == "qwen")
        #expect(target.lifecycle == .active)
        #expect(target.source == .manual)
    }

    @Test("rejects an empty target")
    func rejectsEmptyTarget() {
        let target = CorrectionTargetTerm(text: "   ")

        #expect(throws: CorrectionTargetTermValidationError.emptyText) {
            try target.validate()
        }
    }

    @Test("rejects a target longer than a correction rule text")
    func rejectsTooLongTarget() {
        let target = CorrectionTargetTerm(
            text: String(repeating: "a", count: CorrectionRule.maximumTextLength + 1)
        )

        #expect(throws: CorrectionTargetTermValidationError.textTooLong) {
            try target.validate()
        }
    }
}
