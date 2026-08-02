using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class LlmProviderRepositoryTests
{
    [Fact]
    public void Crud_round_trips_all_provider_fields_and_preserves_timestamps()
    {
        using var fixture = new ProviderDatabase();
        var repository = fixture.Repository;
        var original = Provider(
            "deepseek",
            "DeepSeek",
            createdAtUnixMs: 100,
            updatedAtUnixMs: 100);

        repository.Upsert(original);
        var stored = Assert.IsType<LlmProviderRecord>(repository.Get("deepseek"));

        Assert.Equal("DeepSeek", stored.DisplayName);
        Assert.Equal(LlmProviderType.OpenAiCompatible, stored.ProviderType);
        Assert.Equal(new Uri("https://example.test/deepseek/v1"), stored.BaseUri);
        Assert.Equal("model-deepseek", stored.DefaultModel);
        Assert.Equal("llm-provider/deepseek/api_key", stored.ApiKeyRef);
        Assert.Equal(0.2, stored.Temperature, precision: 6);
        Assert.Equal(60, stored.TimeoutSeconds);
        Assert.True(stored.Enabled);
        Assert.False(stored.IsDefault);
        Assert.Equal(100, stored.CreatedAtUnixMs);
        Assert.Equal(100, stored.UpdatedAtUnixMs);

        repository.Upsert(Provider(
            "deepseek",
            "DeepSeek Updated",
            model: "model-new",
            createdAtUnixMs: 100,
            updatedAtUnixMs: 200));
        stored = Assert.IsType<LlmProviderRecord>(repository.Get("deepseek"));

        Assert.Equal("DeepSeek Updated", stored.DisplayName);
        Assert.Equal("model-new", stored.DefaultModel);
        Assert.Equal(100, stored.CreatedAtUnixMs);
        Assert.Equal(200, stored.UpdatedAtUnixMs);
        Assert.Single(repository.List());
        Assert.True(repository.Delete("deepseek"));
        Assert.False(repository.Delete("deepseek"));
        Assert.Null(repository.Get("deepseek"));
    }

    [Fact]
    public void Default_switch_is_unique_and_disable_delete_never_selects_a_fallback()
    {
        using var fixture = new ProviderDatabase();
        var repository = fixture.Repository;
        repository.Upsert(Provider("first", "First"));
        repository.Upsert(Provider("second", "Second"));

        Assert.Null(repository.GetDefault());
        Assert.True(repository.SetDefault("first", updatedAtUnixMs: 200));
        Assert.Equal("first", repository.GetDefault()?.Id);
        Assert.True(repository.SetDefault("second", updatedAtUnixMs: 300));
        Assert.Equal("second", repository.GetDefault()?.Id);
        _ = Assert.Single(repository.List(), provider => provider.IsDefault);

        Assert.True(repository.SetEnabled(
            "second",
            enabled: false,
            updatedAtUnixMs: 400));
        Assert.Null(repository.GetDefault());
        Assert.False(repository.Get("first")?.IsDefault);
        Assert.False(repository.Get("second")?.Enabled);

        Assert.True(repository.SetDefault("first", updatedAtUnixMs: 500));
        Assert.True(repository.Delete("first"));
        Assert.Null(repository.GetDefault());
        Assert.False(repository.Get("second")?.IsDefault);
    }

    [Fact]
    public void Ordinary_health_and_agent_capability_updates_are_independent()
    {
        using var fixture = new ProviderDatabase();
        var repository = fixture.Repository;
        repository.Upsert(Provider("provider", "Provider"));

        Assert.True(repository.UpdateHealth(
            "provider",
            new LlmProviderHealthUpdate(
                LlmProviderHealthStatus.Ok,
                safeMessage: "completion_ok",
                latencyMs: 42,
                checkedAtUnixMs: 200,
                updatedAtUnixMs: 200)));
        var afterHealth = Assert.IsType<LlmProviderRecord>(repository.Get("provider"));
        Assert.Equal(LlmProviderHealthStatus.Ok, afterHealth.HealthStatus);
        Assert.Equal(42, afterHealth.HealthLatencyMs);
        Assert.Equal(LlmAgentCapabilityStatus.Unknown, afterHealth.AgentCapabilityStatus);
        Assert.Null(afterHealth.AgentCapabilityCheckedAtUnixMs);

        Assert.True(repository.UpdateAgentCapability(
            "provider",
            new LlmAgentCapabilityUpdate(
                LlmAgentCapabilityStatus.Unsupported,
                safeMessage: "tool_calls_missing",
                checkedAtUnixMs: 300,
                updatedAtUnixMs: 300)));
        var afterAgent = Assert.IsType<LlmProviderRecord>(repository.Get("provider"));
        Assert.Equal(LlmProviderHealthStatus.Ok, afterAgent.HealthStatus);
        Assert.Equal(42, afterAgent.HealthLatencyMs);
        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, afterAgent.AgentCapabilityStatus);
        Assert.Equal("tool_calls_missing", afterAgent.AgentCapabilityMessage);
        Assert.Equal(300, afterAgent.AgentCapabilityCheckedAtUnixMs);
        Assert.Equal(300, afterAgent.UpdatedAtUnixMs);
    }

    [Fact]
    public async Task Concurrent_default_transactions_leave_exactly_one_enabled_default()
    {
        using var fixture = new ProviderDatabase();
        var ids = Enumerable.Range(0, 8)
            .Select(index => $"provider-{index}")
            .ToArray();
        foreach (var id in ids)
        {
            fixture.Repository.Upsert(Provider(id, id));
        }

        var tasks = ids.Select((id, index) => Task.Run(() =>
        {
            using var runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(fixture.DatabasePath, pooling: false));
            var repository = new SqliteLlmProviderRepository(runner);
            Assert.True(repository.SetDefault(id, 1_000 + index));
        })).ToArray();
        await Task.WhenAll(tasks).WaitAsync(TimeSpan.FromSeconds(30));

        var providers = fixture.Repository.List();
        var selected = Assert.Single(providers, provider => provider.IsDefault);
        Assert.True(selected.Enabled);
        Assert.Contains(selected.Id, ids);
        Assert.Equal(selected.Id, fixture.Repository.GetDefault()?.Id);
    }

    [Fact]
    public void Missing_or_disabled_target_cannot_clear_an_existing_default()
    {
        using var fixture = new ProviderDatabase();
        var repository = fixture.Repository;
        repository.Upsert(Provider("ready", "Ready"));
        repository.Upsert(Provider("disabled", "Disabled", enabled: false));
        Assert.True(repository.SetDefault("ready", 200));

        Assert.False(repository.SetDefault("missing", 300));
        Assert.Equal("ready", repository.GetDefault()?.Id);
        Assert.False(repository.SetDefault("disabled", 400));
        Assert.Equal("ready", repository.GetDefault()?.Id);
    }

    private static LlmProviderRecord Provider(
        string id,
        string displayName,
        string? model = null,
        bool enabled = true,
        bool isDefault = false,
        long createdAtUnixMs = 100,
        long updatedAtUnixMs = 100) => new(
            id,
            displayName,
            LlmProviderType.OpenAiCompatible,
            new Uri($"https://example.test/{id}/v1"),
            model ?? $"model-{id}",
            $"llm-provider/{id}/api_key",
            temperature: 0.2,
            timeoutSeconds: 60,
            enabled,
            isDefault,
            LlmProviderHealthStatus.Unknown,
            healthMessage: null,
            healthLatencyMs: null,
            healthCheckedAtUnixMs: null,
            LlmAgentCapabilityStatus.Unknown,
            agentCapabilityMessage: null,
            agentCapabilityCheckedAtUnixMs: null,
            createdAtUnixMs,
            updatedAtUnixMs);

    private sealed class ProviderDatabase : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly SqliteTransactionRunner runner;

        public ProviderDatabase()
        {
            DatabasePath = Path.Combine(directory.Path, "voxflow.db");
            var flags = new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true);
            new VoxFlowDatabaseMigrator(
                InteractiveFeatureMigrationCatalog.For(flags))
                .Migrate(DatabasePath);
            runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(DatabasePath, pooling: false));
            Repository = new SqliteLlmProviderRepository(runner);
        }

        public string DatabasePath { get; }

        public SqliteLlmProviderRepository Repository { get; }

        public void Dispose()
        {
            runner.Dispose();
            directory.Dispose();
        }
    }
}
