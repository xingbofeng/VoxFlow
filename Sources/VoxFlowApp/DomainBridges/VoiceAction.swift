import VoxFlowDomain

typealias VoiceAction = VoxFlowDomain.VoiceAction

extension VoiceAction {
    var displayName: String {
        switch self {
        case .dictation: return "听写"
        case .agentCompose: return "任务助手"
        case .agentDispatch: return "AI 编程"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: return "waveform"
        case .agentCompose: return "sparkles.rectangle.stack"
        case .agentDispatch: return "terminal"
        }
    }
}
