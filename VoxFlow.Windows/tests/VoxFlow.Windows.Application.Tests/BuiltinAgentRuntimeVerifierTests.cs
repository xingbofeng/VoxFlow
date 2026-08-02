using System.Security.Cryptography;
using System.Text.Json;
using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

[CollectionDefinition("ProcessEnvironment", DisableParallelization = true)]
public sealed class ProcessEnvironmentCollection;

[Collection("ProcessEnvironment")]
public sealed class BuiltinAgentRuntimeVerifierTests
{
    [Fact]
    public void Verifies_only_the_bundled_manifest_binary_and_detects_tampering()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var runtime = Path.Combine(root, BuiltinAgentRuntimeVerifier.RuntimeRelativePath);
        Directory.CreateDirectory(runtime);
        try
        {
            var binary = Path.Combine(runtime, "voxflow-agent.exe");
            File.WriteAllText(binary, "sidecar");
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(binary)));
            File.WriteAllText(Path.Combine(runtime, BuiltinAgentRuntimeVerifier.ManifestFileName),
                JsonSerializer.Serialize(new
                {
                    schemaVersion = 1,
                    runtimeId = "voxflow-agent",
                    version = "0.1.0",
                    architecture = "x64",
                    target = "x86_64-pc-windows-msvc",
                    binary = "voxflow-agent.exe",
                    size = new FileInfo(binary).Length,
                    sha256 = hash,
                }));

            var verifier = new BuiltinAgentRuntimeVerifier();
            var valid = verifier.Verify(root);
            Assert.True(valid.IsAvailable);
            Assert.Equal("0.1.0", valid.Version);
            Assert.Equal(hash, valid.ExpectedSha256);
            Assert.Equal(Path.GetFullPath(binary), valid.Binary?.AbsolutePath);

            File.WriteAllText(binary, "tampered");
            var tampered = verifier.Verify(root);
            Assert.Equal(BuiltinAgentRuntimeAvailability.HashMismatch, tampered.Availability);
            Assert.Equal(hash, tampered.ExpectedSha256);
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void Missing_bundled_binary_never_falls_back_to_PATH()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var runtime = Path.Combine(root, BuiltinAgentRuntimeVerifier.RuntimeRelativePath);
        var poisonedPath = Path.Combine(root, "poisoned-path");
        Directory.CreateDirectory(runtime);
        Directory.CreateDirectory(poisonedPath);
        var previousPath = Environment.GetEnvironmentVariable("PATH");
        try
        {
            var poison = Path.Combine(poisonedPath, "voxflow-agent.exe");
            File.WriteAllText(poison, "path poison");
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(poison)));
            File.WriteAllText(Path.Combine(runtime, BuiltinAgentRuntimeVerifier.ManifestFileName),
                JsonSerializer.Serialize(new
                {
                    schemaVersion = 1,
                    runtimeId = "voxflow-agent",
                    version = "0.1.0",
                    architecture = "x64",
                    target = "x86_64-pc-windows-msvc",
                    binary = "voxflow-agent.exe",
                    size = new FileInfo(poison).Length,
                    sha256 = hash,
                }));
            Environment.SetEnvironmentVariable(
                "PATH",
                poisonedPath + Path.PathSeparator + previousPath);

            var result = new BuiltinAgentRuntimeVerifier().Verify(root);

            Assert.Equal(BuiltinAgentRuntimeAvailability.Missing, result.Availability);
            Assert.Null(result.Binary);
            Assert.Equal(hash, result.ExpectedSha256);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PATH", previousPath);
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void Size_mismatch_fails_closed_before_launch()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var runtime = Path.Combine(root, BuiltinAgentRuntimeVerifier.RuntimeRelativePath);
        Directory.CreateDirectory(runtime);
        try
        {
            var binary = Path.Combine(runtime, "voxflow-agent.exe");
            File.WriteAllText(binary, "sidecar");
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(binary)));
            File.WriteAllText(Path.Combine(runtime, BuiltinAgentRuntimeVerifier.ManifestFileName),
                JsonSerializer.Serialize(new
                {
                    schemaVersion = 1,
                    runtimeId = "voxflow-agent",
                    version = "0.1.0",
                    architecture = "x64",
                    target = "x86_64-pc-windows-msvc",
                    binary = "voxflow-agent.exe",
                    size = new FileInfo(binary).Length + 1,
                    sha256 = hash,
                }));

            var result = new BuiltinAgentRuntimeVerifier().Verify(root);

            Assert.Equal(BuiltinAgentRuntimeAvailability.HashMismatch, result.Availability);
            Assert.Null(result.Binary);
        }
        finally { Directory.Delete(root, true); }
    }
}
