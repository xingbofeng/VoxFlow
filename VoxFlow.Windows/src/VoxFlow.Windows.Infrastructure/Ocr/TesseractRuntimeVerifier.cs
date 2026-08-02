using System.Security.Cryptography;
using System.Text.Json;

namespace VoxFlow.Windows.Infrastructure.Ocr;

public enum TesseractRuntimeVerificationError
{
    ManifestInvalid,
    VersionMismatch,
    ArchitectureMismatch,
    MissingFile,
    SizeMismatch,
    HashMismatch,
    MissingLanguage,
}

public sealed record TesseractRuntimeVerificationResult(
    bool IsValid,
    TesseractRuntimeVerificationError? Error,
    string? FileName = null,
    string? ExecutablePath = null,
    string? TessdataPath = null)
{
    public bool SupportsLanguage(string language) =>
        IsValid && TesseractRuntimeVerifier.RequiredLanguageModels.ContainsKey(language);
}

/// <summary>Only locates the OCR runtime supplied beside the installed app.
/// It deliberately has no PATH search or system-Tesseract fallback.</summary>
public sealed class TesseractRuntimeLocator
{
    public TesseractRuntimeLocator(string installationRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(installationRoot);
        RuntimeDirectory = Path.Combine(
            Path.GetFullPath(installationRoot),
            "runtime",
            "ocr");
    }

    public string RuntimeDirectory { get; }

    public string ExecutablePath => Path.Combine(RuntimeDirectory, "tesseract.exe");

    public string TessdataPath => Path.Combine(RuntimeDirectory, "tessdata");
}

public interface ITesseractRuntimeVerifier
{
    TesseractRuntimeVerificationResult Verify(string runtimeDirectory);
}

/// <summary>Fail-closed verifier for the self-contained x64 Tesseract and the
/// five fixed tessdata_fast models selected in the OpenSpec supply-chain
/// evidence. A missing manifest, any altered file, or a PATH-only install is
/// unavailable to the Agent.</summary>
public sealed class TesseractRuntimeVerifier : ITesseractRuntimeVerifier
{
    public const string ManifestFileName = "TESSERACT_RUNTIME_MANIFEST.json";
    public const string ExpectedRuntimeId =
        "tesseract-5.5.2-vcpkg-03e366fb-x64-static";

    public static IReadOnlyDictionary<string, TesseractLanguageModel> RequiredLanguageModels { get; } =
        new Dictionary<string, TesseractLanguageModel>(StringComparer.Ordinal)
        {
            ["eng"] = new("tessdata/eng.traineddata", 4_113_088,
                "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"),
            ["chi_sim"] = new("tessdata/chi_sim.traineddata", 2_469_156,
                "a5fcb6f0db1e1d6d8522f39db4e848f05984669172e584e8d76b6b3141e1f730"),
            ["chi_tra"] = new("tessdata/chi_tra.traineddata", 2_366_642,
                "529c5b5797d64b126065cd55f2bb4c7fd7b15790798091b1ff259941a829330b"),
            ["jpn"] = new("tessdata/jpn.traineddata", 2_471_260,
                "1f5de9236d2e85f5fdf4b3c500f2d4926f8d9449f28f5394472d9e8d83b91b4d"),
            ["kor"] = new("tessdata/kor.traineddata", 1_677_415,
                "6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2"),
        };

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly IReadOnlyDictionary<string, TesseractLanguageModel> requiredLanguageModels;

    public TesseractRuntimeVerifier(
        IReadOnlyDictionary<string, TesseractLanguageModel>? requiredLanguageModels = null)
    {
        this.requiredLanguageModels = requiredLanguageModels ?? RequiredLanguageModels;
        if (this.requiredLanguageModels.Count == 0
            || this.requiredLanguageModels.Any(pair => string.IsNullOrWhiteSpace(pair.Key)
                || !IsSafeRelativePath(pair.Value.Path)
                || pair.Value.Size <= 0
                || !IsSha256(pair.Value.Sha256)))
        {
            throw new ArgumentException("A fixed OCR language manifest is required.", nameof(requiredLanguageModels));
        }
    }

    public TesseractRuntimeVerificationResult Verify(string runtimeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runtimeDirectory);
        var root = Path.GetFullPath(runtimeDirectory);
        TesseractRuntimeManifest manifest;
        try
        {
            manifest = JsonSerializer.Deserialize<TesseractRuntimeManifest>(
                File.ReadAllText(Path.Combine(root, ManifestFileName)),
                SerializerOptions) ?? throw new JsonException("OCR runtime manifest is empty.");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return Invalid(TesseractRuntimeVerificationError.ManifestInvalid, ManifestFileName);
        }

        if (manifest.SchemaVersion != 1
            || !string.Equals(manifest.RuntimeId, ExpectedRuntimeId, StringComparison.Ordinal)
            || !string.Equals(manifest.Version, "5.5.2", StringComparison.Ordinal)
            || !string.Equals(manifest.Architecture, "x64", StringComparison.Ordinal)
            || !string.Equals(manifest.Binary, "tesseract.exe", StringComparison.OrdinalIgnoreCase)
            || manifest.Files is null
            || manifest.Languages is null)
        {
            return Invalid(TesseractRuntimeVerificationError.VersionMismatch);
        }

