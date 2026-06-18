public enum VoiceTaskRecoveryAction: String, Codable, Equatable, Sendable {
    case copy
    case reoutput
    case regenerate
    case retranscribe
    case delete
}

public enum VoiceTaskRecoveryPolicy {
    public static func availableActions(
        mode: VoiceTaskMode?,
        status: VoiceTaskStatus?,
        hasFinalText: Bool,
        hasRawTranscript: Bool,
        outputResultKind: OutputResultKind?
    ) -> [VoiceTaskRecoveryAction] {
        var actions: [VoiceTaskRecoveryAction] = []

        if hasFinalText || hasRawTranscript {
            actions.append(.copy)
        }

        if mode == .dictation,
           status == .completed || status == .partiallyCompleted,
           hasFinalText,
           canReoutput(outputResultKind) {
            actions.append(.reoutput)
        }

        if mode == .agentCompose, hasRawTranscript {
            actions.append(.regenerate)
        }

        if status == .failed {
            actions.append(.retranscribe)
        }

        actions.append(.delete)
        return actions
    }

    private static func canReoutput(_ kind: OutputResultKind?) -> Bool {
        guard let kind else {
            return true
        }
        switch kind {
        case .inserted, .copied, .targetChanged, .permissionDenied:
            return true
        case .failed, .cancelled:
            return false
        }
    }
}
