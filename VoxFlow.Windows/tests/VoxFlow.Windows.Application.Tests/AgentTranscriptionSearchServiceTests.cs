using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.History;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentTranscriptionSearchServiceTests
{
    [Fact]
    public void Search_applies_dates_limit_and_redacts_credential_shaped_text()
    {
        var history = new CapturingHistoryStore(
        [
            Entry("old", "needle sk-private-secret", "Bearer very-secret", "2026-01-01T00:00:00Z"),
            Entry("new", "needle", "final", "2026-02-01T00:00:00Z"),
        ]);
        var service = new AgentTranscriptionSearchService(history);

        var result = service.Search("needle", "2026-01-15", "2026-03-01", 1);

        Assert.True(result.Ok);
        var entry = Assert.Single(result.Entries);
        Assert.Equal("new", entry.Id);
        Assert.Equal(1, history.Limit);
        Assert.Equal("needle", history.Query);
    }

    [Fact]
    public void Search_rejects_invalid_dates_and_limits_before_reading_history()
    {
        var history = new CapturingHistoryStore([]);
        var service = new AgentTranscriptionSearchService(history);

        Assert.Equal("invalid_date_range", service.Search("a", "not-a-date", null, 1).ErrorCode);
        Assert.Equal("invalid_limit", service.Search("a", null, null, 101).ErrorCode);
        Assert.Equal("missing_query", service.Search(" ", null, null, 1).ErrorCode);
        Assert.False(history.WasSearched);
    }

    [Fact]
    public void Search_redacts_returned_content_without_dropping_the_matching_entry()
    {
        var history = new CapturingHistoryStore([Entry("one", "needle sk-private-secret", "Bearer very-secret", "2026-01-01T00:00:00Z")]);
        var result = new AgentTranscriptionSearchService(history).Search("needle", null, null, 5);

        var entry = Assert.Single(result.Entries);
        Assert.Contains("[REDACTED]", entry.RawText, StringComparison.Ordinal);
        Assert.Contains("[REDACTED]", entry.FinalText, StringComparison.Ordinal);
        Assert.DoesNotContain("private-secret", entry.RawText, StringComparison.Ordinal);
        Assert.DoesNotContain("very-secret", entry.FinalText, StringComparison.Ordinal);
    }

    private static HistoryEntry Entry(string id, string raw, string final, string createdAt) => new(
        id, "notepad.exe", raw, final, new HistoryMetadata(), DateTimeOffset.Parse(createdAt));

    private sealed class CapturingHistoryStore(IReadOnlyList<HistoryEntry> entries) : IHistoryStore
    {
        public bool WasSearched { get; private set; }
        public string? Query { get; private set; }
        public int Limit { get; private set; }
        public HistoryMaintenanceResult WriteAndPrune(HistoryEntry entry, DateTimeOffset? deleteBeforeUtcExclusive) => throw new NotSupportedException();
        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) => throw new NotSupportedException();
        public IReadOnlyList<HistoryEntry> ReadAll() => entries;
        public int Delete(IReadOnlyCollection<string> ids) => throw new NotSupportedException();
        public int Clear() => throw new NotSupportedException();
        public bool UpdateFinalText(string id, string finalText) => throw new NotSupportedException();
        public IReadOnlyList<HistoryEntry> Search(string query, DateTimeOffset? dateFromUtc, DateTimeOffset? dateToUtc, int limit)
        {
            WasSearched = true;
            Query = query;
            Limit = limit;
            return entries.Where(entry => entry.RawText.Contains(query, StringComparison.OrdinalIgnoreCase)
                    && (dateFromUtc is null || entry.CreatedAtUtc >= dateFromUtc)
                    && (dateToUtc is null || entry.CreatedAtUtc <= dateToUtc))
                .Take(limit).ToArray();
        }
    }
}
