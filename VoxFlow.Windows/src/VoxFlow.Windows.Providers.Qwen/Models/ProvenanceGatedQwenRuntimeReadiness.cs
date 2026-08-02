using VoxFlow.Windows.Application.Models;

namespace VoxFlow.Windows.Providers.Qwen.Models;

public interface IQwenNativeModelReadinessHost
{
    ValueTask<QwenRuntimePrewarmResult> PrewarmAsync(
        QwenModelManifest manifest,
        string installPath,
        CancellationToken cancellationToken);

    ValueTask<QwenCanaryResult> RunCanaryAsync(
        QwenModelManifest manifest,
        string installPath,
        ReadOnlyMemory<short> pcm16,
        CancellationToken cancellationToken);

    ValueTask ReleaseAsync(
        string modelId,
        string revision,
        CancellationToken cancellationToken);
}

public sealed class ProvenanceGatedQwenRuntimeReadiness(
    IQwenNativeModelReadinessHost nativeHost) : IQwenModelRuntimeReadiness
{
    public ValueTask<QwenRuntimePrewarmResult> PrewarmAsync(
        QwenModelManifest manifest,
        string installPath,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        if (!manifest.RuntimeGate.IsPublishable)
        {
            return ValueTask.FromResult(new QwenRuntimePrewarmResult(
                QwenRuntimePrewarmStatus.RuntimeUnsupported,
                "runtime_provenance_blocked"));
        }

        return nativeHost.PrewarmAsync(manifest, installPath, cancellationToken);
    }

    public ValueTask<QwenCanaryResult> RunCanaryAsync(
        QwenModelManifest manifest,
        string installPath,
        ReadOnlyMemory<short> pcm16,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        if (!manifest.RuntimeGate.IsPublishable)
        {
            return ValueTask.FromResult(new QwenCanaryResult(
                false,
                null,
                "runtime_provenance_blocked"));
        }

        return nativeHost.RunCanaryAsync(manifest, installPath, pcm16, cancellationToken);
    }

    public ValueTask ReleaseAsync(
        string modelId,
        string revision,
        CancellationToken cancellationToken) =>
        nativeHost.ReleaseAsync(modelId, revision, cancellationToken);
}
