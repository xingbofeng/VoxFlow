using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Tencent;

public sealed class TencentSettingsAndSigningTests
{
    private const string AppId = "1234567890";
    private const string SecretId = "fix" + "ture-secret-id";
    private const string SecretKey = "fix" + "ture-signing-key";

    [Theory]
    [InlineData("", SecretId, SecretKey)]
    [InlineData(AppId, " ", SecretKey)]
    [InlineData(AppId, SecretId, "\t")]
    public void Credentials_require_all_three_non_blank_values(
        string appId,
        string secretId,
        string secretKey)
    {
        Assert.Throws<ArgumentException>(() =>
            new TencentAsrCredentials(appId, secretId, secretKey));
    }

    [Fact]
    public async Task Save_mask_reveal_and_delete_use_provider_scoped_DPAPI_vault_fields()
    {
        using var vault = new FakeCredentialVault();
        var tester = new CapturingTencentConnectionTester();
        var service = new TencentAsrSettingsService(vault, tester);
        var credentials = new TencentAsrCredentials(AppId, SecretId, SecretKey);

        await service.SaveAsync(credentials, CancellationToken.None);
        var status = await service.GetStatusAsync(CancellationToken.None);

        Assert.Equal("16k_zh", status.Options.EngineModelType);
        Assert.Equal(1, status.Options.VoiceFormat);
        Assert.True(status.Options.NeedVad);
        Assert.Equal(30_000, status.Options.MaxSpeakTimeMilliseconds);
        Assert.True(status.IsComplete);
        Assert.True(status.CanTestConnection);
        Assert.All(
            [status.AppId, status.SecretId, status.SecretKey],
            field =>
            {
                Assert.Equal(CredentialAvailability.Available, field.Availability);
                Assert.Equal("••••••••", field.Mask);
            });
        Assert.Equal(
            [
                TencentCredentialKeys.AppId,
                TencentCredentialKeys.SecretId,
                TencentCredentialKeys.SecretKey,
            ],
            vault.SavedKeys);

        var revealed = await service.RevealAsync(CancellationToken.None);
        Assert.Equal(credentials, revealed);
        Assert.DoesNotContain(SecretId, revealed!.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SecretKey, revealed.ToString(), StringComparison.Ordinal);

        await service.DeleteAsync(CancellationToken.None);

        Assert.Equal(("asr", "tencent_cloud_asr"), vault.LastDeletedOwner);
        Assert.False((await service.GetStatusAsync(CancellationToken.None)).IsComplete);
    }

    [Fact]
    public async Task Partial_or_unavailable_DPAPI_fields_never_enable_save_test_state()
    {
        using var vault = new FakeCredentialVault();
        var tester = new CapturingTencentConnectionTester();
        var service = new TencentAsrSettingsService(vault, tester);
        await vault.SaveAsync(TencentCredentialKeys.AppId, AppId);
        await vault.SaveAsync(TencentCredentialKeys.SecretId, SecretId);

        var partial = await service.GetStatusAsync(CancellationToken.None);
        var result = await service.TestConnectionAsync(CancellationToken.None);

        Assert.False(partial.IsComplete);
        Assert.False(partial.CanTestConnection);
        Assert.False(result.Succeeded);
        Assert.Equal(TencentConnectionTestError.IncompleteCredentials, result.Error);
        Assert.Equal(0, tester.CallCount);

        vault.SetUnavailable(TencentCredentialKeys.SecretId);
        Assert.False((await service.GetStatusAsync(CancellationToken.None)).IsComplete);
    }

