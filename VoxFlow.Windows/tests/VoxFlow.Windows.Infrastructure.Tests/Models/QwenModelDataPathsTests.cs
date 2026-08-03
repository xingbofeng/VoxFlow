using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Models;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class QwenModelDataPathsTests
{
    [Theory]
    [InlineData(QwenVariant.Qwen06B, "qwen3-asr-0.6b")]
    [InlineData(QwenVariant.Qwen17B, "qwen3-asr-1.7b")]
    public void Model_paths_are_fixed_below_local_appdata(
        QwenVariant variant,
        string modelId)
    {
        var paths = new QwenModelDataPaths(@"C:\Users\Test\AppData\Local");
        const string revision = "immutable-revision";

        Assert.Equal(
            @"C:\Users\Test\AppData\Local\VoxFlow\Models",
            paths.ModelsRoot);
        Assert.Equal(
            $@"C:\Users\Test\AppData\Local\VoxFlow\Models\{modelId}\{revision}",
            paths.GetInstallDirectory(variant, revision));
        Assert.StartsWith(paths.ModelsRoot, paths.GetStagingDirectory(variant, revision));
        Assert.StartsWith(paths.ModelsRoot, paths.GetDownloadStatePath(variant, revision));
    }
}
