import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Correction context gate")
struct ContextGateTests {
    private let gate = ContextGate()

    @Test("allows an active rule for a final dictation transcript")
    func allowsFinalDictation() {
        #expect(gate.allows(rule: makeRule(), context: makeContext()))
    }

    @Test(arguments: [CorrectionInputMode.command, .translation])
    func rejectsUnsupportedModes(mode: CorrectionInputMode) {
        #expect(!gate.allows(rule: makeRule(), context: makeContext(mode: mode)))
    }

    @Test("rejects interim transcripts")
    func rejectsInterim() {
        #expect(!gate.allows(rule: makeRule(), context: makeContext(isFinalTranscript: false)))
    }

    @Test("rejects secure fields")
    func rejectsSecureField() {
        #expect(!gate.allows(rule: makeRule(), context: makeContext(isSecureField: true)))
    }

    @Test("allows an application rule only for its bundle identifier")
    func applicationScope() {
        let rule = makeRule(scope: .application(bundleIdentifier: "com.apple.TextEdit"))

        #expect(gate.allows(rule: rule, context: makeContext(bundleIdentifier: "com.apple.TextEdit")))
        #expect(!gate.allows(rule: rule, context: makeContext(bundleIdentifier: "com.apple.Notes")))
    }

    @Test(arguments: [RuleLifecycle.candidate, .suspended, .retired])
    func rejectsInactiveLifecycles(lifecycle: RuleLifecycle) {
        #expect(!gate.allows(rule: makeRule(lifecycle: lifecycle), context: makeContext()))
    }

    @Test("engine returns raw text with no events when the gate rejects")
    func engineFailsOpen() {
        let result = VoiceCorrectionEngine().correct(
            rawText: "teh",
            context: makeContext(mode: .command),
            snapshot: RuleSnapshot(version: 1, rules: [makeRule()])
        )

        #expect(result.correctedText == "teh")
        #expect(result.events.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    private func makeRule(
        scope: RuleScope = .global,
        lifecycle: RuleLifecycle = .active
    ) -> CorrectionRule {
        CorrectionRule(
            original: "teh",
            replacement: "the",
            matchPolicy: .boundary,
            scope: scope,
            lifecycle: lifecycle
        )
    }

    private func makeContext(
        mode: CorrectionInputMode = .dictation,
        bundleIdentifier: String? = "com.apple.TextEdit",
        isFinalTranscript: Bool = true,
        isSecureField: Bool = false
    ) -> CorrectionContext {
        CorrectionContext(
            mode: mode,
            providerID: "test",
            modelID: nil,
            language: "en",
            bundleIdentifier: bundleIdentifier,
            isFinalTranscript: isFinalTranscript,
            isSecureField: isSecureField
        )
    }
}