    [Fact]
    public async Task Explicit_connection_test_reads_secrets_but_result_and_diagnostics_are_safe()
    {
        using var vault = new FakeCredentialVault();
        var tester = new CapturingTencentConnectionTester();
        var service = new TencentAsrSettingsService(vault, tester);
        await service.SaveAsync(
            new TencentAsrCredentials(AppId, SecretId, SecretKey),
            CancellationToken.None);

        var result = await service.TestConnectionAsync(CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.Equal(AppId, tester.Credentials?.AppId);
        Assert.Equal(SecretId, tester.Credentials?.SecretId);
        Assert.Equal(SecretKey, tester.Credentials?.SecretKey);
        Assert.DoesNotContain(AppId, result.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SecretId, result.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SecretKey, result.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void Signed_URL_uses_deterministic_clock_nonce_sorted_parameters_and_HMAC_SHA1()
    {
        var time = new ControlledTimeProvider(
            new DateTimeOffset(2026, 7, 11, 0, 0, 0, TimeSpan.Zero));
        var builder = new TencentSignedUrlBuilder(
            time,
            new FakeTencentNonceSource(7_654_321));

        var request = builder.Build(
            new TencentAsrCredentials(AppId, SecretId, SecretKey),
            TencentAsrOptions.Default,
            "fixture-voice-id");

        Assert.Equal(
            "wss://asr.cloud.tencent.com/asr/v2/1234567890?" +
            "engine_model_type=16k_zh&expired=1783814400&max_speak_time=30000&" +
            "needvad=1&nonce=7654321&secretid=fixture-secret-id&" +
            "timestamp=1783728000&voice_format=1&voice_id=fixture-voice-id&" +
            "signature=0kexfzha6CeBwV2I%2BNG%2BdfVn%2FLs%3D",
            request.ConnectUri.OriginalString);
        Assert.DoesNotContain(SecretKey, request.ConnectUri.OriginalString, StringComparison.Ordinal);
        Assert.DoesNotContain(AppId, request.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SecretId, request.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(SecretKey, request.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("signature", request.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Optional_hotword_list_is_signed_and_URL_encoded_without_entering_safe_diagnostics()
    {
        var time = new ControlledTimeProvider(
            new DateTimeOffset(2026, 7, 11, 0, 0, 0, TimeSpan.Zero));
        var builder = new TencentSignedUrlBuilder(
            time,
            new FakeTencentNonceSource(42));
        var options = TencentAsrOptions.Default with { HotwordList = "VoxFlow|10,语音识别|5" };

        var request = builder.Build(
            new TencentAsrCredentials(AppId, SecretId, SecretKey),
            options,
            "fixture-voice-id");

        Assert.Contains("hotword_list=VoxFlow%7C10%2C%E8%AF%AD%E9%9F%B3%E8%AF%86%E5%88%AB%7C5", request.ConnectUri.OriginalString, StringComparison.Ordinal);
        Assert.DoesNotContain(options.HotwordList, request.ToString(), StringComparison.Ordinal);
    }

    private sealed class FakeTencentNonceSource(int nonce) : ITencentNonceSource
    {
        public int NextNonce() => nonce;
    }

    private sealed class CapturingTencentConnectionTester : ITencentConnectionTester
    {
        public int CallCount { get; private set; }

        public TencentAsrCredentials? Credentials { get; private set; }

        public ValueTask<TencentConnectionTestResult> TestAsync(
            TencentAsrCredentials credentials,
            CancellationToken cancellationToken)
        {
            CallCount++;
            Credentials = credentials;
            return ValueTask.FromResult(TencentConnectionTestResult.Success);
        }
    }

    private sealed class FakeCredentialVault : ICredentialVault
    {
        private readonly Dictionary<CredentialKey, string> secrets = [];
        private readonly HashSet<CredentialKey> unavailable = [];

        public List<CredentialKey> SavedKeys { get; } = [];

        public (string OwnerKind, string OwnerId)? LastDeletedOwner { get; private set; }

        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default)
        {
            secrets[key] = secret;
            unavailable.Remove(key);
            SavedKeys.Add(key);
            return Task.CompletedTask;
        }

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            if (unavailable.Contains(key))
            {
                throw new CredentialUnavailableException();
            }

            return Task.FromResult(secrets.GetValueOrDefault(key));
        }

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(unavailable.Contains(key)
                ? new CredentialPresentation(CredentialAvailability.Unavailable, "••••••••")
                : secrets.ContainsKey(key)
                    ? new CredentialPresentation(CredentialAvailability.Available, "••••••••")
                    : new CredentialPresentation(CredentialAvailability.Missing, string.Empty));

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default)
        {
            secrets.Remove(key);
            unavailable.Remove(key);
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
                unavailable.Remove(key);
            }

            return Task.FromResult(keys.Length);
        }

        public void SetUnavailable(CredentialKey key) => unavailable.Add(key);

        public void Dispose()
        {
        }
    }
}
