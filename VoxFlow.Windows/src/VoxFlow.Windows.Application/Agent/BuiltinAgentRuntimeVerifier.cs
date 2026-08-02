using System.Security.Cryptography;
using System.Text.Json;

namespace VoxFlow.Windows.Application.Agent;

public enum BuiltinAgentRuntimeAvailability
{
    Available,
    Missing,
    ManifestInvalid,
    HashMismatch,
}

public sealed record BuiltinAgentRuntimeStatus(
    BuiltinAgentRuntimeAvailability Availability,
    string? Version,
    BuiltinAgentBinaryDescriptor? Binary)
{
    public bool IsAvailable => Availability == BuiltinAgentRuntimeAvailability.Available;

    /// <summary>
    /// The digest declared by the signed installation manifest. This is kept
    /// for diagnostics even when verification fails; it is never an approval
    /// to launch an unverified executable.
    /// </summary>
    public string? ExpectedSha256 { get; init; }
}

/// <summary>Verifies the one bundled sidecar from its controlled installation
/// manifest. It never searches PATH or accepts a caller-provided executable
/// path.</summary>
public sealed class BuiltinAgentRuntimeVerifier
{
    public static string RuntimeRelativePath { get; } = Path.Combine("runtime", "agent");
    public const string ManifestFileName = "VOXFLOW_AGENT_RUNTIME_MANIFEST.json";

    public BuiltinAgentRuntimeStatus Verify(string installationRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(installationRoot);
        var runtimeRoot = Path.Combine(Path.GetFullPath(installationRoot), RuntimeRelativePath);
        RuntimeManifest? manifest;
        try
        {
            manifest = JsonSerializer.Deserialize<RuntimeManifest>(
                File.ReadAllText(Path.Combine(runtimeRoot, ManifestFileName)),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return new(BuiltinAgentRuntimeAvailability.ManifestInvalid, null, null);
        }

        if (manifest is null || manifest.SchemaVersion != 1 ||
            !string.Equals(manifest.RuntimeId, "voxflow-agent", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(manifest.Version) ||
            !string.Equals(manifest.Architecture, "x64", StringComparison.Ordinal) ||
            !string.Equals(manifest.Target, "x86_64-pc-windows-msvc", StringComparison.Ordinal) ||
            !string.Equals(manifest.Binary, "voxflow-agent.exe", StringComparison.OrdinalIgnoreCase) ||
            manifest.Size <= 0 ||
            manifest.Sha256 is not { Length: 64 } || !manifest.Sha256.All(Uri.IsHexDigit))
        {
            return new(BuiltinAgentRuntimeAvailability.ManifestInvalid, null, null);
        }

        var binaryPath = Path.Combine(runtimeRoot, manifest.Binary);
        if (!File.Exists(binaryPath))
        {
            return new(BuiltinAgentRuntimeAvailability.Missing, manifest.Version, null)
            {
                ExpectedSha256 = manifest.Sha256,
            };
        }
        if (new FileInfo(binaryPath).Length != manifest.Size)
        {
            return new(BuiltinAgentRuntimeAvailability.HashMismatch, manifest.Version, null)
            {
                ExpectedSha256 = manifest.Sha256,
            };
        }
        using var stream = File.OpenRead(binaryPath);
        var actualHash = Convert.ToHexString(SHA256.HashData(stream));
        if (!string.Equals(actualHash, manifest.Sha256, StringComparison.OrdinalIgnoreCase))
        {
            return new(BuiltinAgentRuntimeAvailability.HashMismatch, manifest.Version, null)
            {
                ExpectedSha256 = manifest.Sha256,
            };
        }

        return new(BuiltinAgentRuntimeAvailability.Available, manifest.Version,
            new BuiltinAgentBinaryDescriptor(binaryPath, manifest.Sha256))
        {
            ExpectedSha256 = manifest.Sha256,
        };
    }

    private sealed record RuntimeManifest(
        int SchemaVersion,
        string RuntimeId,
        string Version,
        string Architecture,
        string Target,
        string Binary,
        long Size,
        string Sha256);
}
