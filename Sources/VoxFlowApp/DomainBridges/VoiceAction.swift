import VoxFlowDomain

typealias VoiceAction = VoxFlowDomain.VoiceAction

extension VoiceAction {
    var displayName: String {
        switch self {
        case .dictation: return "听写"
        case .agentCompose: return "帮我说"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: return "waveform"
        case .agentCompose: return "sparkles.rectangle.stack"
        }
    }
}
