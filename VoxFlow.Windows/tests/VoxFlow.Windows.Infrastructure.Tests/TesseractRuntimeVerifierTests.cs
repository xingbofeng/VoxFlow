using System.Security.Cryptography;
using System.Text.Json;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class TesseractRuntimeVerifierTests
{
    [Fact]
    public void Fixed_five_tessdata_fast_models_match_the_recorded_supply_chain_manifest()
    {
        Assert.Equal(
            new[] { "chi_sim", "chi_tra", "eng", "jpn", "kor" },
            TesseractRuntimeVerifier.RequiredLanguageModels.Keys.OrderBy(value => value));
        Assert.Equal(
            "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
            TesseractRuntimeVerifier.RequiredLanguageModels["eng"].Sha256);
        Assert.Equal(4_113_088, TesseractRuntimeVerifier.RequiredLanguageModels["eng"].Size);
    }

    [Fact]
    public void Locator_uses_only_the_controlled_runtime_ocr_directory()
    {
        var locator = new TesseractRuntimeLocator(@"C:\Program Files\VoxFlow");

        Assert.Equal(@"C:\Program Files\VoxFlow\runtime\ocr", locator.RuntimeDirectory);
        Assert.Equal(@"C:\Program Files\VoxFlow\runtime\ocr\tesseract.exe", locator.ExecutablePath);
        Assert.Equal(@"C:\Program Files\VoxFlow\runtime\ocr\tessdata", locator.TessdataPath);
    }

    [Fact]
    public void Missing_runtime_tree_is_manifest_invalid_without_path_fallback()
    {
        using var directory = new TemporaryDirectory();
        var locator = new TesseractRuntimeLocator(directory.Path);

        var result = new TesseractRuntimeVerifier().Verify(locator.RuntimeDirectory);

        Assert.False(result.IsValid);
        Assert.Equal(TesseractRuntimeVerificationError.ManifestInvalid, result.Error);
        Assert.Null(result.ExecutablePath);
        Assert.Null(result.TessdataPath);
        Assert.Equal(
            Path.Combine(directory.Path, "runtime", "ocr"),
            locator.RuntimeDirectory);
        Assert.False(File.Exists(locator.ExecutablePath));
    }

    [Theory]
    [InlineData("zh-Hans", "chi_sim+eng")]
    [InlineData("zh-Hant", "chi_tra+eng")]
    [InlineData("ja-JP", "jpn+eng")]
    [InlineData("ko-KR", "kor+eng")]
    [InlineData("en-US", "eng")]
    [InlineData(null, "eng")]
    public void Selects_only_a_bundled_model_plus_english_for_current_language(
        string? language,
        string expected)
    {
        Assert.Equal(expected, TesseractLanguageSelector.SelectWithEnglish(language));
    }

    [Theory]
    [InlineData(RuntimeMutation.None, true, null)]
    [InlineData(RuntimeMutation.MissingModel, false, TesseractRuntimeVerificationError.MissingFile)]
    [InlineData(RuntimeMutation.ModelTampered, false, TesseractRuntimeVerificationError.HashMismatch)]
    [InlineData(RuntimeMutation.WrongArchitecture, false, TesseractRuntimeVerificationError.ArchitectureMismatch)]
    [InlineData(RuntimeMutation.UnapprovedLanguage, false, TesseractRuntimeVerificationError.MissingLanguage)]
    [InlineData(RuntimeMutation.PathEscape, false, TesseractRuntimeVerificationError.ManifestInvalid)]
    public void Controlled_manifest_hashes_languages_and_x64_binary_fail_closed(
        RuntimeMutation mutation,
        bool expectedValid,
        TesseractRuntimeVerificationError? expectedError)
    {
        using var fixture = new RuntimeFixture();
        fixture.Mutate(mutation);

        var result = fixture.Verifier.Verify(fixture.RuntimeDirectory);

        Assert.Equal(expectedValid, result.IsValid);
        Assert.Equal(expectedError, result.Error);
        if (expectedValid)
        {
            Assert.Equal(Path.Combine(fixture.RuntimeDirectory, "tesseract.exe"), result.ExecutablePath);
            Assert.Equal(Path.Combine(fixture.RuntimeDirectory, "tessdata"), result.TessdataPath);
        }
    }

    public enum RuntimeMutation
    {
        None,
        MissingModel,
        ModelTampered,
        WrongArchitecture,
        UnapprovedLanguage,
        PathEscape,
    }

    private sealed class RuntimeFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly string binary;
        private readonly string model;
        private readonly IReadOnlyDictionary<string, TesseractRuntimeVerifier.TesseractLanguageModel> models;

        public RuntimeFixture()
        {
            RuntimeDirectory = Path.Combine(directory.Path, "runtime", "ocr");
            Directory.CreateDirectory(Path.Combine(RuntimeDirectory, "tessdata"));
            binary = Path.Combine(RuntimeDirectory, "tesseract.exe");
            model = Path.Combine(RuntimeDirectory, "tessdata", "fixture.traineddata");
            File.WriteAllBytes(binary, CreatePe(0x8664));
            File.WriteAllText(Path.Combine(RuntimeDirectory, "LICENSE.txt"), "Apache-2.0 fixture");
            File.WriteAllText(model, "traineddata fixture");
            models = new Dictionary<string, TesseractRuntimeVerifier.TesseractLanguageModel>
            {
                ["fixture"] = Describe(model, "tessdata/fixture.traineddata"),
            };
            Verifier = new TesseractRuntimeVerifier(models);
            WriteManifest();
        }

        public string RuntimeDirectory { get; }

        public TesseractRuntimeVerifier Verifier { get; }

        public void Mutate(RuntimeMutation mutation)
        {
            switch (mutation)
            {
                case RuntimeMutation.None:
                    return;
                case RuntimeMutation.MissingModel:
                    File.Delete(model);
                    return;
                case RuntimeMutation.ModelTampered:
                    var bytes = File.ReadAllBytes(model);
                    bytes[^1] ^= 0xff;
                    File.WriteAllBytes(model, bytes);
                    return;
                case RuntimeMutation.WrongArchitecture:
                    File.WriteAllBytes(binary, CreatePe(0x014c));
                    WriteManifest();
                    return;
                case RuntimeMutation.UnapprovedLanguage:
                    WriteManifest(language: "unapproved");
                    return;
                case RuntimeMutation.PathEscape:
                    WriteManifest(path: "../escape.traineddata");
                    return;
                default:
                    throw new ArgumentOutOfRangeException(nameof(mutation), mutation, null);
            }
        }

        public void Dispose() => directory.Dispose();

        private void WriteManifest(string? language = null, string? path = null)
        {
            var modelPath = path ?? "tessdata/fixture.traineddata";
            var modelEntry = Describe(model, modelPath);
            var files = new[]
            {
                Describe(binary, "tesseract.exe"),
                Describe(Path.Combine(RuntimeDirectory, "LICENSE.txt"), "LICENSE.txt"),
                modelEntry,
            };
            var manifest = new
            {
                schemaVersion = 1,
                runtimeId = TesseractRuntimeVerifier.ExpectedRuntimeId,
                version = "5.5.2",
                architecture = "x64",
                binary = "tesseract.exe",
                files,
                languages = new[]
                {
                    new
                    {
                        language = language ?? "fixture",
                        path = modelPath,
                        size = modelEntry.Size,
                        sha256 = modelEntry.Sha256,
                    },
                },
            };
            File.WriteAllText(
                Path.Combine(RuntimeDirectory, TesseractRuntimeVerifier.ManifestFileName),
                JsonSerializer.Serialize(manifest));
        }

        private static TesseractRuntimeVerifier.TesseractLanguageModel Describe(string absolutePath, string relativePath)
        {
            var bytes = File.ReadAllBytes(absolutePath);
            return new(relativePath, bytes.LongLength,
                Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant());
        }

        private static byte[] CreatePe(ushort machine)
        {
            var bytes = new byte[256];
            bytes[0] = (byte)'M';
            bytes[1] = (byte)'Z';
            BitConverter.GetBytes(0x80).CopyTo(bytes, 0x3c);
            bytes[0x80] = (byte)'P';
            bytes[0x81] = (byte)'E';
            BitConverter.GetBytes(machine).CopyTo(bytes, 0x84);
            return bytes;
        }
    }
}
