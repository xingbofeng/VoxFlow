public struct ContextGate: Sendable {
    public init() {}

    public func allows(
        rule: CorrectionRule,
        context: CorrectionContext
    ) -> Bool {
        guard context.mode == .dictation,
              context.isFinalTranscript,
              !context.isSecureField,
              rule.isEnabled,
              rule.lifecycle == .active,
              rule.allowedModes.contains(context.mode),
              scopeMatches(rule.scope, bundleIdentifier: context.bundleIdentifier),
              optionalConstraint(rule.providerID, matches: context.providerID),
              optionalConstraint(rule.modelID, matches: context.modelID),
              optionalConstraint(rule.language, matches: context.language)
        else {
            return false
        }
        return true
    }

    private func scopeMatches(
        _ scope: RuleScope,
        bundleIdentifier: String?
    ) -> Bool {
        switch scope {
        case .global:
            return true
        case .application(let requiredBundleIdentifier):
            return bundleIdentifier == requiredBundleIdentifier
        }
    }

    private func optionalConstraint(
        _ required: String?,
        matches actual: String?
    ) -> Bool {
        guard let required else {
            return true
        }
        return required.caseInsensitiveCompare(actual ?? "") == .orderedSame
    }
}
