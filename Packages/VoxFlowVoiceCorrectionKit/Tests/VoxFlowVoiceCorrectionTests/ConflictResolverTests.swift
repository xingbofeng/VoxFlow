import Foundation
import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Correction conflict resolution")
struct ConflictResolverTests {
    private let resolver = ConflictResolver()

    @Test("prefers a longer match")
    func longerMatchWins() {
        let short = makeMatch(location: 0, length: 3, original: "abc")
        let long = makeMatch(location: 0, length: 5, original: "abcde")

        #expect(resolver.resolve([short, long]) == [long])
    }

    @Test("prefers application scope over global scope")
    func applicationScopeWins() {
        let global = makeMatch(location: 0, length: 3, scope: .global)
        let app = makeMatch(
            location: 0,
            length: 3,
            scope: .application(bundleIdentifier: "com.apple.TextEdit")
        )

        #expect(resolver.resolve([global, app]) == [app])
    }

    @Test("prefers a manual rule over an automatically learned rule")
    func manualSourceWins() {
        let learned = makeMatch(location: 0, length: 3, source: .automaticLearning)
        let manual = makeMatch(location: 0, length: 3, source: .manual)

        #expect(resolver.resolve([learned, manual]) == [manual])
    }

    @Test("prefers the higher confidence rule")
    func confidenceWins() {
        let low = makeMatch(location: 0, length: 3, confidence: 0.4)
        let high = makeMatch(location: 0, length: 3, confidence: 0.9)

        #expect(resolver.resolve([low, high]) == [high])
    }

    @Test("prefers the left-most match when priorities are equal")
    func leftMostWins() {
        let left = makeMatch(location: 0, length: 3)
        let right = makeMatch(location: 2, length: 3)

        #expect(resolver.resolve([right, left]) == [left])
    }

    @Test("removes a fully contained lower-priority match")
    func fullContainment() {
        let outer = makeMatch(location: 1, length: 6, original: "abcdef")
        let inner = makeMatch(location: 2, length: 3, original: "bcd")

        #expect(resolver.resolve([inner, outer]) == [outer])
    }

    @Test("keeps stable winners for partial overlaps and preserves non-overlaps")
    func partialOverlap() {
        let left = makeMatch(location: 0, length: 4)
        let overlapping = makeMatch(location: 3, length: 4)
        let separate = makeMatch(location: 8, length: 2)

        #expect(resolver.resolve([overlapping, separate, left]) == [left, separate])
    }

    private func makeMatch(
        location: Int,
        length: Int,
        original: String = "abc",
        scope: RuleScope = .global,
        source: RuleSource = .manual,
        confidence: Double = 1
    ) -> CorrectionMatch {
        let rule = CorrectionRule(
            id: UUID(),
            original: original,
            replacement: "fixed",
            matchPolicy: .boundary,
            scope: scope,
            source: source,
            confidence: confidence
        )
        return CorrectionMatch(
            rule: rule,
            range: CorrectionTextRange(location: location, length: length),
            matchedText: original
        )
    }
}
