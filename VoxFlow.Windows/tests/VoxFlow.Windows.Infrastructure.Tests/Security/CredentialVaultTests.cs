using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Security;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Security;

public sealed class CredentialVaultTests
{
    private static readonly CredentialKey TencentSecretKey =
        new("asr", "tencent_cloud_asr", "secret_key");

    [Fact]
    public async Task Current_Windows_user_can_round_trip_DPAPI_while_storage_stays_ciphertext_only()
    {
        using var fixture = new CredentialFixture(new DpapiCurrentUserDataProtector());
        const string sensitiveValue = "sensitive fixture alpha 42";

        await fixture.Vault.SaveAsync(TencentSecretKey, sensitiveValue, CancellationToken.None);

        Assert.Equal(
            sensitiveValue,
            await fixture.Vault.ReadSecretAsync(TencentSecretKey, CancellationToken.None));
        Assert.Equal(
            new CredentialPresentation(CredentialAvailability.Available, "••••••••"),
            await fixture.Vault.GetPresentationAsync(
                TencentSecretKey,
                CancellationToken.None));

        var ciphertext = fixture.ReadCiphertext(TencentSecretKey);
        Assert.NotEmpty(ciphertext);
        Assert.False(ciphertext.AsSpan().SequenceEqual(Encoding.UTF8.GetBytes(sensitiveValue)));
        Assert.DoesNotContain(
            sensitiveValue,
            Encoding.UTF8.GetString(File.ReadAllBytes(fixture.DatabasePath)),
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Damaged_ciphertext_is_unavailable_and_never_echoes_plaintext_or_crypto_details()
    {
        using var fixture = new CredentialFixture(new DpapiCurrentUserDataProtector());
        const string sensitiveValue = "sensitive fixture beta 73";
        await fixture.Vault.SaveAsync(TencentSecretKey, sensitiveValue, CancellationToken.None);
        fixture.ReplaceCiphertext(TencentSecretKey, [1, 2, 3]);

        var presentation = await fixture.Vault.GetPresentationAsync(
            TencentSecretKey,
            CancellationToken.None);
        var exception = await Assert.ThrowsAsync<CredentialUnavailableException>(async () =>
            await fixture.Vault.ReadSecretAsync(TencentSecretKey, CancellationToken.None));

        Assert.Equal(CredentialAvailability.Unavailable, presentation.Availability);
        Assert.Equal("••••••••", presentation.Mask);
        Assert.DoesNotContain(sensitiveValue, exception.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("Crypt", exception.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Ciphertext_unreadable_by_another_user_context_is_reported_as_unavailable()
    {
        using var fixture = new CredentialFixture(new DpapiCurrentUserDataProtector());
        await fixture.Vault.SaveAsync(
            TencentSecretKey,
            "sensitive fixture gamma 19",
            CancellationToken.None);
        var otherUserVault = new SqliteCredentialVault(
            fixture.Factory,
            new AlwaysUnavailableProtector());

        var presentation = await otherUserVault.GetPresentationAsync(
            TencentSecretKey,
            CancellationToken.None);

        Assert.Equal(CredentialAvailability.Unavailable, presentation.Availability);
        await Assert.ThrowsAsync<CredentialUnavailableException>(async () =>
            await otherUserVault.ReadSecretAsync(TencentSecretKey, CancellationToken.None));
    }

    [Fact]
    public async Task Field_entropy_prevents_swapping_ciphertext_between_fields()
    {
        using var fixture = new CredentialFixture(new DpapiCurrentUserDataProtector());
        var appId = new CredentialKey("asr", "tencent_cloud_asr", "app_id");
        await fixture.Vault.SaveAsync(appId, "fixture app value", CancellationToken.None);
        await fixture.Vault.SaveAsync(
            TencentSecretKey,
            "fixture secret value",
            CancellationToken.None);

        fixture.SwapCiphertexts(appId, TencentSecretKey);

        Assert.Equal(
            CredentialAvailability.Unavailable,
            (await fixture.Vault.GetPresentationAsync(appId, CancellationToken.None)).Availability);
        Assert.Equal(
            CredentialAvailability.Unavailable,
            (await fixture.Vault.GetPresentationAsync(
                TencentSecretKey,
                CancellationToken.None)).Availability);
    }

    [Fact]
    public async Task Delete_is_idempotent_and_owner_delete_does_not_touch_other_providers()
    {
        using var fixture = new CredentialFixture(new DpapiCurrentUserDataProtector());
        var tencentAppId = new CredentialKey("asr", "tencent_cloud_asr", "app_id");
        var aliyunApiKey = new CredentialKey("asr", "aliyun_dashscope_asr", "api_key");
        await fixture.Vault.SaveAsync(tencentAppId, "fixture tencent app", CancellationToken.None);
        await fixture.Vault.SaveAsync(
            TencentSecretKey,
            "fixture tencent secret",
            CancellationToken.None);
        await fixture.Vault.SaveAsync(aliyunApiKey, "fixture aliyun value", CancellationToken.None);

        Assert.Equal(
            2,
            await fixture.Vault.DeleteOwnerAsync(
                "asr",
                "tencent_cloud_asr",
                CancellationToken.None));
        Assert.Equal(
            0,
            await fixture.Vault.DeleteOwnerAsync(
                "asr",
                "tencent_cloud_asr",
                CancellationToken.None));
        await fixture.Vault.DeleteAsync(TencentSecretKey, CancellationToken.None);

        Assert.Null(await fixture.Vault.ReadSecretAsync(tencentAppId, CancellationToken.None));
        Assert.Equal(
            "fixture aliyun value",
            await fixture.Vault.ReadSecretAsync(aliyunApiKey, CancellationToken.None));
    }

    [Theory]
    [InlineData("", "provider", "field")]
    [InlineData("owner", " ", "field")]
    [InlineData("owner", "provider", "")]
    public void Credential_keys_reject_blank_identity_parts(
        string ownerKind,
        string ownerId,
        string fieldName)
    {
        Assert.Throws<ArgumentException>(() =>
            new CredentialKey(ownerKind, ownerId, fieldName));
    }

    private sealed class CredentialFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();

        public CredentialFixture(ICurrentUserDataProtector protector)
        {
            DatabasePath = Path.Combine(directory.Path, "voxflow.db");
            new VoxFlowDatabaseMigrator().Migrate(DatabasePath);
            Factory = new SqliteConnectionFactory(DatabasePath, pooling: false);
            Vault = new SqliteCredentialVault(Factory, protector);
        }

        public string DatabasePath { get; }

        public SqliteConnectionFactory Factory { get; }

        public SqliteCredentialVault Vault { get; }

        public byte[] ReadCiphertext(CredentialKey key)
        {
            using var connection = Factory.Open();
            using var command = CredentialCommand(connection, key);
            command.CommandText =
                "SELECT ciphertext FROM credentials " +
                "WHERE owner_kind = $ownerKind AND owner_id = $ownerId AND field_name = $fieldName;";
            return (byte[])command.ExecuteScalar()!;
        }

        public void ReplaceCiphertext(CredentialKey key, byte[] ciphertext)
        {
            using var connection = Factory.Open();
            using var command = CredentialCommand(connection, key);
            command.CommandText =
                "UPDATE credentials SET ciphertext = $ciphertext " +
                "WHERE owner_kind = $ownerKind AND owner_id = $ownerId AND field_name = $fieldName;";
            command.Parameters.AddWithValue("$ciphertext", ciphertext);
            command.ExecuteNonQuery();
        }

        public void SwapCiphertexts(CredentialKey first, CredentialKey second)
        {
            var firstCiphertext = ReadCiphertext(first);
            var secondCiphertext = ReadCiphertext(second);
            ReplaceCiphertext(first, secondCiphertext);
            ReplaceCiphertext(second, firstCiphertext);
        }

        public void Dispose()
        {
            Vault.Dispose();
            directory.Dispose();
        }

        private static SqliteCommand CredentialCommand(
            SqliteConnection connection,
            CredentialKey key)
        {
            var command = connection.CreateCommand();
            command.Parameters.AddWithValue("$ownerKind", key.OwnerKind);
            command.Parameters.AddWithValue("$ownerId", key.OwnerId);
            command.Parameters.AddWithValue("$fieldName", key.FieldName);
            return command;
        }
    }

    private sealed class AlwaysUnavailableProtector : ICurrentUserDataProtector
    {
        public byte[] Protect(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> entropy) =>
            throw new CryptographicException();

        public byte[] Unprotect(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> entropy) =>
            throw new CryptographicException();
    }
}
