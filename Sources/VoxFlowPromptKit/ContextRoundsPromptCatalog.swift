import Foundation

/// Prompt wrapper for same-app dictation context rounds.
///
/// The wrapper is model-facing and intentionally English. Runtime text inside
/// the wrapper may contain user language from previous transcripts.
public enum ContextRoundsPromptCatalog {
    public static let wrapper = PromptTemplate(
        kind: .contextRounds,
        version: .v1_0_0,
        body: """
        Previous context, do not repeat:
        {{previousContext}}

        Current ASR text:
        {{currentInput}}
        """
    )

    /// Wrapper for the target input box's current content (cursor context).
    /// Kept separate from the history wrapper so the LLM treats "what the
    /// user is editing right now" differently from "what the user said
    /// before". Injected only when the input-context toggle is on and the
    /// field is not secure.
    public static let inputContextWrapper = PromptTemplate(
        kind: .contextRounds,
        version: .v1_0_0,
        body: """
        Existing input text, the ASR text may reference or edit it:
        {{inputContext}}

        Current ASR text:
        {{currentInput}}
        """
    )
}
