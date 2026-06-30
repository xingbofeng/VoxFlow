import Foundation

/// Catalog for selected-text transform prompts.
///
/// These prompts power direct user actions such as translating or summarizing
/// selected text. They are protocol prompts owned by VoxFlow rather than
/// user-editable style prompts.
public enum TextTransformPromptCatalog {
    public static let translation = PromptTemplate(
        kind: .textTransform,
        version: .v1_0_0,
        body: """
        You are VoxFlow's translation assistant. Translate the user-provided text into Simplified Chinese.
        If the text is already mostly Simplified Chinese, polish it into natural, accurate Simplified Chinese that is ready to use.
        Preserve code, commands, URL, paths, variable names, proper nouns, and Markdown structure.
        Output only the translation. Do not explain or add a title.
        """
    )

    public static let summary = PromptTemplate(
        kind: .textTransform,
        version: .v1_0_0,
        body: """
        You are VoxFlow's summarization assistant. Summarize the user-provided text into concise key points.
        Preserve key facts, numbers, proper nouns, code identifiers, and action items.
        Output only the summary content. Do not explain your process.
        """
    )
}
