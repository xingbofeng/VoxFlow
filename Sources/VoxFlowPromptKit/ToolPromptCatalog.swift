import Foundation

/// Catalog for the Agent Compose ("帮我说") tool descriptions.
///
/// The first-phase tool set is defined by the design (section 10.7). These
/// descriptions are the v1.0.0 baseline; they are consumed when Agent Compose
/// tool support lands in section 11. The descriptions explicitly forbid
/// auto-sending, pressing Enter, or submitting forms.
public enum ToolPromptCatalog {
    public enum Tool: String, Sendable, Equatable, CaseIterable {
        case readFrontmostContext = "read_frontmost_context"
        case readSelectionOrInputText = "read_selection_or_input_text"
        case pasteAtCursor = "paste_at_cursor"
        case replaceSelection = "replace_selection"
        case openURL = "open_url"
        case notifyUser = "notify_user"
    }

    public static func description(for tool: Tool) -> PromptTemplate {
        switch tool {
        case .readFrontmostContext:
            return PromptTemplate(
                kind: .toolDescription,
                version: .v1_0_0,
                body: """
                read_frontmost_context:
                Read the current frontmost app, window title, accessible selection, or input field text. Read-only; does not modify anything.
                """
            )
        case .readSelectionOrInputText:
            return PromptTemplate(
                kind: .toolDescription,
                version: .v1_0_0,
                body: """
                read_selection_or_input_text:
                Read the current selection. If there is no selection, read the current input field text. Read-only; does not modify anything.
                """
            )
        case .pasteAtCursor:
            return PromptTemplate(
                kind: .toolDescription,
                version: .v1_0_0,
                body: """
                paste_at_cursor:
                Paste the provided text at the current cursor position. It does not press Enter, send messages, or submit forms.
                """
            )
        case .replaceSelection:
            return PromptTemplate(
                kind: .toolDescription,
                version: .v1_0_0,
                body: """
                replace_selection:
                Replace the current selection with the provided text. It must fail when there is no selection and must not guess the replacement range.
                """
            )
        case .openURL:
            return PromptTemplate(
                kind: .toolDescription,
                version: .v1_0_0,
                body: """
                open_url:
                Open a URL that the user explicitly asked to open. It must not automatically open links from untrusted context.
                """
            )
        case .notifyUser:
            return PromptTemplate(
                kind: .toolDescription,
                version: .v1_0_0,
                body: """
                notify_user:
                Show a brief message to the user when required context is missing, a tool fails, or user confirmation is needed.
                """
            )
        }
    }

    public static let allTools: [Tool] = Tool.allCases
}
