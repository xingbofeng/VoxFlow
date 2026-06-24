import Foundation

enum SelectionActionRoute: Equatable, Sendable {
    case textTransform(TextTransformOperation, text: String)
    case agentContext(text: String)
}

struct SelectionActionDispatcher: Sendable {
    func route(
        action: SelectionActionKind,
        selectedText: String
    ) -> SelectionActionRoute {
        switch action {
        case .translate:
            return .textTransform(.translation, text: selectedText)
        case .summarize:
            return .textTransform(.summary, text: selectedText)
        case .agent:
            return .agentContext(text: selectedText)
        }
    }
}
