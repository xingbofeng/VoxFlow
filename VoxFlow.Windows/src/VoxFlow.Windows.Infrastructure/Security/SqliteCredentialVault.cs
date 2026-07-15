using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Infrastructure.Persistence;

namespace VoxFlow.Windows.Infrastructure.Security;

public sealed class SqliteCredentialVault : ICredentialVault
{
    private const int CurrentProtectionVersion = 1;
    private const string CurrentUserScope = "CurrentUser";
    private const string FixedMask = "••••••••";
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly ICurrentUserDataProtector protector;
    private int disposed;

    public SqliteCredentialVault(
        SqliteConnectionFactory connectionFactory,
        ICurrentUserDataProtector protector)
    {
        ArgumentNullException.ThrowIfNull(connectionFactory);
        this.protector = protector ?? throw new ArgumentNullException(nameof(protector));
        transactionRunner = new SqliteTransactionRunner(connectionFactory);
    }

    public Task SaveAsync(
        CredentialKey key,
        string secret,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(key);
        ArgumentException.ThrowIfNullOrWhiteSpace(secret);
        cancellationToken.ThrowIfCancellationRequested();

        var plaintext = StrictUtf8.GetBytes(secret);
        var entropy = CreateEntropy(key, CurrentProtectionVersion);
        byte[]? ciphertext = null;

        try
        {
            try
            {
                ciphertext = protector.Protect(plaintext, entropy);
            }
            catch (CryptographicException)
            {
                throw new CredentialUnavailableException();
            }
            catch (PlatformNotSupportedException)
            {
                throw new CredentialUnavailableException();
            }

            if (ciphertext.Length == 0)
            {
                throw new CredentialUnavailableException();
            }

            transactionRunner.Write((connection, transaction) =>
            {
                Upsert(connection, transaction, key, ciphertext);
                return 0;
            });

            return Task.CompletedTask;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
            CryptographicOperations.ZeroMemory(entropy);
            if (ciphertext is not null)
            {
                CryptographicOperations.ZeroMemory(ciphertext);
            }
        }
    }

    public Task<string?> ReadSecretAsync(
        CredentialKey key,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(key);
        cancellationToken.ThrowIfCancellationRequested();

        var stored = ReadStoredCredential(key);
        if (stored is null)
        {
            return Task.FromResult<string?>(null);
        }

        var plaintext = Unprotect(key, stored);
        try
        {
            try
            {
                return Task.FromResult<string?>(StrictUtf8.GetString(plaintext));
            }
            catch (DecoderFallbackException)
            {
                throw new CredentialUnavailableException();
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public Task<CredentialPresentation> GetPresentationAsync(
        CredentialKey key,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(key);
        cancellationToken.ThrowIfCancellationRequested();

        var stored = ReadStoredCredential(key);
        if (stored is null)
        {
            return Task.FromResult(
                new CredentialPresentation(CredentialAvailability.Missing, string.Empty));
        }

        try
        {
            var plaintext = Unprotect(key, stored);
            CryptographicOperations.ZeroMemory(plaintext);
            return Task.FromResult(
                new CredentialPresentation(CredentialAvailability.Available, FixedMask));
        }
        catch (CredentialUnavailableException)
        {
            return Task.FromResult(
                new CredentialPresentation(CredentialAvailability.Unavailable, FixedMask));
        }
    }

    public Task DeleteAsync(
        CredentialKey key,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(key);
        cancellationToken.ThrowIfCancellationRequested();

        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "DELETE FROM credentials " +
                "WHERE owner_kind = $ownerKind AND owner_id = $ownerId " +
                "AND field_name = $fieldName;";
            AddKeyParameters(command, key);
            command.ExecuteNonQuery();
            return 0;
        });

        return Task.CompletedTask;
    }

    public Task<int> DeleteOwnerAsync(
        string ownerKind,
        string ownerId,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        ownerKind = NormalizeIdentity(ownerKind, nameof(ownerKind));
        ownerId = NormalizeIdentity(ownerId, nameof(ownerId));
        cancellationToken.ThrowIfCancellationRequested();

        var deleted = transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "DELETE FROM credentials " +
                "WHERE owner_kind = $ownerKind AND owner_id = $ownerId;";
            command.Parameters.AddWithValue("$ownerKind", ownerKind);
            command.Parameters.AddWithValue("$ownerId", ownerId);
            return command.ExecuteNonQuery();
        });

