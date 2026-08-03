using System.Text.RegularExpressions;
using VoxFlow.Windows.Application.History;

namespace VoxFlow.Windows.Application.Text;

public interface IGlossarySuggestionSource
{
    IReadOnlyList<string> ReadSuggestions(int limit = 30);
}

/// <summary>
/// Derives vocabulary candidates from actual retained dictation usage. Terms
/// introduced by an edit are strongest; repeated technical/proper-name tokens
/// are also eligible, matching the macOS history-learning semantics.
/// </summary>
public sealed partial class HistoryGlossarySuggestionSource : IGlossarySuggestionSource
{
    private readonly IHistoryStore history;

    public HistoryGlossarySuggestionSource(IHistoryStore history)
    {
        this.history = history ?? throw new ArgumentNullException(nameof(history));
    }

    public IReadOnlyList<string> ReadSuggestions(int limit = 30)
    {
        if (limit is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(limit));
        }

        var scores = new Dictionary<string, Candidate>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in history.ReadAll().Take(500))
        {
            var raw = Tokenize(entry.RawText).ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var term in Tokenize(entry.FinalText))
            {
                var introducedByEdit = !raw.Contains(term);
                if (!scores.TryGetValue(term, out var candidate))
                {
                    candidate = new Candidate(term, 0, 0);
                }

                scores[term] = candidate with
                {
                    Occurrences = candidate.Occurrences + 1,
                    EditIntroductions = candidate.EditIntroductions + (introducedByEdit ? 1 : 0),
                };
            }
        }

        return scores.Values
            .Where(candidate => candidate.EditIntroductions > 0 || candidate.Occurrences >= 2)
            .OrderByDescending(candidate => candidate.EditIntroductions)
            .ThenByDescending(candidate => candidate.Occurrences)
            .ThenBy(candidate => candidate.Term, StringComparer.CurrentCultureIgnoreCase)
            .Take(limit)
            .Select(candidate => candidate.Term)
            .ToArray();
    }

    private static IEnumerable<string> Tokenize(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            yield break;
        }

        foreach (Match match in CandidateTokenRegex().Matches(text))
        {
            var term = match.Value.Trim();
            if (IsReasonable(term))
            {
                yield return term;
            }
        }
    }

    private static bool IsReasonable(string term)
    {
        if (term.Length is < 2 or > 50)
        {
            return false;
        }

        return !StopWords.Contains(term);
    }

    private static readonly HashSet<string> StopWords = new(
        [
            "this", "that", "with", "from", "have", "will", "the", "and",
            "这个", "那个", "就是", "然后", "其实", "我们", "你们", "他们",
            "删除", "保存", "发送", "取消", "确认", "复制",
        ],
        StringComparer.OrdinalIgnoreCase);

    [GeneratedRegex(@"[A-Za-z][A-Za-z0-9_+#.\-/]{1,49}|[\p{IsCJKUnifiedIdeographs}]{2,12}")]
    private static partial Regex CandidateTokenRegex();

    private sealed record Candidate(
        string Term,
        int Occurrences,
        int EditIntroductions);
}
