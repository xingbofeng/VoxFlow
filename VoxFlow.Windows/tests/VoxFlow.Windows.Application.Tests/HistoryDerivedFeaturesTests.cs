using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Application.Tests;

public sealed class HistoryDerivedFeaturesTests
{
    [Fact]
    public async Task History_reprocessor_uses_the_live_dictation_post_processor()
    {
        var processor = new CapturingProcessor();
        var reprocessor = new DictationHistoryReprocessor(processor);

        var result = await reprocessor.ReprocessAsync(" raw ", CancellationToken.None);

        Assert.Equal("processed: raw ", result);
        Assert.Equal(" raw ", processor.Input);
    }

    [Fact]
    public void Glossary_suggestions_come_from_edits_and_repeated_real_history()
    {
        var source = new HistoryGlossarySuggestionSource(new MemoryHistoryStore(
        [
            Entry("1", "Q win native", "QwenNative runtime"),
            Entry("2", "use VoxFlow", "use VoxFlow"),
            Entry("3", "test VoxFlow", "test VoxFlow"),
            Entry("4", "ordinary sentence", "ordinary sentence"),
        ]));

        var suggestions = source.ReadSuggestions();

        Assert.Contains("QwenNative", suggestions);
        Assert.Contains("VoxFlow", suggestions);
        Assert.DoesNotContain("ordinary", suggestions);
    }

    private static HistoryEntry Entry(string id, string raw, string final) => new(
        id,
        "dictation",
        raw,
        final,
        new HistoryMetadata(),
        DateTimeOffset.Parse("2026-07-16T00:00:00Z"));

    private sealed class CapturingProcessor : IDictationTextPostProcessor
    {
        public string? Input { get; private set; }

        public ValueTask<string> ProcessAsync(
            string text,
            IProgress<string> streamingProgress,
            CancellationToken cancellationToken)
        {
            Input = text;
            return ValueTask.FromResult("processed:" + text);
        }
    }

    private sealed class MemoryHistoryStore(IReadOnlyList<HistoryEntry> entries) : IHistoryStore
    {
        public IReadOnlyList<HistoryEntry> ReadAll() => entries;
        public HistoryMaintenanceResult WriteAndPrune(HistoryEntry entry, DateTimeOffset? before) =>
            throw new NotSupportedException();
        public int PruneBefore(DateTimeOffset before) => throw new NotSupportedException();
        public int Delete(IReadOnlyCollection<string> ids) => throw new NotSupportedException();
        public int Clear() => throw new NotSupportedException();
        public bool UpdateFinalText(string id, string finalText) => throw new NotSupportedException();
    }
}
