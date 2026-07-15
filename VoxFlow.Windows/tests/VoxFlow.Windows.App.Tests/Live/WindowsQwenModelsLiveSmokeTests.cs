using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests.Live;

/// <summary>
/// Explicit live validation for the production Qwen download,
/// integrity, install, native prewarm and non-silent canary path. It uses only
/// the public, revision-pinned model manifests bundled with VoxFlow. Set
/// VOICEINPUT_TEST_WINDOWS_QWEN_MODEL_ID to validate one variant while
/// diagnosing the native runtime; omitting it validates the full catalog.
/// </summary>
public sealed class WindowsQwenModelsLiveSmokeTests
{
    [WindowsQwenModelsLiveFact]
    [Trait("Category", "Live")]
    public async Task Both_pinned_models_download_install_and_reach_ready()
    {
        var databasePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow",
            "voxflow.db");
        Assert.True(File.Exists(databasePath), "Qwen live smoke: local_db_missing");

        using var composition = new WindowsAppCompositionRoot(databasePath);
        using var timeout = new CancellationTokenSource(TimeSpan.FromHours(2));
        var requestedModelId = Environment.GetEnvironmentVariable(
            "VOICEINPUT_TEST_WINDOWS_QWEN_MODEL_ID");
        var manifests = composition.QwenCatalog.Models
            .Where(model => string.IsNullOrWhiteSpace(requestedModelId)
                || string.Equals(model.Id, requestedModelId, StringComparison.Ordinal))
            .OrderBy(model => model.Variant)
            .ToArray();
        Assert.NotEmpty(manifests);

        foreach (var manifest in manifests)
        {
            var result = await composition.QwenModelOperations.DownloadAsync(
                manifest,
                userInitiated: true,
                timeout.Token);
            Assert.True(
                result.Phase == ModelInstallPhase.Ready,
                string.Concat(
                    "Qwen live smoke: model=",
                    manifest.Id,
                    "; phase=",
                    result.Phase,
                    "; error=",
                    string.IsNullOrWhiteSpace(result.ErrorCode)
                        ? "none"
                        : result.ErrorCode));
        }
    }
}

[AttributeUsage(AttributeTargets.Method, AllowMultiple = false)]
public sealed class WindowsQwenModelsLiveFactAttribute : FactAttribute
{
    public WindowsQwenModelsLiveFactAttribute()
        : this(
            OperatingSystem.IsWindows(),
            Environment.GetEnvironmentVariable("VOICEINPUT_TEST_WINDOWS_QWEN_MODELS"))
    {
    }

    internal WindowsQwenModelsLiveFactAttribute(bool isWindows, string? optInValue)
    {
        if (!isWindows)
        {
            Skip = "Requires Windows x64 and the bundled qwen_asr runtime.";
            return;
        }

        if (!string.Equals(optInValue, "1", StringComparison.Ordinal))
        {
            Skip = "Set VOICEINPUT_TEST_WINDOWS_QWEN_MODELS=1 to run the multi-gigabyte Qwen live smoke.";
        }
    }
}

public sealed class WindowsQwenModelsLiveFactTests
{
    [Fact]
    public void Missing_opt_in_reports_an_explicit_discovery_skip()
    {
        var attribute = new WindowsQwenModelsLiveFactAttribute(
            isWindows: true,
            optInValue: null);

        Assert.False(string.IsNullOrWhiteSpace(attribute.Skip));
    }
}
