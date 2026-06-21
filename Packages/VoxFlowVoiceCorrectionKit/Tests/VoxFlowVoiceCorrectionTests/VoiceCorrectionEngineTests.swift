import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Voice correction engine")
struct VoiceCorrectionEngineTests {
    @Test("collects all matches from immutable raw text and never cascades")
    func doesNotCascadeReplacements() {
        let rules = [
            CorrectionRule(original: "A", replacement: "B", matchPolicy: .boundary),
            CorrectionRule(original: "B", replacement: "C", matchPolicy: .boundary),
        ]
        let context = CorrectionContext(
            mode: .dictation,
            providerID: "test",
            modelID: nil,
            language: "en",
            bundleIdentifier: "com.apple.TextEdit",
            isFinalTranscript: true,
            isSecureField: false
        )

        let result = VoiceCorrectionEngine().correct(
            rawText: "A B",
            context: context,
            snapshot: RuleSnapshot(version: 1, rules: rules)
        )

        #expect(result.correctedText == "B C")
        #expect(result.events.map(\.original) == ["A", "B"])
    }
}