        return Task.FromResult(deleted);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0)
        {
            transactionRunner.Dispose();
        }
    }

    private static byte[] CreateEntropy(CredentialKey key, int protectionVersion)
    {
        var canonicalIdentity = string.Concat(
            "VoxFlow.Windows.CredentialVault\0",
            protectionVersion.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "\0",
            key.OwnerKind.Length.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ":",
            key.OwnerKind,
            "\0",
            key.OwnerId.Length.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ":",
            key.OwnerId,
            "\0",
            key.FieldName.Length.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ":",
            key.FieldName);
        var identityBytes = StrictUtf8.GetBytes(canonicalIdentity);

        try
        {
            return SHA256.HashData(identityBytes);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(identityBytes);
        }
    }

    private static string CreateCredentialId(CredentialKey key)
    {
        var identityBytes = StrictUtf8.GetBytes(string.Concat(
            key.OwnerKind,
            "\0",
            key.OwnerId,
            "\0",
            key.FieldName));

        try
        {
            return Convert.ToHexString(SHA256.HashData(identityBytes));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(identityBytes);
        }
    }

    private static void Upsert(
        SqliteConnection connection,
        SqliteTransaction transaction,
        CredentialKey key,
        byte[] ciphertext)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "INSERT INTO credentials(" +
            "credential_id, owner_kind, owner_id, field_name, scope, protection_version, " +
            "ciphertext, updated_at_unix_ms) " +
            "VALUES ($credentialId, $ownerKind, $ownerId, $fieldName, $scope, " +
            "$protectionVersion, $ciphertext, $updatedAt) " +
            "ON CONFLICT(owner_kind, owner_id, field_name) DO UPDATE SET " +
            "credential_id = excluded.credential_id, " +
            "scope = excluded.scope, " +
            "protection_version = excluded.protection_version, " +
            "ciphertext = excluded.ciphertext, " +
            "updated_at_unix_ms = excluded.updated_at_unix_ms;";
        command.Parameters.AddWithValue("$credentialId", CreateCredentialId(key));
        AddKeyParameters(command, key);
        command.Parameters.AddWithValue("$scope", CurrentUserScope);
        command.Parameters.AddWithValue("$protectionVersion", CurrentProtectionVersion);
        command.Parameters.Add("$ciphertext", SqliteType.Blob).Value = ciphertext;
        command.Parameters.AddWithValue(
            "$updatedAt",
            DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        command.ExecuteNonQuery();
    }

    private StoredCredential? ReadStoredCredential(CredentialKey key) =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT scope, protection_version, ciphertext FROM credentials " +
                "WHERE owner_kind = $ownerKind AND owner_id = $ownerId " +
                "AND field_name = $fieldName;";
            AddKeyParameters(command, key);
            using var reader = command.ExecuteReader();
            return reader.Read()
                ? new StoredCredential(
                    reader.GetString(0),
                    reader.GetInt32(1),
                    (byte[])reader.GetValue(2))
                : null;
        });

    private byte[] Unprotect(CredentialKey key, StoredCredential stored)
    {
        if (!string.Equals(stored.Scope, CurrentUserScope, StringComparison.Ordinal)
            || stored.ProtectionVersion != CurrentProtectionVersion)
        {
            CryptographicOperations.ZeroMemory(stored.Ciphertext);
            throw new CredentialUnavailableException();
        }

        var entropy = CreateEntropy(key, stored.ProtectionVersion);
        try
        {
            try
            {
                return protector.Unprotect(stored.Ciphertext, entropy);
            }
            catch (CryptographicException)
            {
                throw new CredentialUnavailableException();
            }
            catch (PlatformNotSupportedException)
            {
                throw new CredentialUnavailableException();
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(stored.Ciphertext);
            CryptographicOperations.ZeroMemory(entropy);
        }
    }

    private static void AddKeyParameters(SqliteCommand command, CredentialKey key)
    {
        command.Parameters.AddWithValue("$ownerKind", key.OwnerKind);
        command.Parameters.AddWithValue("$ownerId", key.OwnerId);
        command.Parameters.AddWithValue("$fieldName", key.FieldName);
    }

    private static string NormalizeIdentity(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        return value.Trim();
    }

    private void ThrowIfDisposed() =>
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);

    private sealed record StoredCredential(
        string Scope,
        int ProtectionVersion,
        byte[] Ciphertext);
}
