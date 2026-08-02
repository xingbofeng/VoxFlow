using System.Security.Cryptography;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Security;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Security;

public sealed class LlmProviderCredentialServiceTests
{
    private const string SensitiveValue = "provider fixture secret 41";

    [Fact]
    public async Task Stable_provider_key_round_trips_for_current_user_with_masked_presentation()
    {
        using var fixture = new CredentialServiceDatabase();
        var key = LlmProviderCredentialKeys.ApiKey("openai");

        await fixture.Service.SaveAsync(
            Provider("openai", "OpenAI"),
            SensitiveValue,
            CancellationToken.None);

        Assert.Equal("llm-provider", key.OwnerKind);
        Assert.Equal("openai", key.OwnerId);
        Assert.Equal("api_key", key.FieldId);
        Assert.Equal(
            "llm-provider/openai/api_key",
            LlmProviderCredentialKeys.Reference("openai"));
        var presentation = await fixture.Service.GetPresentationAsync(
            "openai",
            CancellationToken.None);
        Assert.Equal(CredentialAvailability.Available, presentation.Availability);
        Assert.Equal("••••••••", presentation.Mask);
        Assert.Equal(
            SensitiveValue,
            await fixture.Service.RevealApiKeyAsync(
                "openai",
                CancellationToken.None));
        Assert.Equal(
            LlmProviderCredentialKeys.Reference("openai"),
            fixture.Repository.Get("openai")?.ApiKeyRef);
        Assert.Contains("[REDACTED]", presentation.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(
            SensitiveValue,
            presentation.ToString(),
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Provider_credential_is_unavailable_to_another_user_context()
    {
        using var fixture = new CredentialServiceDatabase();
        await fixture.Service.SaveAsync(
            Provider("openai", "OpenAI"),
            SensitiveValue,
            CancellationToken.None);
        using var otherUserVault = new SqliteCredentialVault(
            fixture.Factory,
            new AlwaysUnavailableProtector());
        var otherUserService = new LlmProviderCredentialService(
            otherUserVault,
            fixture.Repository);

        var presentation = await otherUserService.GetPresentationAsync(
            "openai",
            CancellationToken.None);

        Assert.Equal(CredentialAvailability.Unavailable, presentation.Availability);
        Assert.Equal("••••••••", presentation.Mask);
        await Assert.ThrowsAsync<CredentialUnavailableException>(async () =>
            await otherUserService.RevealApiKeyAsync(
                "openai",
                CancellationToken.None));
    }

    [Fact]
    public async Task Metadata_failure_restores_the_previous_credential()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        var factory = new SqliteConnectionFactory(databasePath, pooling: false);
        using var vault = new SqliteCredentialVault(
            factory,
            new DpapiCurrentUserDataProtector());
        var key = LlmProviderCredentialKeys.ApiKey("openai");
        await vault.SaveAsync(key, "previous fixture key", CancellationToken.None);
        var repository = new ThrowingProviderRepository();
        var service = new LlmProviderCredentialService(vault, repository);

        var error = await Assert.ThrowsAsync<LlmProviderCredentialPersistenceException>(
            async () => await service.SaveAsync(
                Provider("openai", "OpenAI"),
                SensitiveValue,
                CancellationToken.None));

        Assert.Equal(
            "previous fixture key",
            await vault.ReadSecretAsync(key, CancellationToken.None));
        Assert.Equal(
            LlmProviderCredentialKeys.Reference("openai"),
            repository.AttemptedProvider?.ApiKeyRef);
        Assert.Contains("[REDACTED]", error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SensitiveValue, error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(
            "previous fixture key",
            error.ToString(),
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Deleting_provider_removes_only_that_owner_credentials()
    {
        using var fixture = new CredentialServiceDatabase();
        await fixture.Service.SaveAsync(
            Provider("first", "First"),
            "first fixture key",
            CancellationToken.None);
        await fixture.Service.SaveAsync(
            Provider("second", "Second"),
            "second fixture key",
            CancellationToken.None);

        Assert.True(await fixture.Service.DeleteAsync(
            "first",
            CancellationToken.None));
        Assert.Null(fixture.Repository.Get("first"));
        Assert.Null(await fixture.Vault.ReadSecretAsync(
            LlmProviderCredentialKeys.ApiKey("first"),
            CancellationToken.None));
        Assert.NotNull(fixture.Repository.Get("second"));
        Assert.Equal(
            "second fixture key",
            await fixture.Vault.ReadSecretAsync(
                LlmProviderCredentialKeys.ApiKey("second"),
                CancellationToken.None));
        Assert.False(await fixture.Service.DeleteAsync(
            "first",
            CancellationToken.None));
    }

    private static LlmProviderRecord Provider(string id, string displayName) => new(
        id,
        displayName,
        LlmProviderType.OpenAiCompatible,
        new Uri($"https://{id}.example/v1"),
        $"model-{id}",
        apiKeyRef: null,
        temperature: 0.2,
        timeoutSeconds: 60,
        enabled: true,
        isDefault: false,
        LlmProviderHealthStatus.Unknown,
        healthMessage: null,
        healthLatencyMs: null,
        healthCheckedAtUnixMs: null,
        LlmAgentCapabilityStatus.Unknown,
        agentCapabilityMessage: null,
        agentCapabilityCheckedAtUnixMs: null,
        createdAtUnixMs: 100,
        updatedAtUnixMs: 100);

    private sealed class CredentialServiceDatabase : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly SqliteTransactionRunner runner;

        public CredentialServiceDatabase()
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.db");
            var flags = new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true);
            new VoxFlowDatabaseMigrator(
                InteractiveFeatureMigrationCatalog.For(flags))
                .Migrate(databasePath);
            Factory = new SqliteConnectionFactory(databasePath, pooling: false);
            runner = new SqliteTransactionRunner(Factory);
            Repository = new SqliteLlmProviderRepository(runner);
            Vault = new SqliteCredentialVault(
                Factory,
                new DpapiCurrentUserDataProtector());
            Service = new LlmProviderCredentialService(Vault, Repository);
        }

        public SqliteConnectionFactory Factory { get; }

        public SqliteLlmProviderRepository Repository { get; }

        public SqliteCredentialVault Vault { get; }

        public LlmProviderCredentialService Service { get; }

        public void Dispose()
        {
            Vault.Dispose();
            runner.Dispose();
            directory.Dispose();
        }
    }

    private sealed class ThrowingProviderRepository : ILlmProviderRepository
    {
        public LlmProviderRecord? AttemptedProvider { get; private set; }

        public IReadOnlyList<LlmProviderRecord> List() => [];

        public LlmProviderRecord? Get(string providerId) => null;

        public LlmProviderRecord? GetDefault() => null;

        public void Upsert(LlmProviderRecord provider)
        {
            AttemptedProvider = provider;
            throw new InvalidOperationException("Synthetic metadata failure.");
        }

        public bool Delete(string providerId) => false;

        public bool SetEnabled(string providerId, bool enabled, long updatedAtUnixMs) =>
            false;

        public bool SetDefault(string providerId, long updatedAtUnixMs) => false;

        public bool UpdateHealth(string providerId, LlmProviderHealthUpdate update) =>
            false;

        public bool UpdateAgentCapability(
            string providerId,
            LlmAgentCapabilityUpdate update) => false;
    }

    private sealed class AlwaysUnavailableProtector : ICurrentUserDataProtector
    {
        public byte[] Protect(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> entropy) =>
            throw new CryptographicException();

        public byte[] Unprotect(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> entropy) =>
            throw new CryptographicException();
    }
}
