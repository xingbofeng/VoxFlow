import Foundation
import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Correction replacement application")
struct ReplacementApplierTests {
    private let applier = ReplacementApplier()

    @Test("applies replacements from the end when lengths change")
    func appliesFromEnd() {
        let raw = "teh qwen"
        let first = makeMatch(raw: raw, original: "teh", replacement: "the")
        let second = makeMatch(raw: raw, original: "qwen", replacement: "Qwen 3 ASR")

        let result = applier.apply(rawText: raw, matches: [first, second])

        #expect(result.correctedText == "the Qwen 3 ASR")
        #expect(result.events.count == 2)
    }

    @Test("uses UTF-16 ranges for Unicode text")
    func unicodeRange() {
        let raw = "🙂 teh café"
        let match = makeMatch(raw: raw, original: "teh", replacement: "the")

        let result = applier.apply(rawText: raw, matches: [match])

        #expect(result.correctedText == "🙂 the café")
        #expect(result.events.first?.range == CorrectionTextRange(location: 3, length: 3))
    }

    @Test("allows a manual rule to remove matched text")
    func emptyReplacement() {
        let raw = "¿Como estas?"
        let match = makeMatch(raw: raw, original: "¿", replacement: "")

        let result = applier.apply(rawText: raw, matches: [match])

        #expect(result.correctedText == "Como estas?")
    }

    @Test("records event metadata against the corrected span")
    func recordsEvent() throws {
        let raw = "use q 问 now"
        let match = makeMatch(
            raw: raw,
            original: "q 问",
            replacement: "Qwen",
            scope: .application(bundleIdentifier: "com.apple.TextEdit"),
            source: .automaticLearning
        )

        let result = applier.apply(rawText: raw, matches: [match])
        let event = try #require(result.events.first)

        #expect(event.ruleID == match.rule.id)
        #expect(event.original == "q 问")
        #expect(event.replacement == "Qwen")
        #expect(event.range == CorrectionTextRange(location: 4, length: 4))
        #expect(event.scope == match.rule.scope)
        #expect(event.source == .automaticLearning)
    }

    private func makeMatch(
        raw: String,
        original: String,
        replacement: String,
        scope: RuleScope = .global,
        source: RuleSource = .manual
    ) -> CorrectionMatch {
        let stringRange = raw.range(of: original)!
        let range = NSRange(stringRange, in: raw)
        let rule = CorrectionRule(
            original: original,
            replacement: replacement,
            matchPolicy: .boundary,
            scope: scope,
            source: source
        )
        return CorrectionMatch(
            rule: rule,
            range: CorrectionTextRange(location: range.location, length: range.length),
            matchedText: original
        )
    }
}
