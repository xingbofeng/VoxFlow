import Foundation

/// Catalog for the AI style router system prompt.
///
/// The router is a single small classification request: given app context and
/// a transcript (or just app metadata for the current runtime classifier), it
/// must output a single candidate id or an empty/fallback value. The template
/// exposes a `{{candidates}}` placeholder for the rendered candidate list.
public enum StyleRouterPromptCatalog {
    /// v1.0.0 preserves the exact wording previously inlined in
    /// `LLMApplicationStyleClassifier`. Migration MUST NOT change behavior.
    public static let system = PromptTemplate(
        kind: .styleRouter,
        version: .v1_0_0,
        body: """
        Choose the best voice input style for the current app from the candidate styles.
        Output exactly one candidate style ID and no explanation. If uncertain, output an empty string.
        Candidate styles:
        {{candidates}}
        """
    )
}
