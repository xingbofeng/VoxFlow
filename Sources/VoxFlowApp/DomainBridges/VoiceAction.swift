import Foundation
import VoxFlowDomain

typealias VoiceAction = VoxFlowDomain.VoiceAction

extension VoiceAction {
    var displayName: String {
        switch self {
        case .agentCompose: return L10n.localize("menu.voice_action.agent_compose", comment: "")
        case .agentDispatch: return L10n.localize("menu.voice_action.agent_dispatch", comment: "")
        case .dictation: return L10n.localize("menu.voice_action.dictation", comment: "")
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
