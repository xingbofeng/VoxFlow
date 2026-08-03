using System.Text.RegularExpressions;

namespace VoxFlow.Windows.Application.Text;

public sealed record GlossaryHotword(
    Guid Id,
    string Term,
    string? Note = null,
    int Weight = 5)
{
    public GlossaryHotword Normalize() => this with
    {
        Term = Term.Trim(),
        Note = string.IsNullOrWhiteSpace(Note) ? null : Note.Trim(),
        Weight = Math.Clamp(Weight, 1, 10),
    };
}

public sealed record TextReplacementRule(
    Guid Id,
    string Source,
    string Target,
    bool Enabled = true,
    bool MatchWholeWord = false)
{
    public TextReplacementRule Normalize() => this with
    {
        Source = Source.Trim(),
        Target = Target.Trim(),
    };
}

public sealed record GlossaryDocument(
    IReadOnlyList<GlossaryHotword> Hotwords,
    IReadOnlyList<TextReplacementRule> Replacements,
    IReadOnlyList<string> IgnoredSuggestions,
    int SchemaVersion = 1)
{
    public const int CurrentSchemaVersion = 1;

    public static GlossaryDocument Default { get; } = new(
        [],
        [],
        [],
        CurrentSchemaVersion);

    public GlossaryDocument Normalize()
    {
        var hotwords = Hotwords
            .Select(item => item.Normalize())
            .Where(item => item.Term.Length > 0)
            .GroupBy(item => item.Term, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToArray();
        var replacements = Replacements
            .Select(item => item.Normalize())
            .Where(item => item.Source.Length > 0)
            .GroupBy(item => item.Source, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToArray();
        var ignored = IgnoredSuggestions
            .Select(value => value.Trim())
            .Where(value => value.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return this with
        {
            Hotwords = hotwords,
            Replacements = replacements,
            IgnoredSuggestions = ignored,
            SchemaVersion = CurrentSchemaVersion,
        };
    }
}

public interface IGlossaryStore
{
    ValueTask<GlossaryDocument> LoadAsync(CancellationToken cancellationToken);

    ValueTask SaveAsync(
        GlossaryDocument document,
        CancellationToken cancellationToken);
}

public static class GlossaryTextProcessor
{
    public static string Apply(string text, GlossaryDocument document)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(document);
        var result = text;
        foreach (var rule in document.Replacements
            .Where(rule => rule.Enabled && !string.IsNullOrWhiteSpace(rule.Source))
            .OrderByDescending(rule => rule.Source.Length))
        {
            result = rule.MatchWholeWord
                ? Regex.Replace(
                    result,
                    $@"(?<![\p{{L}}\p{{N}}_]){Regex.Escape(rule.Source)}(?![\p{{L}}\p{{N}}_])",
                    _ => rule.Target,
                    RegexOptions.CultureInvariant)
                : result.Replace(rule.Source, rule.Target, StringComparison.Ordinal);
        }

        return result;
    }
}
