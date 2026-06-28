import Foundation

enum SelectionActionKind: String, CaseIterable, Equatable, Sendable {
    case translate
    case summarize
    case agent
    case askAI

    var title: String {
        switch self {
        case .translate:
            return L10n.localize("selection.action.translate", comment: "")
        case .summarize:
            return L10n.localize("selection.action.summarize", comment: "")
        case .agent:
            return L10n.localize("selection.action.agent_compose", comment: "")
        case .askAI:
            return L10n.localize("selection.action.ask_ai", comment: "")
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
