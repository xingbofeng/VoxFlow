using System.Text.RegularExpressions;
using VoxFlow.Windows.Application.History;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentTranscriptionSearchEntry(
    string Id,
    string RawText,
    string FinalText,
    string CreatedAt,
    string TargetAppName);

public sealed record AgentTranscriptionSearchResult(
    bool Ok,
    IReadOnlyList<AgentTranscriptionSearchEntry> Entries,
    string? ErrorCode);

/// <summary>Controlled local history access for the sidecar. It reads only
/// retained records through a parameterized repository method and redacts
/// credential-shaped values before returning them to the model.</summary>
public sealed class AgentTranscriptionSearchService
{
    private static readonly Regex Secret = new(
        @"(?i)(?:\bsk-[A-Za-z0-9_\-]{8,}|\bAKID[A-Za-z0-9]{8,}|\bBearer\s+)[A-Za-z0-9_\-.]+",
        RegexOptions.CultureInvariant,
        TimeSpan.FromMilliseconds(100));
    private readonly IHistoryStore history;

    public AgentTranscriptionSearchService(IHistoryStore history) =>
        this.history = history ?? throw new ArgumentNullException(nameof(history));

    public AgentTranscriptionSearchResult Search(
        string query,
        string? dateFrom,
        string? dateTo,
        int limit)
    {
        if (string.IsNullOrWhiteSpace(query)) return new(false, [], "missing_query");
        if (limit is < 1 or > 100) return new(false, [], "invalid_limit");
        if (!TryParseDate(dateFrom, out var from) || !TryParseDate(dateTo, out var to) || (from is not null && to is not null && from > to))
        {
            return new(false, [], "invalid_date_range");
        }
        try
        {
            var entries = history.Search(query.Trim(), from, to, limit)
                .Select(entry => new AgentTranscriptionSearchEntry(
                    entry.Id,
                    Redact(entry.RawText),
                    Redact(entry.FinalText),
                    entry.CreatedAtUtc.ToUniversalTime().ToString("O"),
                    entry.Source))
                .ToArray();
            return new(true, entries, null);
        }
        catch
        {
            return new(false, [], "transcription_search_failed");
        }
    }

    private static bool TryParseDate(string? input, out DateTimeOffset? date)
    {
        date = null;
        if (string.IsNullOrWhiteSpace(input)) return true;
        if (!DateTimeOffset.TryParse(input, System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out var parsed)) return false;
        date = parsed;
        return true;
    }

    private static string Redact(string text) => Secret.Replace(text, "[REDACTED]");
}
