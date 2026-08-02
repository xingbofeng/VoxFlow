namespace VoxFlow.Windows.Application.Screenshot;

public sealed record ScreenshotTransformPromptTemplate(
    string Kind,
    string Version,
    string SystemPrompt,
    int MaxOutputTokens);

public static class ScreenshotTransformPromptCatalog
{
    public static ScreenshotTransformPromptTemplate Refinement { get; } = new(
        "screenshotTextRefinement",
        "v1.0.0",
        """
        You are VoxFlow's conservative screenshot OCR editor. Correct only obvious OCR recognition, punctuation, spacing, and line-break errors in the user-provided text.
        Preserve the original meaning, facts, numbers, names, code, commands, URLs, paths, identifiers, Markdown, and paragraph structure.
        Do not add, infer, summarize, translate, answer, explain, or remove information that is present in the source.
        Output only the corrected text.
        """,
        4096);

    public static ScreenshotTransformPromptTemplate Translation { get; } = new(
        "screenshotTranslation",
        "v1.0.0",
        """
        You are VoxFlow's screenshot translation assistant. Translate the user-provided OCR text into natural, accurate Simplified Chinese.
        If the text is already mostly Simplified Chinese, conservatively polish it without changing meaning.
        Preserve facts, numbers, code, commands, URLs, paths, identifiers, proper nouns, Markdown, and paragraph structure.
        Output only the translation. Do not explain or add a title.
        """,
        4096);

    public static ScreenshotTransformPromptTemplate Summary { get; } = new(
        "screenshotSummary",
        "v1.0.0",
        """
        You are VoxFlow's screenshot summarization assistant. Summarize the user-provided OCR text as at most three short bullet points.
        Preserve key facts, numbers, proper nouns, code identifiers, and action items. Do not add or infer facts not present in the source.
        Output only the bullet points. Do not explain your process or add a title.
        """,
        1024);

    public static ScreenshotTransformPromptTemplate For(
        ScreenshotTransformOperation operation) => operation switch
    {
        ScreenshotTransformOperation.Refinement => Refinement,
        ScreenshotTransformOperation.Translation => Translation,
        ScreenshotTransformOperation.Summary => Summary,
        _ => throw new ArgumentOutOfRangeException(nameof(operation)),
    };
}
