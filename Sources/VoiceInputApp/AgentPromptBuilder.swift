import Foundation

// MARK: - AgentPromptBuilder

struct AgentPromptBuilder {
    static let agentSystemPrompt = """
        You are a context-aware writing assistant. The user will dictate their intent and you \
        will generate polished, usable text based on that intent and the provided context.

        Rules:
        1. Execute the user's dictation intent faithfully. Do not add content the user did not \
        ask for.
        2. Never fabricate facts, dates, names, or data. If context is insufficient, use \
        conservative and general expressions.
        3. Output ONLY the final usable text — no explanations, no notes, no quotation marks, \
        no markdown fences.
        4. Preserve the user's original language (Chinese/English) unless the dictation intent \
        clearly asks for translation.
        5. When the user dictates code-related content (commands, variables, paths, API names, \
        technical terms), preserve them exactly — do not translate or paraphrase English \
        technical terminology into Chinese.
        6. Match the tone and register implied by the context (formal email, casual chat, \
        technical documentation, etc.).
        """

    func build(
        appName: String?,
        stylePrompt: String?,
        context: ContextSnapshot?,
        userDictation: String
    ) -> TextRefinementRequest {
        var sections = [Self.agentSystemPrompt]

        // App context
        if let appName {
            sections.append("Target application: \(appName)")
        }

        // Style guidance
        if let stylePrompt {
            sections.append(
                """
                Style guidance:
                \(stylePrompt)
                """
            )
        }

        // Window context
        if let context {
            var contextParts: [String] = []

            if let windowTitle = context.windowTitle {
                contextParts.append("Window title: \(windowTitle)")
            }
            if let targetAppName = context.targetAppName {
                contextParts.append("Application: \(targetAppName)")
            }
            if let visibleText = context.visibleText {
                contextParts.append("Visible text in window:\n\(visibleText)")
            }
            if let selectedText = context.selectedText {
                contextParts.append("Selected text:\n\(selectedText)")
            }
            if let inputAreaText = context.inputAreaText {
                contextParts.append("Current input area:\n\(inputAreaText)")
            }

            if !contextParts.isEmpty {
                sections.append(
                    """
                    Context (use as reference, do not fabricate from it):
                    \(contextParts.joined(separator: "\n\n"))
                    """
                )
            }
        }

        // User dictation
        sections.append(
            """
            User's dictation intent:
            \(userDictation)
            """
        )

        let systemPrompt = sections.joined(separator: "\n\n")

        return TextRefinementRequest(
            text: userDictation,
            systemPrompt: systemPrompt,
            model: nil,
            temperature: 0.7
        )
    }
}
