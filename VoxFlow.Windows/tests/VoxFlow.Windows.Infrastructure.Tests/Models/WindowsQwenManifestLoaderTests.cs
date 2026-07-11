using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Infrastructure.Models;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class WindowsQwenManifestLoaderTests
{
    [Fact]
    public void Raw_windows_provenance_produces_only_the_two_qwen_manifests()
    {
        var provenancePath = Path.Combine(
            AppContext.BaseDirectory,
            "TestResources",
            "MODEL_PROVENANCE.json");

        var catalog = WindowsQwenManifestLoader.Load(provenancePath);

        Assert.True(catalog.RuntimeGate.IsPublishable);
        Assert.Null(catalog.RuntimeGate.Blocker);
        Assert.Equal("b00b789b17051aea61e9717458171100662318a4", catalog.RuntimeRevision);
        Assert.Equal(
            ["qwen3-asr-0.6b", "qwen3-asr-1.7b"],
            catalog.Models.Select(model => model.Id).ToArray());
        Assert.Equal(
            ["Qwen 0.6B", "Qwen 1.7B"],
            catalog.Models.Select(model => model.DisplayName).ToArray());

        foreach (var model in catalog.Models)
        {
            Assert.NotEmpty(model.Files);
            Assert.Equal(model.TotalBytes, model.Files.Sum(file => file.Bytes));
            Assert.All(model.Files, file =>
            {
                Assert.Equal(Uri.UriSchemeHttps, file.Source.Scheme);
                Assert.Matches("^[a-f0-9]{64}$", file.Sha256);
                Assert.DoesNotContain("mlx", file.Source.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
            });
        }
    }

    [Fact]
    public void Loader_rejects_publishable_claim_when_windows_validation_is_blocked()
    {
        using var document = System.Text.Json.JsonDocument.Parse(
            File.ReadAllText(Path.Combine(
                AppContext.BaseDirectory,
                "TestResources",
                "MODEL_PROVENANCE.json")));
        var raw = document.RootElement.GetRawText()
            .Replace("\"publishable\": false", "\"publishable\": true", StringComparison.Ordinal)
            .Replace("\"status\": \"passed\"", "\"status\": \"blocked\"", StringComparison.Ordinal);
        var path = Path.Combine(Path.GetTempPath(), $"qwen-provenance-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, raw);

        try
        {
            var error = Assert.Throws<InvalidDataException>(() =>
                WindowsQwenManifestLoader.Load(path));
            Assert.Contains("blocked", error.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
