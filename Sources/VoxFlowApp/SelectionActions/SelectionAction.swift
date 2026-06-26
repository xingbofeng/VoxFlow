import Foundation

enum SelectionActionKind: String, CaseIterable, Equatable, Sendable {
    case translate
    case summarize
    case agent
    case askAI

    var title: String {
        switch self {
        case .translate:
            return "翻译"
        case .summarize:
            return "总结"
        case .agent:
            return "任务助手"
        case .askAI:
            return "问 AI"
        }
    }
}

struct SelectionActionCardPresentation: Equatable, Sendable {
    let selectedText: String
    let actions: [SelectionActionKind]

    init(
        selectedText: String,
        actions: [SelectionActionKind] = [.translate, .summarize, .agent, .askAI]
    ) {
        self.selectedText = selectedText
        self.actions = actions
    }
}