        if (!HasSafeUniqueFiles(manifest.Files))
        {
            return Invalid(TesseractRuntimeVerificationError.ManifestInvalid);
        }

        var files = manifest.Files.ToDictionary(file => file.Path, StringComparer.OrdinalIgnoreCase);
        if (!files.ContainsKey(manifest.Binary)
            || !files.ContainsKey("LICENSE.txt")
            || !IsExactLanguageSet(manifest.Languages))
        {
            return Invalid(TesseractRuntimeVerificationError.MissingLanguage);
        }

        foreach (var language in manifest.Languages)
        {
            var expected = requiredLanguageModels[language.Language];
            if (!string.Equals(language.Path, expected.Path, StringComparison.Ordinal)
                || language.Size != expected.Size
                || !string.Equals(language.Sha256, expected.Sha256, StringComparison.OrdinalIgnoreCase)
                || !files.TryGetValue(language.Path, out var file)
                || file.Size != language.Size
                || !string.Equals(file.Sha256, language.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                return Invalid(TesseractRuntimeVerificationError.ManifestInvalid, language.Path);
            }
        }

        foreach (var file in manifest.Files)
        {
            var path = Path.Combine(root, file.Path.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(path))
            {
                return Invalid(TesseractRuntimeVerificationError.MissingFile, file.Path);
            }
            var info = new FileInfo(path);
            if (info.Length != file.Size)
            {
                return Invalid(TesseractRuntimeVerificationError.SizeMismatch, file.Path);
            }
            if (!HashMatches(path, file.Sha256))
            {
                return Invalid(TesseractRuntimeVerificationError.HashMismatch, file.Path);
            }
        }

        var binaryPath = Path.Combine(root, manifest.Binary);
        if (!IsX64PortableExecutable(binaryPath))
        {
            return Invalid(TesseractRuntimeVerificationError.ArchitectureMismatch, manifest.Binary);
        }

        return new(true, null, null, binaryPath, Path.Combine(root, "tessdata"));
    }

    private static bool HasSafeUniqueFiles(IReadOnlyList<TesseractRuntimeFile> files) =>
        files.Count > 0
        && files.All(file => IsSafeRelativePath(file.Path) && file.Size > 0 && IsSha256(file.Sha256))
        && files.GroupBy(file => file.Path, StringComparer.OrdinalIgnoreCase).All(group => group.Count() == 1);

    private bool IsExactLanguageSet(IReadOnlyList<TesseractRuntimeLanguage> languages) =>
        languages.Count == requiredLanguageModels.Count
        && languages.Select(language => language.Language).Distinct(StringComparer.Ordinal).Count() == languages.Count
        && languages.All(language => requiredLanguageModels.ContainsKey(language.Language));

    private static bool IsSafeRelativePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path))
        {
            return false;
        }
        var normalized = path.Replace('\\', '/');
        return !normalized.StartsWith("../", StringComparison.Ordinal)
            && !normalized.Contains("/../", StringComparison.Ordinal)
            && !normalized.Contains(':');
    }

    private static bool IsSha256(string? value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);

    private static bool HashMatches(string path, string expected)
    {
        try
        {
            using var stream = File.OpenRead(path);
            return string.Equals(
                Convert.ToHexString(SHA256.HashData(stream)),
                expected,
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

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
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or EndOfStreamException)
        {
            return false;
        }
    }

    private static TesseractRuntimeVerificationResult Invalid(
        TesseractRuntimeVerificationError error,
        string? fileName = null) => new(false, error, fileName);

    public sealed record TesseractLanguageModel(string Path, long Size, string Sha256);

    private sealed record TesseractRuntimeManifest(
        int SchemaVersion,
        string RuntimeId,
        string Version,
        string Architecture,
        string Binary,
        IReadOnlyList<TesseractRuntimeFile> Files,
        IReadOnlyList<TesseractRuntimeLanguage> Languages);

    private sealed record TesseractRuntimeFile(string Path, long Size, string Sha256);

    private sealed record TesseractRuntimeLanguage(string Language, string Path, long Size, string Sha256);
}

/// <summary>Maps the current recognition/UI language to the only bundled OCR
/// models. English is always included for mixed technical text; unknown
/// locales never trigger a system-data or PATH lookup.</summary>
public static class TesseractLanguageSelector
{
    public static string Select(string? language) => language?.Trim().ToLowerInvariant() switch
    {
        var value when value is not null && (value.StartsWith("zh-hant", StringComparison.Ordinal)
            || value.StartsWith("zh-tw", StringComparison.Ordinal)
            || value.StartsWith("zh-hk", StringComparison.Ordinal)) => "chi_tra",
        var value when value is not null && value.StartsWith("zh", StringComparison.Ordinal) => "chi_sim",
        var value when value is not null && value.StartsWith("ja", StringComparison.Ordinal) => "jpn",
        var value when value is not null && value.StartsWith("ko", StringComparison.Ordinal) => "kor",
        _ => "eng",
    };

    public static string SelectWithEnglish(string? language)
    {
        var primary = Select(language);
        return primary == "eng" ? primary : primary + "+eng";
    }
}
