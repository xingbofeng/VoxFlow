using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class LlmProviderManagementServiceTests
{
    [Fact]
    public async Task New_remote_template_saves_all_metadata_key_and_unique_default()
    {
        using var fixture = new ManagementFixture();
        var draft = new LlmProviderDraft(
            providerId: null,
            templateId: "deepseek",
            displayName: "DeepSeek",
            baseUrl: "https://api.deepseek.com/",
            model: "deepseek-chat",
            temperature: 0.3,
            timeoutSeconds: 45,
            enabled: true,
            isDefault: true);

        var saved = await fixture.Service.SaveAsync(
            draft,
            "remote fixture key",
            retainExistingCredential: false,
            CancellationToken.None);

        Assert.Equal("provider-1", saved.Id);
        Assert.Equal(new Uri("https://api.deepseek.com"), saved.BaseUri);
        Assert.Equal("deepseek-chat", saved.DefaultModel);
        Assert.Equal(0.3, saved.Temperature, 6);
        Assert.Equal(45, saved.TimeoutSeconds);
        Assert.True(saved.Enabled);
        Assert.True(saved.IsDefault);
        Assert.Equal("llm-provider/provider-1/api_key", saved.ApiKeyRef);
        Assert.Equal(1_000, saved.CreatedAtUnixMs);
        Assert.Equal(1_000, saved.UpdatedAtUnixMs);
        Assert.Equal(
            "remote fixture key",
            await fixture.Vault.ReadSecretAsync(
                LlmProviderCredentialKeys.ApiKey("provider-1")));
        Assert.Equal("provider-1", fixture.Repository.GetDefault()?.Id);
    }

    [Fact]
    public async Task Loopback_template_saves_without_key_and_discovers_with_same_snapshot()
    {
        using var fixture = new ManagementFixture();
        var saved = await fixture.Service.SaveAsync(
            new LlmProviderDraft(
                providerId: null,
                templateId: "ollama-local",
                displayName: "Ollama 本地",
                baseUrl: "http://localhost:11434/v1",
                model: "qwen-local",
                temperature: 0.2,
                timeoutSeconds: 120,
                enabled: true,
                isDefault: false),
            apiKey: null,
            retainExistingCredential: false,
            CancellationToken.None);

        Assert.Null(saved.ApiKeyRef);
        Assert.Null(await fixture.Vault.ReadSecretAsync(
            LlmProviderCredentialKeys.ApiKey(saved.Id)));
        var models = await fixture.Service.DiscoverModelsAsync(
            saved.Id,
            CancellationToken.None);
        Assert.Equal(LlmModelDiscoverySource.Remote, models.Source);
        Assert.Equal("qwen-local", Assert.Single(models.Models).Id);
        Assert.Equal(saved.Id, fixture.Client.LastConfiguration?.ProviderId);
        Assert.Equal(new Uri("http://localhost:11434/v1"),
            fixture.Client.LastConfiguration?.BaseUri);
        Assert.Null(fixture.Client.LastConfiguration?.ApiKey);
    }

    [Fact]
    public async Task Edit_keeps_key_resets_stale_health_and_exposes_two_independent_tests_and_delete()
    {
        using var fixture = new ManagementFixture();
        var original = await fixture.Service.SaveAsync(
            new LlmProviderDraft(
                providerId: null,
                templateId: "deepseek",
                displayName: "DeepSeek",
                baseUrl: "https://api.deepseek.com",
                model: "old-model",
                temperature: 0.2,
                timeoutSeconds: 30,
                enabled: true,
                isDefault: true),
            "existing fixture key",
            retainExistingCredential: false,
            CancellationToken.None);
        Assert.True(fixture.Repository.UpdateHealth(
            original.Id,
            new LlmProviderHealthUpdate(
                LlmProviderHealthStatus.Ok,
                "old_health",
                12,
                1_100,
                1_100)));
        Assert.True(fixture.Repository.UpdateAgentCapability(
            original.Id,
            new LlmAgentCapabilityUpdate(
                LlmAgentCapabilityStatus.Supported,
                "old_agent",
                1_100,
                1_100)));
        fixture.Clock.Advance(TimeSpan.FromMilliseconds(1_000));

        var edited = await fixture.Service.SaveAsync(
            new LlmProviderDraft(
                original.Id,
                "deepseek",
                "DeepSeek Edited",
                "https://api.deepseek.com",
                "new-model",
                0.4,
                90,
                enabled: true,
                isDefault: true),
            apiKey: null,
            retainExistingCredential: true,
            CancellationToken.None);

        Assert.Equal(original.CreatedAtUnixMs, edited.CreatedAtUnixMs);
        Assert.Equal(2_000, edited.UpdatedAtUnixMs);
        Assert.Equal(LlmProviderHealthStatus.Unknown, edited.HealthStatus);
        Assert.Equal(LlmAgentCapabilityStatus.Unknown, edited.AgentCapabilityStatus);
        Assert.Equal(
            "existing fixture key",
            await fixture.Vault.ReadSecretAsync(
                LlmProviderCredentialKeys.ApiKey(original.Id)));

        var connection = await fixture.Service.TestConnectionAsync(
            original.Id,
            CancellationToken.None);
        var agent = await fixture.Service.TestAgentCapabilityAsync(
            original.Id,
            CancellationToken.None);
        var tested = fixture.Repository.Get(original.Id)!;
        Assert.True(connection.Succeeded);
        Assert.Equal(LlmProviderHealthStatus.Ok, tested.HealthStatus);
        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, tested.AgentCapabilityStatus);
        Assert.Equal("tool_calls_missing", agent.SafeMessage);

        Assert.True(await fixture.Service.DeleteAsync(
            original.Id,
            CancellationToken.None));
        Assert.Null(fixture.Repository.Get(original.Id));
        Assert.Null(await fixture.Vault.ReadSecretAsync(
            LlmProviderCredentialKeys.ApiKey(original.Id)));
    }

    private sealed class ManagementFixture : IDisposable
    {
        public ManagementFixture()
        {
            Repository = new MemoryRepository();
            Vault = new MemoryCredentialVault();
            Credentials = new LlmProviderCredentialService(Vault, Repository);
            Client = new FakeProviderClient();
            Clock = new ControlledTimeProvider(
                DateTimeOffset.FromUnixTimeMilliseconds(1_000));
            Service = new LlmProviderManagementService(
                Repository,
                Credentials,
                Client,
                Clock,
                () => "provider-1");
        }

        public MemoryRepository Repository { get; }

        public MemoryCredentialVault Vault { get; }

        public LlmProviderCredentialService Credentials { get; }

        public FakeProviderClient Client { get; }

        public ControlledTimeProvider Clock { get; }

        public LlmProviderManagementService Service { get; }

        public void Dispose() => Vault.Dispose();
    }

    private sealed class FakeProviderClient : ILlmProviderClient
    {
        public LlmProviderClientConfiguration? LastConfiguration { get; private set; }

        public ValueTask<LlmCompletionResponse> CompleteAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(new LlmCompletionResponse(
                "ok",
                configuration.ProviderId,
                configuration.Model,
                null));

        public async IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            [System.Runtime.CompilerServices.EnumeratorCancellation]
            CancellationToken cancellationToken)
        {
            await Task.CompletedTask;
            yield return new LlmStreamUpdate("ok", "ok", true, null);
        }

        public ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            LastConfiguration = configuration;
            return ValueTask.FromResult(new LlmModelDiscoveryResult(
                [new LlmModelDescriptor(configuration.Model, null, null)],
                LlmModelDiscoverySource.Remote));
        }

        public ValueTask<LlmConnectionTestResult> TestConnectionAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            LastConfiguration = configuration;
            return ValueTask.FromResult(new LlmConnectionTestResult(
                LlmConnectionTestStatus.Succeeded,
                21,
                null));
        }

        public ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            LastConfiguration = configuration;
            return ValueTask.FromResult(new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Unsupported,
                "tool_calls_missing"));
        }
    }

    private sealed class MemoryCredentialVault : ICredentialVault
    {
        private readonly Dictionary<CredentialKey, string> values = [];

        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default)
        {
            values[key] = secret;
            return Task.CompletedTask;
        }

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(values.TryGetValue(key, out var value) ? value : null);

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(values.ContainsKey(key)
                ? new CredentialPresentation(CredentialAvailability.Available, "••••••••")
                : new CredentialPresentation(CredentialAvailability.Missing, string.Empty));

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            _ = values.Remove(key);
            return Task.CompletedTask;
        }

        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default)
        {
            var keys = values.Keys.Where(key =>
                key.OwnerKind == ownerKind && key.OwnerId == ownerId).ToArray();
            foreach (var key in keys)
            {
                _ = values.Remove(key);
            }
            return Task.FromResult(keys.Length);
        }

        public void Dispose() => values.Clear();
    }

    private sealed class MemoryRepository : ILlmProviderRepository
    {
        private readonly Dictionary<string, LlmProviderRecord> values =
            new(StringComparer.Ordinal);

        public IReadOnlyList<LlmProviderRecord> List() => values.Values
            .OrderByDescending(provider => provider.IsDefault)
            .ThenBy(provider => provider.Id, StringComparer.Ordinal)
            .ToArray();

        public LlmProviderRecord? Get(string providerId) =>
            values.TryGetValue(providerId, out var value) ? value : null;

        public LlmProviderRecord? GetDefault() => values.Values.SingleOrDefault(
            provider => provider.Enabled && provider.IsDefault);

        public void Upsert(LlmProviderRecord provider)
        {
            if (provider.IsDefault)
            {
                foreach (var other in values.Values
                    .Where(value => value.IsDefault && value.Id != provider.Id)
                    .ToArray())
                {
                    values[other.Id] = Copy(other, isDefault: false);
                }
            }
            values[provider.Id] = provider;
        }

        public bool Delete(string providerId) => values.Remove(providerId);

        public bool SetEnabled(string providerId, bool enabled, long updatedAtUnixMs)
        {
            if (Get(providerId) is not { } provider)
            {
                return false;
            }
            values[providerId] = Copy(
                provider,
                enabled: enabled,
                isDefault: enabled && provider.IsDefault,
                updatedAtUnixMs: updatedAtUnixMs);
            return true;
        }

        public bool SetDefault(string providerId, long updatedAtUnixMs)
        {
            if (Get(providerId) is not { Enabled: true } selected)
            {
                return false;
            }
            foreach (var provider in values.Values.ToArray())
            {
                values[provider.Id] = Copy(
                    provider,
                    isDefault: provider.Id == selected.Id,
                    updatedAtUnixMs: updatedAtUnixMs);
            }
            return true;
        }

        public bool UpdateHealth(string providerId, LlmProviderHealthUpdate update)
        {
            if (Get(providerId) is not { } provider)
            {
                return false;
            }
            values[providerId] = new LlmProviderRecord(
                provider.Id, provider.DisplayName, provider.ProviderType,
                provider.BaseUri, provider.DefaultModel, provider.ApiKeyRef,
                provider.Temperature, provider.TimeoutSeconds, provider.Enabled,
                provider.IsDefault, update.Status, update.SafeMessage,
                update.LatencyMs, update.CheckedAtUnixMs,
                provider.AgentCapabilityStatus, provider.AgentCapabilityMessage,
                provider.AgentCapabilityCheckedAtUnixMs, provider.CreatedAtUnixMs,
                update.UpdatedAtUnixMs);
            return true;
        }

        public bool UpdateAgentCapability(
            string providerId,
            LlmAgentCapabilityUpdate update)
        {
            if (Get(providerId) is not { } provider)
            {
                return false;
            }
            values[providerId] = new LlmProviderRecord(
                provider.Id, provider.DisplayName, provider.ProviderType,
                provider.BaseUri, provider.DefaultModel, provider.ApiKeyRef,
                provider.Temperature, provider.TimeoutSeconds, provider.Enabled,
                provider.IsDefault, provider.HealthStatus, provider.HealthMessage,
                provider.HealthLatencyMs, provider.HealthCheckedAtUnixMs,
                update.Status, update.SafeMessage, update.CheckedAtUnixMs,
                provider.CreatedAtUnixMs, update.UpdatedAtUnixMs);
            return true;
        }

        private static LlmProviderRecord Copy(
            LlmProviderRecord provider,
            bool? enabled = null,
            bool? isDefault = null,
            long? updatedAtUnixMs = null) => new(
                provider.Id, provider.DisplayName, provider.ProviderType,
                provider.BaseUri, provider.DefaultModel, provider.ApiKeyRef,
                provider.Temperature, provider.TimeoutSeconds,
                enabled ?? provider.Enabled, isDefault ?? provider.IsDefault,
                provider.HealthStatus, provider.HealthMessage,
                provider.HealthLatencyMs, provider.HealthCheckedAtUnixMs,
                provider.AgentCapabilityStatus, provider.AgentCapabilityMessage,
                provider.AgentCapabilityCheckedAtUnixMs, provider.CreatedAtUnixMs,
                updatedAtUnixMs ?? provider.UpdatedAtUnixMs);
    }
}
