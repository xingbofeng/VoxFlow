using System.Text;
using System.Text.RegularExpressions;

namespace VoxFlow.Windows.Application.Text;

public enum MarkdownPreviewBlockKind
{
    Paragraph,
    Heading1,
    Heading2,
    Heading3,
    Bullet,
    Code,
}

public sealed record MarkdownPreviewBlock(
    MarkdownPreviewBlockKind Kind,
    string Text);

/// <summary>
/// Lightweight Markdown structure preview used by writing-style editors.
/// Renders headings, emphasis, lists, and fenced code — not a full CommonMark engine.
/// </summary>
public static class MarkdownPreviewModel
{
    private static readonly Regex Heading = new(
        @"^(#{1,3})\s+(.*)$",
        RegexOptions.Compiled);
    private static readonly Regex Bullet = new(
        @"^\s*[-*+]\s+(.*)$",
        RegexOptions.Compiled);
    private static readonly Regex Emphasis = new(
        @"(\*\*|__)(.+?)\1|(\*|_)(.+?)\3",
        RegexOptions.Compiled);

    public static string SubstituteContent(string template, string sampleContent)
    {
        ArgumentNullException.ThrowIfNull(template);
        ArgumentNullException.ThrowIfNull(sampleContent);
        return template.Replace("{{content}}", sampleContent, StringComparison.Ordinal);
    }

    public static IReadOnlyList<MarkdownPreviewBlock> Parse(
        string markdown,
        string sampleContent = "Sample dictated text.")
    {
        ArgumentNullException.ThrowIfNull(markdown);
        var source = SubstituteContent(markdown, sampleContent);
        if (string.IsNullOrWhiteSpace(source))
        {
            return [];
        }

        List<MarkdownPreviewBlock> blocks = [];
        var lines = source.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        var inCode = false;
        var code = new StringBuilder();
        foreach (var rawLine in lines)
        {
            var line = rawLine;
            if (line.TrimStart().StartsWith("```", StringComparison.Ordinal))
            {
                if (inCode)
                {
                    blocks.Add(new MarkdownPreviewBlock(
                        MarkdownPreviewBlockKind.Code,
                        code.ToString().TrimEnd()));
                    code.Clear();
                    inCode = false;
                }
                else
                {
                    inCode = true;
                }

                continue;
            }

            if (inCode)
            {
                if (code.Length > 0)
                {
                    code.Append('\n');
                }

                code.Append(line);
                continue;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var heading = Heading.Match(line);
            if (heading.Success)
            {
                var level = heading.Groups[1].Value.Length;
                var kind = level switch
                {
                    1 => MarkdownPreviewBlockKind.Heading1,
                    2 => MarkdownPreviewBlockKind.Heading2,
                    _ => MarkdownPreviewBlockKind.Heading3,
                };
                blocks.Add(new MarkdownPreviewBlock(kind, StripEmphasis(heading.Groups[2].Value)));
                continue;
            }

            var bullet = Bullet.Match(line);
            if (bullet.Success)
            {
                blocks.Add(new MarkdownPreviewBlock(
                    MarkdownPreviewBlockKind.Bullet,
                    StripEmphasis(bullet.Groups[1].Value)));
                continue;
            }

            blocks.Add(new MarkdownPreviewBlock(
                MarkdownPreviewBlockKind.Paragraph,
                StripEmphasis(line)));
        }

        if (inCode && code.Length > 0)
        {
            blocks.Add(new MarkdownPreviewBlock(
                MarkdownPreviewBlockKind.Code,
                code.ToString().TrimEnd()));
        }

        return blocks;
    }

    /// <summary>
    /// Human-readable multi-line preview with structure markers (for plain TextBlock binding).
    /// </summary>
    public static string RenderStructuredText(
        string markdown,
        string sampleContent = "Sample dictated text.")
    {
        var blocks = Parse(markdown, sampleContent);
        if (blocks.Count == 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder();
        foreach (var block in blocks)
        {
            if (builder.Length > 0)
            {
                builder.AppendLine();
            }

            builder.Append(block.Kind switch
            {
                MarkdownPreviewBlockKind.Heading1 => block.Text.ToUpperInvariant(),
                MarkdownPreviewBlockKind.Heading2 => block.Text,
                MarkdownPreviewBlockKind.Heading3 => block.Text,
                MarkdownPreviewBlockKind.Bullet => "• " + block.Text,
                MarkdownPreviewBlockKind.Code => block.Text,
                _ => block.Text,
            });
            if (block.Kind is MarkdownPreviewBlockKind.Heading1
                or MarkdownPreviewBlockKind.Heading2
                or MarkdownPreviewBlockKind.Heading3)
            {
                builder.AppendLine();
            }
        }

        return builder.ToString().TrimEnd();
    }

    public static bool HasRenderableStructure(string markdown)
    {
        var blocks = Parse(markdown ?? string.Empty);
        return blocks.Any(block => block.Kind is not MarkdownPreviewBlockKind.Paragraph)
            || (markdown?.Contains("{{content}}", StringComparison.Ordinal) ?? false)
            || (markdown?.Contains("**", StringComparison.Ordinal) ?? false);
    }

    private static string StripEmphasis(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return string.Empty;
        }

        return Emphasis.Replace(text, static match =>
            match.Groups[2].Success ? match.Groups[2].Value : match.Groups[4].Value);
    }
}
