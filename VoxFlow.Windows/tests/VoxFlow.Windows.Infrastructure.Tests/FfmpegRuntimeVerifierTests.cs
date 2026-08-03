using System.Security.Cryptography;
using System.Text.Json;
using VoxFlow.Windows.Infrastructure.Media;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class FfmpegRuntimeVerifierTests
{
    [Fact]
    public void Locator_uses_only_the_fixed_installation_subdirectory()
    {
        var locator = new FfmpegRuntimeLocator(@"C:\Program Files\VoxFlow");

        Assert.Equal(
            @"C:\Program Files\VoxFlow\runtime\ffmpeg",
            locator.RuntimeDirectory);
        Assert.Equal(
            @"C:\Program Files\VoxFlow\runtime\ffmpeg\ffmpeg.exe",
            locator.FfmpegPath);
        Assert.Equal(
            @"C:\Program Files\VoxFlow\runtime\ffmpeg\ffprobe.exe",
            locator.FfprobePath);
    }

    [Fact]
    public void Matching_manifest_size_hash_and_x64_pe_are_accepted()
    {
        using var fixture = new RuntimeFixture(machine: 0x8664);

        var result = new FfmpegRuntimeVerifier().Verify(fixture.RuntimeDirectory);

        Assert.True(result.IsValid);
        Assert.Null(result.Error);
    }

    [Theory]
    [InlineData(RuntimeMutation.MissingFile, FfmpegRuntimeVerificationError.MissingFile)]
    [InlineData(RuntimeMutation.SizeMismatch, FfmpegRuntimeVerificationError.SizeMismatch)]
    [InlineData(RuntimeMutation.HashMismatch, FfmpegRuntimeVerificationError.HashMismatch)]
    [InlineData(RuntimeMutation.X86Binary, FfmpegRuntimeVerificationError.ArchitectureMismatch)]
    [InlineData(RuntimeMutation.WrongRuntimeId, FfmpegRuntimeVerificationError.VersionMismatch)]
    [InlineData(RuntimeMutation.DuplicateFile, FfmpegRuntimeVerificationError.ManifestInvalid)]
    public void Corrupt_or_unapproved_runtime_fails_closed(
        RuntimeMutation mutation,
        FfmpegRuntimeVerificationError expected)
    {
        using var fixture = new RuntimeFixture(machine: 0x8664);
        fixture.Mutate(mutation);

        var result = new FfmpegRuntimeVerifier().Verify(fixture.RuntimeDirectory);

        Assert.False(result.IsValid);
        Assert.Equal(expected, result.Error);
    }

    public enum RuntimeMutation
    {
        MissingFile,
        SizeMismatch,
        HashMismatch,
        X86Binary,
        WrongRuntimeId,
        DuplicateFile,
    }

    private sealed class RuntimeFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly string ffmpegPath;
        private readonly string ffprobePath;

        public RuntimeFixture(ushort machine)
        {
            RuntimeDirectory = Path.Combine(directory.Path, "runtime", "ffmpeg");
            Directory.CreateDirectory(RuntimeDirectory);
            ffmpegPath = Path.Combine(RuntimeDirectory, "ffmpeg.exe");
            ffprobePath = Path.Combine(RuntimeDirectory, "ffprobe.exe");
            File.WriteAllBytes(ffmpegPath, CreatePe(machine, marker: 1));
            File.WriteAllBytes(ffprobePath, CreatePe(machine, marker: 2));
            WriteManifest(FfmpegRuntimeVerifier.ExpectedRuntimeId);
        }

        public string RuntimeDirectory { get; }

        public void Mutate(RuntimeMutation mutation)
        {
            switch (mutation)
            {
                case RuntimeMutation.MissingFile:
                    File.Delete(ffprobePath);
                    break;
                case RuntimeMutation.SizeMismatch:
                    using (var stream = File.OpenWrite(ffmpegPath))
                    {
                        stream.SetLength(stream.Length + 1);
                    }
                    break;
                case RuntimeMutation.HashMismatch:
                    var bytes = File.ReadAllBytes(ffmpegPath);
                    bytes[^1] ^= 0xff;
                    File.WriteAllBytes(ffmpegPath, bytes);
                    break;
                case RuntimeMutation.X86Binary:
                    File.WriteAllBytes(ffmpegPath, CreatePe(0x014c, marker: 1));
                    WriteManifest(FfmpegRuntimeVerifier.ExpectedRuntimeId);
                    break;
                case RuntimeMutation.WrongRuntimeId:
                    WriteManifest("unapproved-runtime");
                    break;
                case RuntimeMutation.DuplicateFile:
                    WriteManifest(FfmpegRuntimeVerifier.ExpectedRuntimeId, duplicateFfmpeg: true);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(mutation), mutation, null);
            }
        }

        public void Dispose() => directory.Dispose();

        private void WriteManifest(string runtimeId, bool duplicateFfmpeg = false)
        {
            var files = new List<object>
            {
                Describe(ffmpegPath),
                Describe(ffprobePath),
            };
            if (duplicateFfmpeg)
            {
                files.Add(Describe(ffmpegPath));
            }

            var manifest = new
            {
                schemaVersion = 1,
                runtimeId,
                architecture = "x64",
                files,
            };
            File.WriteAllText(
                Path.Combine(RuntimeDirectory, FfmpegRuntimeVerifier.ManifestFileName),
                JsonSerializer.Serialize(manifest));
        }

        private static object Describe(string path)
        {
            var bytes = File.ReadAllBytes(path);
            return new
            {
                path = Path.GetFileName(path),
                size = bytes.LongLength,
                sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
            };
        }

        private static byte[] CreatePe(ushort machine, byte marker)
        {
            var bytes = new byte[256];
            bytes[0] = (byte)'M';
            bytes[1] = (byte)'Z';
            BitConverter.GetBytes(0x80).CopyTo(bytes, 0x3c);
            bytes[0x80] = (byte)'P';
            bytes[0x81] = (byte)'E';
            BitConverter.GetBytes(machine).CopyTo(bytes, 0x84);
            bytes[^1] = marker;
            return bytes;
        }
    }
}
