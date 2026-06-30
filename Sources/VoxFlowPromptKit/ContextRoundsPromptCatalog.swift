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
}
