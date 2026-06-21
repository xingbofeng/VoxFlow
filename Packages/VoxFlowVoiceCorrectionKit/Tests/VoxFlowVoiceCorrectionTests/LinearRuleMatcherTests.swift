import Foundation
import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Linear rule matcher")
struct LinearRuleMatcherTests {
    private let matcher = LinearRuleMatcher()

    @Test("exact matching replaces only the trimmed full transcript")
    func exactMatch() {
        let matches = matcher.matches(
            in: "  teh  ",
            rules: [makeRule(original: "teh", policy: .exact)]
        )

        #expect(matches.map(\.range) == [CorrectionTextRange(location: 2, length: 3)])
    }

    @Test("boundary matching skips occurrences inside compound words")
    func boundaryMatch() {
        let matches = matcher.matches(
            in: "teh tehology TEH",
            rules: [makeRule(original: "teh", policy: .boundary)]
        )

        #expect(matches.map(\.range) == [
            CorrectionTextRange(location: 0, length: 3),
            CorrectionTextRange(location: 13, length: 3),
        ])
    }

    @Test("substring matching can match inside a larger token")
    func substringMatch() {
        let matches = matcher.matches(
            in: "hyperframe",
            rules: [makeRule(original: "frame", policy: .substring)]
        )

        #expect(matches.map(\.range) == [CorrectionTextRange(location: 5, length: 5)])
    }

    @Test("manual rules are case insensitive by default")
    func caseInsensitiveByDefault() {
        let matches = matcher.matches(
            in: "QWEN qwen",
            rules: [makeRule(original: "Qwen", policy: .boundary)]
        )

        #expect(matches.count == 2)
    }

    @Test("case sensitive manual rules preserve casing")
    func caseSensitiveRule() {
        let matches = matcher.matches(
            in: "qwen Qwen",
            rules: [makeRule(original: "Qwen", policy: .boundary, caseSensitive: true)]
        )

        #expect(matches.map(\.range) == [CorrectionTextRange(location: 5, length: 4)])
    }

    @Test("matching skips text that already equals the replacement")
    func skipsNoOpReplacement() {
        let matches = matcher.matches(
            in: "Claude already has the expected capitalization",
            rules: [makeRule(original: "claude", replacement: "Claude", policy: .boundary)]
        )

        #expect(matches.isEmpty)
    }

    private func makeRule(
        original: String,
        replacement: String = "corrected",
        policy: MatchPolicy,
        caseSensitive: Bool = false
    ) -> CorrectionRule {
        CorrectionRule(
            original: original,
            replacement: replacement,
            matchPolicy: policy,
            source: .manual,
            caseSensitive: caseSensitive
        )
    }
}
