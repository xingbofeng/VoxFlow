import Foundation

enum AgentDispatchHUDPresentation: Equatable {
    case idle
    case listening(agentNames: [String])
    case exact(agentName: String, message: String)
    case confirmation(utterance: String, candidates: [AgentSessionCard])
    case fallbackInput(text: String)
    case clipboardFallback(text: String)
    case sent(agentName: String)
    case failure(message: String, retainedText: String)

    var title: String {
        switch self {
        case .idle: return ""
        case .listening: return L10n.localize("hud.title.listening", comment: "")
        case let .exact(agentName, _): return String(format: L10n.localize("hud.title.exact", comment: ""), agentName)
        case .confirmation: return L10n.localize("hud.title.confirmation", comment: "")
        case .fallbackInput: return L10n.localize("hud.title.fallback_input", comment: "")
        case .clipboardFallback: return L10n.localize("hud.title.clipboard_fallback", comment: "")
        case let .sent(agentName): return String(format: L10n.localize("hud.title.sent", comment: ""), agentName)
        case .failure: return L10n.localize("hud.title.failure", comment: "")
        }
    }

    var detail: String {
        switch self {
        case .idle, .sent: return ""
        case let .listening(agentNames): return String(
            format: L10n.localize("hud.detail.listening_agents", comment: ""),
            agentNames.joined(separator: " · ")
        )
        case let .exact(_, message): return message
        case let .confirmation(utterance, _): return utterance
        case let .fallbackInput(text): return text
        case let .clipboardFallback(text): return text
        case let .failure(message, retainedText):
            return retainedText.isEmpty
                ? message
                : String(
                    format: L10n.localize("hud.detail.failure_with_retained", comment: ""),
                    message,
                    retainedText
                )
        }
    }

    var badge: String? {
        if case .exact = self { return L10n.localize("hud.badge.exact_send", comment: "") }
        return nil
    }
}
