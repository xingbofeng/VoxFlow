using System.Diagnostics;
using System.Security.Cryptography;

namespace VoxFlow.Windows.Application.Agent;

public sealed class BuiltinAgentBinaryDescriptor
{
    public BuiltinAgentBinaryDescriptor(string absolutePath, string sha256)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(sha256);
        if (!Path.IsPathFullyQualified(absolutePath))
        {
            throw new ArgumentException("The sidecar path must be absolute.", nameof(absolutePath));
        }
        if (sha256.Length != 64 || !sha256.All(Uri.IsHexDigit))
        {
            throw new ArgumentException("A SHA-256 digest is required.", nameof(sha256));
        }

        AbsolutePath = Path.GetFullPath(absolutePath);
        Sha256 = sha256.ToUpperInvariant();
    }

    public string AbsolutePath { get; }

    public string Sha256 { get; }
}

/// <summary>
/// Constructs the only permitted sidecar launch configuration. It rejects a
/// missing or tampered binary before launch and never puts request/provider
/// data in argv or environment; callers serialize the request to stdin.
/// </summary>
public sealed class BuiltinAgentProcessSpecification
{
    private readonly BuiltinAgentBinaryDescriptor binary;

    public BuiltinAgentProcessSpecification(BuiltinAgentBinaryDescriptor binary)
    {
        this.binary = binary ?? throw new ArgumentNullException(nameof(binary));
    }

    public ProcessStartInfo CreateStartInfo(BuiltinAgentSidecarRunRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        VerifyBinary();
        return new ProcessStartInfo
        {
            FileName = binary.AbsolutePath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
    }

    private void VerifyBinary()
    {
        if (!File.Exists(binary.AbsolutePath))
        {
            throw new InvalidOperationException("The built-in Agent binary is unavailable.");
        }

        using var stream = File.OpenRead(binary.AbsolutePath);
        var hash = Convert.ToHexString(SHA256.HashData(stream));
        if (!CryptographicOperations.FixedTimeEquals(
                Convert.FromHexString(hash),
                Convert.FromHexString(binary.Sha256)))
        {
            throw new InvalidOperationException("The built-in Agent binary verification failed.");
        }
    }
}
