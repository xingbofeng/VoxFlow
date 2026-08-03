using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Models;

public sealed class QwenModelDataPaths
{
    public QwenModelDataPaths(string localApplicationDataPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(localApplicationDataPath);
        ModelsRoot = Path.GetFullPath(Path.Combine(
            localApplicationDataPath,
            "VoxFlow",
            "Models"));
    }

    public string ModelsRoot { get; }

    public string GetInstallDirectory(QwenVariant variant, string revision) =>
        Path.Combine(GetVariantInstallRoot(variant), ValidateRevision(revision));

    public string GetStagingDirectory(QwenVariant variant, string revision) =>
        Path.Combine(GetVariantStagingRoot(variant), ValidateRevision(revision));

    public string GetDownloadStatePath(QwenVariant variant, string revision) =>
        Path.Combine(GetStagingDirectory(variant, revision), ".download-state.json");

    public string GetVariantInstallRoot(QwenVariant variant) =>
        Path.Combine(ModelsRoot, GetModelId(variant));

    public string GetVariantStagingRoot(QwenVariant variant) =>
        Path.Combine(ModelsRoot, ".staging", GetModelId(variant));

    public static string GetModelId(QwenVariant variant) => variant switch
    {
        QwenVariant.Qwen06B => "qwen3-asr-0.6b",
        QwenVariant.Qwen17B => "qwen3-asr-1.7b",
        _ => throw new ArgumentOutOfRangeException(nameof(variant), variant, null),
    };

    private static string ValidateRevision(string revision)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(revision);
        if (revision.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0
            || revision is "." or "..")
        {
            throw new ArgumentException("Model revision is not a safe directory name.", nameof(revision));
        }

        return revision;
    }
}
