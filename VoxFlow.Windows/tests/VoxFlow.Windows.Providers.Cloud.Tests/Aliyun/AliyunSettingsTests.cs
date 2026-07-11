using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Providers.Cloud.Aliyun;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Aliyun;

public sealed class AliyunSettingsTests
{
    private const string SentinelApiKey = "s" + "k-ws-test-sentinel-never-log";

    [Fact]
    public async Task Save_mask_reveal_and_delete_use_the_provider_scoped_DPAPI_vault_path()
    {
        using var vault = new FakeCredentialVault();
        var tester = new CapturingAliyunConnectionTester();
        var service = new AliyunAsrSettingsService(vault, tester);

        await Assert.ThrowsAsync<ArgumentException>(async () =>
            await service.SaveAsync("   ", CancellationToken.None));

        await service.SaveAsync(SentinelApiKey, CancellationToken.None);
        var status = await service.GetStatusAsync(CancellationToken.None);

        Assert.Equal(AliyunAsrDefaults.Model, status.Model);
        Assert.Equal("fun-asr-realtime", status.Model);
        Assert.Equal(
            new Uri("wss://dashscope.aliyuncs.com/api-ws/v1/inference"),
            status.Endpoint);
        Assert.Equal(CredentialAvailability.Available, status.ApiKey.Availability);
        Assert.Equal("••••••••", status.ApiKey.Mask);
        Assert.True(status.CanTestConnection);
        Assert.Equal(AliyunCredentialKeys.ApiKey, vault.LastSavedKey);
        Assert.Equal(SentinelApiKey, await service.RevealApiKeyAsync(CancellationToken.None));

        await service.DeleteAsync(CancellationToken.None);

        Assert.Equal(("asr", "aliyun_dashscope_asr"), vault.LastDeletedOwner);
        Assert.Equal(
            CredentialAvailability.Missing,
            (await service.GetStatusAsync(CancellationToken.None)).ApiKey.Availability);
    }

    [Fact]
    public async Task Explicit_connection_test_reads_the_secret_without_exposing_it_in_result_text()
    {
        using var vault = new FakeCredentialVault();
        var tester = new CapturingAliyunConnectionTester();
        var service = new AliyunAsrSettingsService(vault, tester);
        await service.SaveAsync(SentinelApiKey, CancellationToken.None);

        var result = await service.TestConnectionAsync(CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.Equal(SentinelApiKey, tester.ApiKey);
        Assert.DoesNotContain(SentinelApiKey, result.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("Bearer", result.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Handshake_uses_bearer_auth_but_safe_diagnostics_never_render_the_key()
    {
        var descriptor = AliyunHandshakeDescriptor.Create(SentinelApiKey);

        Assert.Equal(
            $"Bearer {SentinelApiKey}",
            descriptor.Headers["Authorization"]);
        Assert.Equal(AliyunAsrDefaults.Endpoint, descriptor.Endpoint);
        Assert.DoesNotContain(SentinelApiKey, descriptor.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SentinelApiKey, descriptor.SafeDiagnostic, StringComparison.Ordinal);
        Assert.Contains("fun-asr-realtime", descriptor.SafeDiagnostic, StringComparison.Ordinal);
    }

    private sealed class CapturingAliyunConnectionTester : IAliyunConnectionTester
    {
        public string? ApiKey { get; private set; }

        public ValueTask<AliyunConnectionTestResult> TestAsync(
            string apiKey,
            CancellationToken cancellationToken)
        {
            ApiKey = apiKey;
            return ValueTask.FromResult(
                new AliyunConnectionTestResult(Succeeded: true, ErrorCode: null));
        }
    }

    private sealed class FakeCredentialVault : ICredentialVault
    {
        private readonly Dictionary<CredentialKey, string> secrets = [];

        public CredentialKey? LastSavedKey { get; private set; }

        public (string OwnerKind, string OwnerId)? LastDeletedOwner { get; private set; }

        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default)
        {
            LastSavedKey = key;
            secrets[key] = secret;
            return Task.CompletedTask;
        }

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(secrets.GetValueOrDefault(key));

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(secrets.ContainsKey(key)
                ? new CredentialPresentation(CredentialAvailability.Available, "••••••••")
                : new CredentialPresentation(CredentialAvailability.Missing, string.Empty));

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            secrets.Remove(key);
            return Task.CompletedTask;
        }

        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default)
        {
            LastDeletedOwner = (ownerKind, ownerId);
            var keys = secrets.Keys
                .Where(key => key.OwnerKind == ownerKind && key.OwnerId == ownerId)
                .ToArray();
            foreach (var key in keys)
            {
                secrets.Remove(key);
            }

            return Task.FromResult(keys.Length);
        }

        public void Dispose()
        {
        }
    }
}
