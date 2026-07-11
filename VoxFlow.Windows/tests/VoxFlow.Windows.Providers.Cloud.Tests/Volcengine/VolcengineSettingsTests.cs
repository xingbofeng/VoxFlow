using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Providers.Cloud.Volcengine;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Volcengine;

public sealed class VolcengineSettingsTests
{
    private static readonly VolcengineAsrCredentials Complete = new(
        AppId: "test-app-id",
        AccessToken: "test-access-token",
        SecretKey: "test-secret-key");

    [Fact]
    public async Task Configuration_is_complete_only_when_all_three_credentials_are_saved()
    {
        using var vault = new FakeCredentialVault();
        var service = new VolcengineAsrSettingsService(vault);

        await Assert.ThrowsAsync<ArgumentException>(async () =>
            await service.SaveAsync(
                Complete with { SecretKey = " " },
                CancellationToken.None));

        await service.SaveAsync(Complete, CancellationToken.None);
        var status = await service.GetStatusAsync(CancellationToken.None);

        Assert.True(status.IsComplete);
        Assert.Equal(VolcengineAsrDefaults.Endpoint, status.Endpoint);
        Assert.Equal("volc.bigasr.sauc.duration", status.ResourceId);
        Assert.Equal("bigmodel", status.Model);
        Assert.All(
            [status.AppId, status.AccessToken, status.SecretKey],
            item => Assert.Equal(
                new CredentialPresentation(CredentialAvailability.Available, "••••••••"),
                item));
        Assert.Equal(
            [
                VolcengineCredentialKeys.AppId,
                VolcengineCredentialKeys.AccessToken,
                VolcengineCredentialKeys.SecretKey,
            ],
            vault.SavedKeys);

        await vault.DeleteAsync(VolcengineCredentialKeys.SecretKey);

        Assert.False((await service.GetStatusAsync(CancellationToken.None)).IsComplete);
    }

    [Fact]
    public async Task Delete_removes_the_provider_owner_and_reveal_reads_each_DPAPI_field()
    {
        using var vault = new FakeCredentialVault();
        var service = new VolcengineAsrSettingsService(vault);
        await service.SaveAsync(Complete, CancellationToken.None);

        Assert.Equal(Complete, await service.RevealAsync(CancellationToken.None));

        await service.DeleteAsync(CancellationToken.None);

        Assert.Equal(("asr", "volcengine_asr"), vault.LastDeletedOwner);
        Assert.False((await service.GetStatusAsync(CancellationToken.None)).IsComplete);
    }

    [Fact]
    public void Handshake_never_sends_or_logs_secret_key()
    {
        var descriptor = VolcengineHandshakeDescriptor.Create(
            Complete,
            connectId: "test-connect-id");

        Assert.Equal("test-app-id", descriptor.Headers["X-Api-App-Key"]);
        Assert.Equal("test-access-token", descriptor.Headers["X-Api-Access-Key"]);
        Assert.Equal(
            VolcengineAsrDefaults.ResourceId,
            descriptor.Headers["X-Api-Resource-Id"]);
        Assert.Equal("test-connect-id", descriptor.Headers["X-Api-Connect-Id"]);
        Assert.DoesNotContain(
            Complete.SecretKey,
            string.Join("\n", descriptor.Headers.Values),
            StringComparison.Ordinal);
        Assert.DoesNotContain(Complete.SecretKey, descriptor.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Complete.AccessToken, descriptor.SafeDiagnostic, StringComparison.Ordinal);
    }

    private sealed class FakeCredentialVault : ICredentialVault
    {
        private readonly Dictionary<CredentialKey, string> secrets = [];

        public List<CredentialKey> SavedKeys { get; } = [];

        public (string OwnerKind, string OwnerId)? LastDeletedOwner { get; private set; }

        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default)
        {
            SavedKeys.Add(key);
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
