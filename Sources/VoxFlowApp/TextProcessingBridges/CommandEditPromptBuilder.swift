import Foundation
import VoxFlowPromptKit

/// Builds the refinement request for voice commands: the spoken instruction is
/// the only command the model obeys, and the snapshot of the focused input
/// area is the content it edits.
struct CommandEditPromptBuilder {
    private static let renderer = PromptRenderer()

    func build(instruction: String, text: String) -> TextRefinementRequest {
        let render = Self.renderer.render(
            CommandEditPromptCatalog.base,
            context: PromptRenderContext.make(("instruction", instruction))
        )
        let systemPrompt = render.renderedText
        return TextRefinementRequest(
            text: text,
            systemPrompt: systemPrompt,
            // Model and temperature follow the configured provider, like every
            // other purpose except agent compose.
            model: nil,
            temperature: nil,
            purpose: .commandEdit,
            promptMetadata: PromptTraceMetadata(
                promptKind: CommandEditPromptCatalog.base.kind,
                promptVersion: CommandEditPromptCatalog.base.version,
                renderedPromptHash: PromptRenderer.hash(renderedPrompt: systemPrompt),
                styleID: nil,
                routerVersion: nil,
                agentPromptVersion: nil
            )
        )
    }
}
