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
        case .listening: return "正在听你说"
        case let .exact(agentName, _): return "准备发送给\(agentName)"
        case .confirmation: return "选择要指挥的队员"
        case .fallbackInput: return "写入当前输入框"
        case .clipboardFallback: return "已复制到剪切板"
        case let .sent(agentName): return "已发送给\(agentName)"
        case .failure: return "发送失败"
        }
    }

    var detail: String {
        switch self {
        case .idle, .sent: return ""
        case let .listening(agentNames): return agentNames.joined(separator: " · ")
        case let .exact(_, message): return message
        case let .confirmation(utterance, _): return utterance
        case let .fallbackInput(text): return text
        case let .clipboardFallback(text): return text
        case let .failure(message, retainedText):
            return retainedText.isEmpty ? message : "\(message)\n指令已保留：\(retainedText)"
        }
    }

    var badge: String? {
        if case .exact = self { return "100% 直接发送" }
        return nil
    }
}
