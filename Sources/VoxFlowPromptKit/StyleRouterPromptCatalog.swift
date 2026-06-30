import Foundation

/// Catalog for the AI style router system prompt.
///
/// The router is a single small classification request: given app context and
/// a transcript (or just app metadata for the current runtime classifier), it
/// must output a single candidate number or `fallback`. The template
/// exposes a `{{candidates}}` placeholder for the rendered candidate list.
public enum StyleRouterPromptCatalog {
    public static let system = PromptTemplate(
        kind: .styleRouter,
        version: .v1_0_0,
        body: """
        Choose the best VoxFlow voice input style for the current transcript.

        Rules:
        1. Use the transcript as the primary signal. App name, bundle ID, and window title are secondary context only.
        2. Choose only from the numbered candidate descriptions below.
        3. If the transcript is too short, generic, unrelated to any candidate, or uncertain, output fallback.
        4. Output exactly one token: a candidate number (1..N) or fallback.
        5. Do not output a style ID, style name, explanation, punctuation, JSON, or any extra text.

        Candidate styles:
        {{candidates}}
        """
    )
}
