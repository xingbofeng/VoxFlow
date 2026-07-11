using Microsoft.Data.Sqlite;
using System.Text.Json;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class HistoryRepositoryTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Default_policy_prunes_entries_older_than_thirty_days_after_a_write()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("expired", Now.AddDays(-30).AddMilliseconds(-1)));

        var result = fixture.Service.Record(
            CreateEntry("current", Now),
            HistoryRetentionPolicy.Default);

        Assert.True(result.WasWritten);
        Assert.Equal(1, result.PrunedCount);
        Assert.Equal(["current"], fixture.ReadIds());
    }

    [Fact]
    public void Entry_created_exactly_at_the_cutoff_boundary_is_retained()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("at-cutoff", Now.AddDays(-30)));

        var result = fixture.Service.CleanupOnStartup(HistoryRetentionPolicy.Default);

        Assert.False(result.WasWritten);
        Assert.Equal(0, result.PrunedCount);
        Assert.Equal(["at-cutoff"], fixture.ReadIds());
    }

    [Fact]
    public void Disabled_policy_does_not_write_or_erase_existing_history()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("existing", Now.AddDays(-365)));

        var cleanup = fixture.Service.CleanupOnStartup(HistoryRetentionPolicy.Disabled);
        var write = fixture.Service.Record(
            CreateEntry("must-not-be-written", Now),
            HistoryRetentionPolicy.Disabled);

        Assert.Equal(new HistoryMaintenanceResult(false, 0), cleanup);
        Assert.Equal(new HistoryMaintenanceResult(false, 0), write);
        Assert.Equal(["existing"], fixture.ReadIds());
    }

    [Fact]
    public void Forever_policy_writes_without_pruning_existing_history()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("very-old", Now.AddDays(-3650)));

        var result = fixture.Service.Record(
            CreateEntry("current", Now),
            HistoryRetentionPolicy.Forever);

        Assert.Equal(new HistoryMaintenanceResult(true, 0), result);
        Assert.Equal(["current", "very-old"], fixture.ReadIds());
    }

    [Fact]
    public void Startup_cleanup_prunes_only_expired_history_without_writing()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("expired", Now.AddDays(-31)));
        fixture.Seed(CreateEntry("recent", Now.AddDays(-1)));

        var result = fixture.Service.CleanupOnStartup(HistoryRetentionPolicy.Default);

        Assert.Equal(new HistoryMaintenanceResult(false, 1), result);
        Assert.Equal(["recent"], fixture.ReadIds());
    }

    [Fact]
    public void Write_and_prune_commit_as_one_atomic_operation()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("expired", Now.AddDays(-31)));

        var result = fixture.Store.WriteAndPrune(
            CreateEntry("current", Now),
            Now.AddDays(-30));

        Assert.Equal(new HistoryMaintenanceResult(true, 1), result);
        Assert.Equal(["current"], fixture.ReadIds());
    }

    [Fact]
    public void Write_and_prune_roll_back_together_when_pruning_fails()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("expired", Now.AddDays(-31)));
        fixture.CreateFailingDeleteTrigger();

        Assert.Throws<SqliteException>(() => fixture.Store.WriteAndPrune(
            CreateEntry("must-roll-back", Now),
            Now.AddDays(-30)));

        Assert.Equal(["expired"], fixture.ReadIds());
    }

    [Fact]
    public void History_entry_contract_contains_typed_metadata_but_no_raw_payload_escape_hatch()
    {
        var entryProperties = typeof(HistoryEntry).GetProperties();
        var metadataProperties = typeof(HistoryMetadata).GetProperties();

        Assert.Contains(entryProperties, property => property.Name == nameof(HistoryEntry.RawText));
        Assert.Contains(entryProperties, property => property.Name == nameof(HistoryEntry.FinalText));
        Assert.Contains(entryProperties, property => property.Name == nameof(HistoryEntry.Metadata));
        Assert.DoesNotContain(entryProperties, property =>
            property.Name.Contains("audio", StringComparison.OrdinalIgnoreCase)
            || property.Name.Contains("pcm", StringComparison.OrdinalIgnoreCase)
            || property.Name.Contains("wave", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(metadataProperties, property =>
            property.PropertyType == typeof(string)
            || property.PropertyType == typeof(byte[])
            || property.PropertyType == typeof(ReadOnlyMemory<byte>));
    }

    [Fact]
    public void History_metadata_rejects_unknown_raw_audio_fields()
    {
        const string maliciousMetadata =
            "{\"recovered\":false,\"rawAudio\":\"base64-payload\"}";

        Assert.Throws<JsonException>(() =>
            JsonSerializer.Deserialize<HistoryMetadata>(
                maliciousMetadata,
                DomainJson.Options));
    }

    [Fact]
    public void Typed_processing_metadata_round_trips_without_a_free_form_payload()
    {
        using var fixture = new HistoryFixture(Now);
        var metadata = new HistoryMetadata(
            recovered: true,
            capturedFrameCount: 120,
            droppedFrameCount: 3,
            durationMilliseconds: 840,
            errorCode: VoxFlowErrorCode.NetworkFailure,
            asrProvider: AsrProviderId.Qwen,
            qwenVariant: QwenVariant.Qwen06B,
            recognitionLanguage: RecognitionLanguage.ChineseMandarin,
            llmProvider: LlmProviderId.OpenAI,
            llmDurationMilliseconds: 75);
        var entry = CreateEntry("typed-metadata", Now) with { Metadata = metadata };

        fixture.Seed(entry);

        Assert.Equal(metadata, fixture.Store.ReadAll().Single().Metadata);
    }

    [Fact]
    public void Update_final_text_is_parameterized_and_changes_only_the_requested_record()
    {
        using var fixture = new HistoryFixture(Now);
        const string adversarialId = "entry'); DROP TABLE dictation_history; --";
        const string editedText = "It's still safe; DELETE FROM dictation_history; --";
        fixture.Seed(CreateEntry(adversarialId, Now));
        fixture.Seed(CreateEntry("untouched", Now.AddMinutes(-1)));

        Assert.True(fixture.Store.UpdateFinalText(adversarialId, editedText));
        Assert.False(fixture.Store.UpdateFinalText("missing", "unused"));

        var entries = fixture.Store.ReadAll();
        Assert.Equal(2, entries.Count);
        Assert.Equal(
            editedText,
            entries.Single(entry => entry.Id == adversarialId).FinalText);
        Assert.Equal(
            "final-untouched",
            entries.Single(entry => entry.Id == "untouched").FinalText);
    }

    [Fact]
    public void Batch_delete_is_atomic_and_parameterized()
    {
        using var fixture = new HistoryFixture(Now);
        const string adversarialId = "delete-me'); SELECT RAISE(ABORT); --";
        fixture.Seed(CreateEntry(adversarialId, Now));
        fixture.Seed(CreateEntry("also-delete", Now.AddMinutes(-1)));
        fixture.Seed(CreateEntry("keep", Now.AddMinutes(-2)));

        Assert.Equal(
            2,
            fixture.Store.Delete([adversarialId, "also-delete", adversarialId]));

        Assert.Equal(["keep"], fixture.ReadIds());
    }

    [Fact]
    public void Batch_delete_rolls_back_all_rows_when_a_trigger_rejects_one()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("ordinary", Now));
        fixture.Seed(CreateEntry("protected", Now.AddMinutes(-1)));
        fixture.CreateProtectedDeleteTrigger();

        Assert.Throws<SqliteException>(() =>
            fixture.Store.Delete(["ordinary", "protected"]));

        Assert.Equal(["ordinary", "protected"], fixture.ReadIds());
    }

    [Fact]
    public void Clear_returns_the_deleted_count_and_leaves_the_store_reusable()
    {
        using var fixture = new HistoryFixture(Now);
        fixture.Seed(CreateEntry("first", Now));
        fixture.Seed(CreateEntry("second", Now.AddMinutes(-1)));

        Assert.Equal(2, fixture.Store.Clear());
        Assert.Equal(0, fixture.Store.Clear());

        fixture.Seed(CreateEntry("after-clear", Now));
        Assert.Equal(["after-clear"], fixture.ReadIds());
    }

    private static HistoryEntry CreateEntry(string id, DateTimeOffset createdAtUtc) =>
        new(
            id,
            "qwen-0.6b",
            $"raw-{id}",
            $"final-{id}",
            new HistoryMetadata(
                recovered: false,
                capturedFrameCount: 42,
                droppedFrameCount: 0,
                durationMilliseconds: 125,
                errorCode: null),
            createdAtUtc);

    private sealed class HistoryFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly SqliteTransactionRunner runner;

        public HistoryFixture(DateTimeOffset now)
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.db");
            new VoxFlowDatabaseMigrator().Migrate(databasePath);
            runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(databasePath, pooling: false));
            Store = new SqliteHistoryStore(runner);
            Service = new HistoryRetentionService(
                Store,
                new ControlledTimeProvider(now));
        }

        public SqliteHistoryStore Store { get; }

        public HistoryRetentionService Service { get; }

        public void Seed(HistoryEntry entry) => Store.WriteAndPrune(entry, null);

        public string[] ReadIds() => [.. Store.ReadAll().Select(entry => entry.Id)];

        public void CreateFailingDeleteTrigger()
        {
            runner.Write((connection, transaction) =>
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText =
                    "CREATE TRIGGER fail_history_prune " +
                    "BEFORE DELETE ON dictation_history " +
                    "BEGIN SELECT RAISE(ABORT, 'forced prune failure'); END;";
                command.ExecuteNonQuery();
                return 0;
            });
        }

        public void CreateProtectedDeleteTrigger()
        {
            runner.Write((connection, transaction) =>
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText =
                    "CREATE TRIGGER protect_one_history_row " +
                    "BEFORE DELETE ON dictation_history " +
                    "WHEN OLD.id = 'protected' " +
                    "BEGIN SELECT RAISE(ABORT, 'protected history row'); END;";
                command.ExecuteNonQuery();
                return 0;
            });
        }

        public void Dispose()
        {
            runner.Dispose();
            directory.Dispose();
        }
    }
}
