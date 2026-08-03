using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiSettingsTests
{
    private const string ApiKey = "s" + "k-fixture-openai-key";

    [Fact]
    public async Task Production_card_defaults_to_TokenHub_compatible_endpoint()
    {
        using var vault = new FakeCredentialVault();
        var store = new FakeLlmProviderSettingsStore();
        var service = new OpenAiSettingsService(
            vault,
            store,
            new CapturingConnectionTester());

        var status = await service.GetStatusAsync(CancellationToken.None);

        Assert.Equal(new Uri("https://tokenhub.tencentmaas.com/v1"), status.BaseUri);
        Assert.Equal("tokenhub.tencentmaas.com", status.BaseUri.Host);
        Assert.Equal("deepseek-v4-flash", status.Model);
        Assert.Equal(OpenAiProductionDefaults.DefaultModel, status.Model);
        Assert.False(status.Enabled);
        Assert.False(status.IsConfigured);
        Assert.False(status.CanTestConnection);
        Assert.Equal(CredentialAvailability.Missing, status.ApiKey.Availability);
        Assert.Null(await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));
    }

    [Fact]
    public async Task Save_mask_reveal_test_and_delete_use_DPAPI_and_persist_only_official_metadata()
    {
        using var vault = new FakeCredentialVault();
        var store = new FakeLlmProviderSettingsStore();
        var tester = new CapturingConnectionTester();
        var service = new OpenAiSettingsService(vault, store, tester);

        await service.SaveAsync(
            ApiKey,
            model: " gpt-fixture-model ",
            enabled: true,
            CancellationToken.None);
        var status = await service.GetStatusAsync(CancellationToken.None);

        Assert.True(status.Enabled);
        Assert.True(status.IsConfigured);
        Assert.True(status.CanTestConnection);
        Assert.Equal("gpt-fixture-model", status.Model);
        Assert.Equal("••••••••", status.ApiKey.Mask);
        Assert.Equal([OpenAiCredentialKeys.ApiKey], vault.SavedKeys);
        Assert.Equal(
            new LlmProviderSettings(
                LlmProviderId.OpenAI,
                OpenAiProductionDefaults.BaseUri,
                "gpt-fixture-model",
                Enabled: true),
            await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));

        Assert.Equal(ApiKey, await service.RevealApiKeyAsync(CancellationToken.None));
        var result = await service.TestConnectionAsync(CancellationToken.None);
        Assert.True(result.Succeeded);
        Assert.Equal(OpenAiProductionDefaults.BaseUri, tester.Configuration!.BaseUri);
        Assert.Equal("gpt-fixture-model", tester.Configuration.Model);
        Assert.Equal(ApiKey, tester.Configuration.ApiKey);
        Assert.DoesNotContain(ApiKey, tester.Configuration.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(ApiKey, result.ToString(), StringComparison.Ordinal);

        await service.DeleteAsync(CancellationToken.None);

        Assert.Equal(("llm", "openai"), vault.LastDeletedOwner);
        Assert.Null(await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));
        Assert.False((await service.GetStatusAsync(CancellationToken.None)).IsConfigured);
    }

    [Theory]
    [InlineData("", "gpt-model")]
    [InlineData(" ", "gpt-model")]
    [InlineData(ApiKey, "")]
    [InlineData(ApiKey, "\t")]
    public async Task Save_rejects_blank_key_or_model_before_writing(
        string apiKey,
        string model)
    {
        using var vault = new FakeCredentialVault();
        var store = new FakeLlmProviderSettingsStore();
        var service = new OpenAiSettingsService(
            vault,
            store,
            new CapturingConnectionTester());

        await Assert.ThrowsAsync<ArgumentException>(async () =>
            await service.SaveAsync(apiKey, model, enabled: true, CancellationToken.None));

        Assert.Empty(vault.SavedKeys);
        Assert.Null(await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));
    }

    [Fact]
    public async Task Missing_or_unavailable_key_never_runs_a_connection_test()
    {
        using var vault = new FakeCredentialVault();
        var store = new FakeLlmProviderSettingsStore();
        var tester = new CapturingConnectionTester();
        var service = new OpenAiSettingsService(vault, store, tester);
        await store.SaveAsync(
            new LlmProviderSettings(
                LlmProviderId.OpenAI,
                OpenAiProductionDefaults.BaseUri,
                "gpt-model",
                Enabled: true),
            CancellationToken.None);

        var missing = await service.TestConnectionAsync(CancellationToken.None);
        vault.Unavailable = true;
        var unavailable = await service.TestConnectionAsync(CancellationToken.None);

        Assert.False(missing.Succeeded);
        Assert.Equal(OpenAiConnectionTestError.NotConfigured, missing.Error);
        Assert.False(unavailable.Succeeded);
        Assert.Equal(OpenAiConnectionTestError.CredentialsUnavailable, unavailable.Error);
        Assert.Equal(0, tester.CallCount);
    }

    private sealed class CapturingConnectionTester : IOpenAiConnectionTester
    {
        public int CallCount { get; private set; }

        public OpenAiClientConfiguration? Configuration { get; private set; }

        public ValueTask<OpenAiConnectionTestResult> TestAsync(
            OpenAiClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            CallCount++;
            Configuration = configuration;
            return ValueTask.FromResult(OpenAiConnectionTestResult.Success);
        }
    }

    private sealed class FakeLlmProviderSettingsStore : ILlmProviderSettingsStore
    {
        private readonly Dictionary<LlmProviderId, LlmProviderSettings> values = [];

        public ValueTask<LlmProviderSettings?> LoadAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(values.GetValueOrDefault(provider));

        public ValueTask SaveAsync(
            LlmProviderSettings settings,
            CancellationToken cancellationToken)
        {
            values[settings.Provider] = settings;
            return ValueTask.CompletedTask;
        }

        public ValueTask DeleteAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken)
        {
            values.Remove(provider);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeCredentialVault : ICredentialVault
    {
        private readonly Dictionary<CredentialKey, string> values = [];

        public List<CredentialKey> SavedKeys { get; } = [];

        public (string OwnerKind, string OwnerId)? LastDeletedOwner { get; private set; }

        public bool Unavailable { get; set; }

        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default)
        {
            values[key] = secret;
            SavedKeys.Add(key);
            return Task.CompletedTask;
        }

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Unavailable
                ? throw new CredentialUnavailableException()
                : Task.FromResult(values.GetValueOrDefault(key));

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Unavailable
                ? new CredentialPresentation(CredentialAvailability.Unavailable, "••••••••")
                : values.ContainsKey(key)
                    ? new CredentialPresentation(CredentialAvailability.Available, "••••••••")
                    : new CredentialPresentation(CredentialAvailability.Missing, string.Empty));

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            values.Remove(key);
            return Task.CompletedTask;
        }

        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default)
        {
            LastDeletedOwner = (ownerKind, ownerId);
            var keys = values.Keys
                .Where(key => key.OwnerKind == ownerKind && key.OwnerId == ownerId)
                .ToArray();
            foreach (var key in keys)
            {
                values.Remove(key);
            }

            return Task.FromResult(keys.Length);
        }

        public void Dispose()
        {
        }
    }
}
