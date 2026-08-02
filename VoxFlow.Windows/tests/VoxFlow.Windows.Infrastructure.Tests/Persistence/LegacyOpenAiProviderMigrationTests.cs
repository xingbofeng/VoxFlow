using System.Text.Json;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class LegacyOpenAiProviderMigrationTests
{
    private const string LegacySecret = "legacy fixture key";

    [Fact]
    public async Task Complete_legacy_metadata_and_key_are_migrated_without_losing_values()
    {
        using var fixture = new MigrationDatabase();
        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.LegacyApiKey,
            LegacySecret);

        var result = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(LegacyOpenAiProviderMigrationStatus.Completed, result.Status);
        var provider = Assert.IsType<LlmProviderRecord>(fixture.Repository.Get("openai"));
        Assert.Equal(new Uri("https://legacy.example/v1"), provider.BaseUri);
        Assert.Equal("legacy-model", provider.DefaultModel);
        Assert.True(provider.Enabled);
        Assert.True(provider.IsDefault);
        Assert.Equal(
            LegacyOpenAiProviderMigration.CanonicalApiKeyReference,
            provider.ApiKeyRef);
        Assert.Equal(
            LegacySecret,
            await fixture.Credentials.ReadSecretAsync(
                LegacyOpenAiProviderMigration.ProviderApiKey));
        Assert.Equal(
            LegacySecret,
            await fixture.Credentials.ReadSecretAsync(
                LegacyOpenAiProviderMigration.LegacyApiKey));

        var stateJson = Assert.IsType<string>(fixture.ReadMigrationStateJson());
        using var state = JsonDocument.Parse(stateJson);
        Assert.Equal("completed", state.RootElement.GetProperty("status").GetString());
        var backup = state.RootElement.GetProperty("backup");
        Assert.Equal("legacy-model", backup.GetProperty("model").GetString());
        Assert.True(backup.GetProperty("enabled").GetBoolean());
        Assert.DoesNotContain(LegacySecret, stateJson, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Missing_legacy_key_keeps_provider_unconfigured_and_retryable()
    {
        using var fixture = new MigrationDatabase();

        var first = await fixture.Migration.RunAsync(CancellationToken.None);
        var second = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(LegacyOpenAiProviderMigrationStatus.CredentialMissing, first.Status);
        Assert.Equal(LegacyOpenAiProviderMigrationStatus.CredentialMissing, second.Status);
        var provider = Assert.IsType<LlmProviderRecord>(fixture.Repository.Get("openai"));
        Assert.Null(provider.ApiKeyRef);
        Assert.Null(await fixture.Credentials.ReadSecretAsync(
            LegacyOpenAiProviderMigration.ProviderApiKey));
        Assert.Equal(0, fixture.Credentials.SaveCount);
        var stateJson = Assert.IsType<string>(fixture.ReadMigrationStateJson());
        using var state = JsonDocument.Parse(stateJson);
        Assert.Equal(
            "credentialMissing",
            state.RootElement.GetProperty("status").GetString());
        Assert.False(state.RootElement.TryGetProperty("completedAtUnixMs", out _));
    }

    [Fact]
    public async Task Half_migration_after_verification_failure_resumes_without_overwriting_keys()
    {
        using var fixture = new MigrationDatabase();
        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.LegacyApiKey,
            LegacySecret);
        fixture.Credentials.FailNextProviderReadAfterSave = true;

        var failed = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(
            LegacyOpenAiProviderMigrationStatus.CredentialVerificationFailed,
            failed.Status);
        Assert.Equal(
            "llm/openai/api_key",
            fixture.Repository.Get("openai")?.ApiKeyRef);
        Assert.Equal(LegacySecret, fixture.Credentials.Peek(
            LegacyOpenAiProviderMigration.LegacyApiKey));
        Assert.Equal(LegacySecret, fixture.Credentials.Peek(
            LegacyOpenAiProviderMigration.ProviderApiKey));
        Assert.NotEqual("completed", fixture.ReadMigrationStatus());

        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.ProviderApiKey,
            "partially migrated key");
        var resumed = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(LegacyOpenAiProviderMigrationStatus.Completed, resumed.Status);
        Assert.Equal(1, fixture.Credentials.SaveCount);
        Assert.Equal(
            "partially migrated key",
            await fixture.Credentials.ReadSecretAsync(
                LegacyOpenAiProviderMigration.ProviderApiKey));
        Assert.Equal(LegacySecret, await fixture.Credentials.ReadSecretAsync(
            LegacyOpenAiProviderMigration.LegacyApiKey));
        Assert.Equal("completed", fixture.ReadMigrationStatus());
    }

    [Fact]
    public async Task Already_completed_migration_is_a_no_op()
    {
        using var fixture = new MigrationDatabase();
        fixture.SetProviderCredentialReference(
            LegacyOpenAiProviderMigration.CanonicalApiKeyReference,
            updatedAtUnixMs: 800);
        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.ProviderApiKey,
            "already migrated key");
        fixture.WriteMigrationState(
            """
            {
              "schemaVersion": 1,
              "status": "completed",
              "backup": {
                "providerId": "openai",
                "baseUrl": "https://legacy.example/v1",
                "model": "legacy-model",
                "enabled": true,
                "updatedAtUnixMs": 100,
                "legacyApiKeyRef": "llm/openai/api_key"
              },
              "completedAtUnixMs": 900
            }
            """,
            updatedAtUnixMs: 900);

        var result = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(
            LegacyOpenAiProviderMigrationStatus.AlreadyCompleted,
            result.Status);
        Assert.Equal(0, fixture.Credentials.SaveCount);
        Assert.Equal("legacy-model", fixture.Repository.Get("openai")?.DefaultModel);
        Assert.Equal(
            "already migrated key",
            await fixture.Credentials.ReadSecretAsync(
                LegacyOpenAiProviderMigration.ProviderApiKey));
    }

    [Fact]
    public async Task Completed_migration_never_overwrites_later_user_edits()
    {
        using var fixture = new MigrationDatabase();
        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.LegacyApiKey,
            LegacySecret);
        Assert.Equal(
            LegacyOpenAiProviderMigrationStatus.Completed,
            (await fixture.Migration.RunAsync(CancellationToken.None)).Status);

        fixture.UpdateProviderAsUser();
        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.ProviderApiKey,
            "user replacement key");
        var saveCount = fixture.Credentials.SaveCount;

        var result = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(
            LegacyOpenAiProviderMigrationStatus.AlreadyCompleted,
            result.Status);
        var provider = Assert.IsType<LlmProviderRecord>(fixture.Repository.Get("openai"));
        Assert.Equal(new Uri("https://user.example/v1"), provider.BaseUri);
        Assert.Equal("user-model", provider.DefaultModel);
        Assert.False(provider.Enabled);
        Assert.False(provider.IsDefault);
        Assert.Equal(saveCount, fixture.Credentials.SaveCount);
        Assert.Equal(
            "user replacement key",
            await fixture.Credentials.ReadSecretAsync(
                LegacyOpenAiProviderMigration.ProviderApiKey));
    }

    [Fact]
    public async Task Repeated_startups_create_one_provider_one_marker_and_copy_once()
    {
        using var fixture = new MigrationDatabase();
        fixture.Credentials.Seed(
            LegacyOpenAiProviderMigration.LegacyApiKey,
            LegacySecret);

        var first = await fixture.Migration.RunAsync(CancellationToken.None);
        var second = await fixture.Migration.RunAsync(CancellationToken.None);
        var third = await fixture.Migration.RunAsync(CancellationToken.None);

        Assert.Equal(LegacyOpenAiProviderMigrationStatus.Completed, first.Status);
        Assert.Equal(LegacyOpenAiProviderMigrationStatus.AlreadyCompleted, second.Status);
        Assert.Equal(LegacyOpenAiProviderMigrationStatus.AlreadyCompleted, third.Status);
        Assert.Equal(1, fixture.Credentials.SaveCount);
        Assert.Equal(1, fixture.CountRows("llm_providers", "provider_id = 'openai'"));
        Assert.Equal(
            1,
            fixture.CountRows(
                "settings",
                $"key = '{LegacyOpenAiProviderMigration.StateSettingKey}'"));
    }

    private sealed class MigrationDatabase : IDisposable
    {
        private static readonly WindowsInteractiveFeatureFlags EnabledFlags = new(
            selectionTransformEnabled: true,
            builtinAgentEnabled: true);

        private readonly TemporaryDirectory directory = new();
        private readonly SqliteConnectionFactory factory;
        private readonly SqliteTransactionRunner runner;

        public MigrationDatabase()
        {
            DatabasePath = Path.Combine(directory.Path, "voxflow.db");
            new VoxFlowDatabaseMigrator().Migrate(DatabasePath);
            factory = new SqliteConnectionFactory(DatabasePath, pooling: false);
            SeedLegacyMetadata();
            new VoxFlowDatabaseMigrator(
                InteractiveFeatureMigrationCatalog.For(EnabledFlags))
                .Migrate(DatabasePath);
            runner = new SqliteTransactionRunner(factory);
            Repository = new SqliteLlmProviderRepository(runner);
            Credentials = new FakeCredentialVault();
            Migration = new LegacyOpenAiProviderMigration(
                runner,
                Credentials,
                new ControlledTimeProvider(
                    DateTimeOffset.FromUnixTimeMilliseconds(1_000)));
        }

        public string DatabasePath { get; }

        public SqliteLlmProviderRepository Repository { get; }

        public FakeCredentialVault Credentials { get; }

        public LegacyOpenAiProviderMigration Migration { get; }

        public string? ReadMigrationStateJson()
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue(
                "$key",
                LegacyOpenAiProviderMigration.StateSettingKey);
            return command.ExecuteScalar() as string;
        }

        public string? ReadMigrationStatus()
        {
            var json = ReadMigrationStateJson();
            if (json is null)
            {
                return null;
            }

            using var document = JsonDocument.Parse(json);
            return document.RootElement.GetProperty("status").GetString();
        }

        public void WriteMigrationState(string json, long updatedAtUnixMs)
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ($key, $json, $updatedAt);";
            command.Parameters.AddWithValue(
                "$key",
                LegacyOpenAiProviderMigration.StateSettingKey);
            command.Parameters.AddWithValue("$json", json);
            command.Parameters.AddWithValue("$updatedAt", updatedAtUnixMs);
            command.ExecuteNonQuery();
        }

        public void SetProviderCredentialReference(string? value, long updatedAtUnixMs)
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "UPDATE llm_providers SET api_key_ref = $reference, " +
                "updated_at_unix_ms = $updatedAt WHERE provider_id = 'openai';";
            command.Parameters.AddWithValue("$reference", value ?? (object)DBNull.Value);
            command.Parameters.AddWithValue("$updatedAt", updatedAtUnixMs);
            Assert.Equal(1, command.ExecuteNonQuery());
        }

        public void UpdateProviderAsUser()
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "UPDATE llm_providers SET base_url = 'https://user.example/v1', " +
                "model = 'user-model', enabled = 0, is_default = 0, " +
                "updated_at_unix_ms = 2000 WHERE provider_id = 'openai';";
            Assert.Equal(1, command.ExecuteNonQuery());
        }

        public int CountRows(string table, string predicate)
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText = $"SELECT COUNT(*) FROM {table} WHERE {predicate};";
            return Convert.ToInt32(command.ExecuteScalar());
        }

        public void Dispose()
        {
            Credentials.Dispose();
            runner.Dispose();
            directory.Dispose();
        }

        private void SeedLegacyMetadata()
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "INSERT INTO llm_providers(" +
                "provider_id, base_url, model, enabled, updated_at_unix_ms" +
                ") VALUES ('openai', 'https://legacy.example/v1', " +
                "'legacy-model', 1, 100);";
            command.ExecuteNonQuery();
        }
    }

    private sealed class FakeCredentialVault : ICredentialVault
    {
        private readonly Dictionary<CredentialKey, string> secrets = [];
        private bool failProviderRead;

        public int SaveCount { get; private set; }

        public bool FailNextProviderReadAfterSave { get; set; }

        public void Seed(CredentialKey key, string secret) => secrets[key] = secret;

        public string? Peek(CredentialKey key) =>
            secrets.TryGetValue(key, out var value) ? value : null;

        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            SaveCount++;
            secrets[key] = secret;
            if (FailNextProviderReadAfterSave
                && key == LegacyOpenAiProviderMigration.ProviderApiKey)
            {
                FailNextProviderReadAfterSave = false;
                failProviderRead = true;
            }
            return Task.CompletedTask;
        }

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (failProviderRead
                && key == LegacyOpenAiProviderMigration.ProviderApiKey)
            {
                failProviderRead = false;
                throw new CredentialUnavailableException();
            }
            return Task.FromResult(Peek(key));
        }

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(secrets.ContainsKey(key)
                ? new CredentialPresentation(
                    CredentialAvailability.Available,
                    "••••••••")
                : new CredentialPresentation(
                    CredentialAvailability.Missing,
                    string.Empty));
        }

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _ = secrets.Remove(key);
            return Task.CompletedTask;
        }

        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var matching = secrets.Keys
                .Where(key => key.OwnerKind == ownerKind && key.OwnerId == ownerId)
                .ToArray();
            foreach (var key in matching)
            {
                _ = secrets.Remove(key);
            }
            return Task.FromResult(matching.Length);
        }

        public void Dispose()
        {
        }
    }
}
