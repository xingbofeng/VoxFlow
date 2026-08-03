using System.Security.Cryptography;
using System.Text.Json;

namespace VoxFlow.Windows.Infrastructure.Media;

public enum FfmpegRuntimeVerificationError
{
    ManifestInvalid,
    VersionMismatch,
    ArchitectureMismatch,
    MissingFile,
    SizeMismatch,
    HashMismatch,
}

public sealed record FfmpegRuntimeVerificationResult(
    bool IsValid,
    FfmpegRuntimeVerificationError? Error,
    string? FileName = null);

public sealed class FfmpegRuntimeLocator
{
    public FfmpegRuntimeLocator(string installationRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(installationRoot);
        RuntimeDirectory = Path.Combine(
            Path.GetFullPath(installationRoot),
            "runtime",
            "ffmpeg");
    }

    public string RuntimeDirectory { get; }

    public string FfmpegPath => Path.Combine(RuntimeDirectory, "ffmpeg.exe");

    public string FfprobePath => Path.Combine(RuntimeDirectory, "ffprobe.exe");
}

public interface IFfmpegRuntimeVerifier
{
    FfmpegRuntimeVerificationResult Verify(string runtimeDirectory);
}

public sealed class FfmpegRuntimeVerifier : IFfmpegRuntimeVerifier
{
    public const string ManifestFileName = "FFMPEG_RUNTIME_MANIFEST.json";
    public const string ExpectedRuntimeId =
        "devenvy-ffmpeg-lgpl-8.0.1.4-win-x64";

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    public FfmpegRuntimeVerificationResult Verify(string runtimeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runtimeDirectory);
        var fullRuntimeDirectory = Path.GetFullPath(runtimeDirectory);
        var manifestPath = Path.Combine(fullRuntimeDirectory, ManifestFileName);
        FfmpegRuntimeManifest manifest;
        try
        {
            var json = File.ReadAllText(manifestPath);
            manifest = JsonSerializer.Deserialize<FfmpegRuntimeManifest>(json, SerializerOptions)
                ?? throw new JsonException("FFmpeg manifest is empty.");
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return Invalid(FfmpegRuntimeVerificationError.ManifestInvalid, ManifestFileName);
        }

        if (manifest.SchemaVersion != 1 ||
            !string.Equals(manifest.RuntimeId, ExpectedRuntimeId, StringComparison.Ordinal))
        {
            return Invalid(FfmpegRuntimeVerificationError.VersionMismatch);
        }

        if (!string.Equals(manifest.Architecture, "x64", StringComparison.Ordinal) ||
            manifest.Files is null ||
            manifest.Files.Count == 0)
        {
            return Invalid(FfmpegRuntimeVerificationError.ArchitectureMismatch);
        }

        if (manifest.Files.Any(entry =>
                !IsSafeFileName(entry.Path) || entry.Size <= 0 || !IsSha256(entry.Sha256)) ||
            manifest.Files
                .GroupBy(entry => entry.Path, StringComparer.OrdinalIgnoreCase)
                .Any(group => group.Count() != 1))
        {
            return Invalid(FfmpegRuntimeVerificationError.ManifestInvalid);
        }

        var fileEntries = manifest.Files.ToDictionary(file => file.Path, StringComparer.OrdinalIgnoreCase);
        if (!fileEntries.ContainsKey("ffmpeg.exe") || !fileEntries.ContainsKey("ffprobe.exe"))
        {
            return Invalid(FfmpegRuntimeVerificationError.ManifestInvalid);
        }

        foreach (var entry in manifest.Files)
        {
            var filePath = Path.Combine(fullRuntimeDirectory, entry.Path);
            if (!File.Exists(filePath))
            {
                return Invalid(FfmpegRuntimeVerificationError.MissingFile, entry.Path);
            }

            var fileInfo = new FileInfo(filePath);
            if (fileInfo.Length != entry.Size)
            {
                return Invalid(FfmpegRuntimeVerificationError.SizeMismatch, entry.Path);
            }

            string actualHash;
            try
            {
                using var stream = File.OpenRead(filePath);
                actualHash = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                return Invalid(FfmpegRuntimeVerificationError.MissingFile, entry.Path);
            }

            if (!string.Equals(actualHash, entry.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                return Invalid(FfmpegRuntimeVerificationError.HashMismatch, entry.Path);
            }

            if (!IsX64PortableExecutable(filePath))
            {
                return Invalid(FfmpegRuntimeVerificationError.ArchitectureMismatch, entry.Path);
            }
        }

        return new FfmpegRuntimeVerificationResult(true, null);
    }

    private static bool IsSafeFileName(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        !Path.IsPathRooted(path) &&
        string.Equals(path, Path.GetFileName(path), StringComparison.Ordinal);

    private static bool IsSha256(string? value) =>
        value is { Length: 64 } && value.All(Uri.IsHexDigit);

    private static bool IsX64PortableExecutable(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            using var reader = new BinaryReader(stream);
            if (stream.Length < 0x86 || reader.ReadUInt16() != 0x5a4d)
            {
                return false;
            }

            stream.Position = 0x3c;
            var peOffset = reader.ReadInt32();
            if (peOffset < 0 || peOffset > stream.Length - 6)
            {
                return false;
            }

            stream.Position = peOffset;
            return reader.ReadUInt32() == 0x00004550 && reader.ReadUInt16() == 0x8664;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or EndOfStreamException)
        {
            return false;
        }
    }

    private static FfmpegRuntimeVerificationResult Invalid(
        FfmpegRuntimeVerificationError error,
        string? fileName = null) => new(false, error, fileName);

    private sealed record FfmpegRuntimeManifest(
        int SchemaVersion,
        string RuntimeId,
        string Architecture,
        IReadOnlyList<FfmpegRuntimeFile> Files);

    private sealed record FfmpegRuntimeFile(string Path, long Size, string Sha256);
}
