public struct VoiceCorrectionEngine: Sendable {
    private let matcher: LinearRuleMatcher
    private let contextGate: ContextGate
    private let conflictResolver: ConflictResolver
    private let replacementApplier: ReplacementApplier

    public init(
        matcher: LinearRuleMatcher = LinearRuleMatcher(),
        contextGate: ContextGate = ContextGate(),
        conflictResolver: ConflictResolver = ConflictResolver(),
        replacementApplier: ReplacementApplier = ReplacementApplier()
    ) {
        self.matcher = matcher
        self.contextGate = contextGate
        self.conflictResolver = conflictResolver
        self.replacementApplier = replacementApplier
    }

    public func correct(
        rawText: String,
        context: CorrectionContext,
        snapshot: RuleSnapshot
    ) -> CorrectionResult {
        let allowedRules = snapshot.rules.filter {
            contextGate.allows(rule: $0, context: context)
        }
        let matches = matcher.matches(in: rawText, rules: allowedRules)
        let resolvedMatches = conflictResolver.resolve(matches)
        return replacementApplier.apply(rawText: rawText, matches: resolvedMatches)
    }
}
