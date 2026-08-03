using System.Security.Cryptography;

namespace VoxFlow.Windows.Infrastructure.Security;

public sealed class DpapiCurrentUserDataProtector : ICurrentUserDataProtector
{
    public byte[] Protect(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> entropy)
    {
        var plaintextBuffer = plaintext.ToArray();
        var entropyBuffer = entropy.ToArray();

        try
        {
            return ProtectedData.Protect(
                plaintextBuffer,
                entropyBuffer,
                DataProtectionScope.CurrentUser);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintextBuffer);
            CryptographicOperations.ZeroMemory(entropyBuffer);
        }
    }

    public byte[] Unprotect(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> entropy)
    {
        var ciphertextBuffer = ciphertext.ToArray();
        var entropyBuffer = entropy.ToArray();

        try
        {
            return ProtectedData.Unprotect(
                ciphertextBuffer,
                entropyBuffer,
                DataProtectionScope.CurrentUser);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(ciphertextBuffer);
            CryptographicOperations.ZeroMemory(entropyBuffer);
        }
    }
}
