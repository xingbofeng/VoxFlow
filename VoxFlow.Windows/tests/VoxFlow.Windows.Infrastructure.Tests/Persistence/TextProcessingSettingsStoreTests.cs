using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class TextProcessingSettingsStoreTests
{
    [Fact]
    public async Task Missing_row_loads_defaults_and_saved_thresholds_round_trip_through_JSON()
    {
        using var fixture = new Fixture();
        Assert.Equal(
            DeterministicTextProcessingSettings.Default,
            await fixture.Store.LoadAsync(CancellationToken.None));
        var settings = DeterministicTextProcessingSettings.Default with
        {
            LongSentenceBreaking = true,
            LongSentenceWordThreshold = 17,
            LongSentenceCjkThreshold = 23,
            PunctuationWordThreshold = 6,
            PunctuationCjkThreshold = 5,
        };

        await fixture.Store.SaveAsync(settings, CancellationToken.None);

        Assert.Equal(settings, await fixture.Store.LoadAsync(CancellationToken.None));
        var row = fixture.Runner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT key, json_value FROM settings " +
                "WHERE key = 'text_processing.deterministic';";
            using var reader = command.ExecuteReader();
            Assert.True(reader.Read());
            return (reader.GetString(0), reader.GetString(1));
        });
        Assert.Equal("text_processing.deterministic", row.Item1);
        Assert.Contains("\"longSentenceWordThreshold\":17", row.Item2, StringComparison.Ordinal);
        Assert.DoesNotContain("apiKey", row.Item2, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Save_upserts_one_row_and_corrupt_or_invalid_payload_fails_closed()
    {
        using var fixture = new Fixture();
        await fixture.Store.SaveAsync(
            DeterministicTextProcessingSettings.Default,
            CancellationToken.None);
        await fixture.Store.SaveAsync(
            DeterministicTextProcessingSettings.Default with { Enabled = false },
            CancellationToken.None);
        Assert.False((await fixture.Store.LoadAsync(CancellationToken.None)).Enabled);
        Assert.Equal(1, fixture.CountRows());

        fixture.ReplaceJson("{\"enabled\":true,\"longSentenceWordThreshold\":0}");

        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await fixture.Store.LoadAsync(CancellationToken.None));
    }

    private sealed class Fixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();

        public Fixture()
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.db");
            new VoxFlowDatabaseMigrator().Migrate(databasePath);
            Runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(databasePath, pooling: false));
            Store = new SqliteTextProcessingSettingsStore(Runner);
        }

        public SqliteTransactionRunner Runner { get; }

        public SqliteTextProcessingSettingsStore Store { get; }

        public int CountRows() => Runner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT COUNT(*) FROM settings " +
                "WHERE key = 'text_processing.deterministic';";
            return Convert.ToInt32(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
        });

        public void ReplaceJson(string json) => Runner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE settings SET json_value = $json " +
                "WHERE key = 'text_processing.deterministic';";
            command.Parameters.AddWithValue("$json", json);
            command.ExecuteNonQuery();
            return 0;
        });

        public void Dispose()
        {
            Runner.Dispose();
            directory.Dispose();
        }
    }
}
