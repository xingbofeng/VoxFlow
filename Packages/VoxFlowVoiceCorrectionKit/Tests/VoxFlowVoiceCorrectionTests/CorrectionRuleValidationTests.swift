import Foundation
import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Correction rule validation")
struct CorrectionRuleValidationTests {
    @Test("rejects an empty original")
    func rejectsEmptyOriginal() {
        let rule = makeRule(original: "   ")

        #expect(throws: CorrectionRuleValidationError.emptyOriginal) {
            try rule.validate()
        }
    }

    @Test("rejects a replacement identical to the original")
    func rejectsSelfReplacement() {
        let rule = makeRule(original: "Qwen", replacement: "Qwen")

        #expect(throws: CorrectionRuleValidationError.identicalReplacement) {
            try rule.validate()
        }
    }

    @Test("rejects an original longer than the supported limit")
    func rejectsOverlongOriginal() {
        let rule = makeRule(
            original: String(repeating: "a", count: CorrectionRule.maximumTextLength + 1)
        )

        #expect(throws: CorrectionRuleValidationError.originalTooLong) {
            try rule.validate()
        }
    }

    @Test("rejects substring matching for an automatically learned rule")
    func rejectsLearnedSubstringRule() {
        let rule = makeRule(matchPolicy: .substring, source: .automaticLearning)

        #expect(throws: CorrectionRuleValidationError.automaticLearningRequiresBoundary) {
            try rule.validate()
        }
    }

    @Test("rejects a single CJK character learned automatically")
    func rejectsSingleCJKLearnedRule() {
        let rule = makeRule(original: "问", source: .automaticLearning)

        #expect(throws: CorrectionRuleValidationError.automaticLearningSingleCJK) {
            try rule.validate()
        }
    }

    @Test("core models satisfy Sendable boundaries")
    func modelsAreSendable() {
        requireSendable(makeRule())
        requireSendable(
            CorrectionContext(
                mode: .dictation,
                providerID: "apple-speech",
                modelID: nil,
                language: "zh-CN",
                bundleIdentifier: "com.apple.TextEdit",
                isFinalTranscript: true,
                isSecureField: false
            )
        )
        requireSendable(RuleSnapshot(version: 1, rules: [makeRule()]))
    }

    @Test("target identifier survives Codable round trip")
    func targetIDSurvivesCodableRoundTrip() throws {
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        var rule = makeRule()
        rule.targetID = targetID

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(CorrectionRule.self, from: data)

        #expect(decoded.targetID == targetID)
    }

    @Test("legacy JSON without target identifier remains decodable")
    func legacyJSONWithoutTargetIDRemainsDecodable() throws {
        let data = try JSONEncoder().encode(makeRule())
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("targetID") == false)

        let decoded = try JSONDecoder().decode(CorrectionRule.self, from: data)

        #expect(decoded.targetID == nil)
        #expect(decoded.original == "q 问")
    }

    private func makeRule(
        original: String = "q 问",
        replacement: String = "Qwen",
        matchPolicy: MatchPolicy = .boundary,
        source: RuleSource = .manual
    ) -> CorrectionRule {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return CorrectionRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            original: original,
            replacement: replacement,
            matchPolicy: matchPolicy,
            scope: .global,
            lifecycle: .active,
            source: source,
            confidence: 1,
            isEnabled: true,
            createdAt: now,
            updatedAt: now,
            lastAppliedAt: nil
        )
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
