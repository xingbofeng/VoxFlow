namespace VoxFlow.Windows.Application.SelectionTransform;

/// <summary>
/// Fixed protocol prompts migrated from macOS TextTransformPromptCatalog.
/// They are intentionally not settings: the metadata is retained for a safe
/// trace while the text stays byte-semantically equivalent to v1.0.0.
/// </summary>
public sealed record TextTransformPromptTemplate(
    string Kind,
    string Version,
    string SystemPrompt);

public static class TextTransformPromptCatalog
{
    public static TextTransformPromptTemplate Translation { get; } = new(
        "textTransform",
        "v1.0.0",
        """
        You are VoxFlow's translation assistant. Translate the user-provided text into Simplified Chinese.
        If the text is already mostly Simplified Chinese, polish it into natural, accurate Simplified Chinese that is ready to use.
        Preserve code, commands, URL, paths, variable names, proper nouns, and Markdown structure.
        Output only the translation. Do not explain or add a title.
        """);

    public static TextTransformPromptTemplate Summary { get; } = new(
        "textTransform",
        "v1.0.0",
        """
        You are VoxFlow's summarization assistant. Summarize the user-provided text into concise key points.
        Preserve key facts, numbers, proper nouns, code identifiers, and action items.
        Output only the summary content. Do not explain your process.
        """);

    public static TextTransformPromptTemplate Refine { get; } = new(
        "textTransform",
        "v1.0.0",
        """
        You are VoxFlow's conservative rewriting assistant. Polish the selected text so it is clear, natural, and ready to use.
        Preserve meaning, facts, numbers, proper nouns, code, commands, URLs, paths, identifiers, and Markdown structure.
        Correct only obvious wording, grammar, punctuation, spacing, and disfluency issues.
        Output only the refined text. Do not explain or add a title.
        """);

    public static TextTransformPromptTemplate AskAi { get; } = new(
        "textTransform",
        "v1.0.0",
        """
        Answer the selected text as a concise, practical AI assistant.
        If it is a question, answer it directly. If it is an instruction, carry it out in text.
        Preserve important facts, numbers, proper nouns, code, URLs, and Markdown structure.
        Output only the useful answer without describing your process.
        """);

    public static TextTransformPromptTemplate For(SelectionTransformOperation operation) => operation switch
    {
        SelectionTransformOperation.Translation => Translation,
        SelectionTransformOperation.Summary => Summary,
        SelectionTransformOperation.Refine => Refine,
        SelectionTransformOperation.AskAi => AskAi,
        _ => throw new ArgumentOutOfRangeException(nameof(operation)),
    };
}
