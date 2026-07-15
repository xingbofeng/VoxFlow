using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Models;

public enum QwenRuntimePrewarmStatus
{
    Ready,
    RuntimeUnsupported,
    HardwareUnsupported,
    Failed,
}

public sealed record QwenRuntimePrewarmResult(
    QwenRuntimePrewarmStatus Status,
    string? ErrorCode);

public sealed record QwenCanaryResult(
    bool Success,
    string? FinalText,
    string? ErrorCode);

public interface IQwenModelRuntimeReadiness : IQwenModelRuntimeCache
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
}

public interface IModelInstallStatePublisher
{
    void Publish(QwenModelManifest manifest, ModelInstallRecord state);
}

public sealed class QwenModelReadinessService
{
    private readonly IModelInstallStateRepository stateRepository;
    private readonly IQwenModelRuntimeReadiness runtime;
    private readonly IModelInstallStatePublisher statePublisher;
    private readonly ReadOnlyMemory<short> canaryPcm16;

    public QwenModelReadinessService(
        IModelInstallStateRepository stateRepository,
        IQwenModelRuntimeReadiness runtime,
        IModelInstallStatePublisher statePublisher,
        ReadOnlyMemory<short> canaryPcm16)
    {
        this.stateRepository = stateRepository
            ?? throw new ArgumentNullException(nameof(stateRepository));
        this.runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        this.statePublisher = statePublisher
            ?? throw new ArgumentNullException(nameof(statePublisher));
        if (canaryPcm16.IsEmpty || IsSilent(canaryPcm16.Span))
        {
            throw new ArgumentException(
                "The Qwen readiness canary must contain non-silent PCM16 audio.",
                nameof(canaryPcm16));
        }

        this.canaryPcm16 = canaryPcm16;
    }

    public async Task<ModelInstallRecord> EvaluateAsync(
        QwenModelManifest manifest,
        string installPath,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentException.ThrowIfNullOrWhiteSpace(installPath);
        var current = await stateRepository.LoadAsync(manifest.Id, cancellationToken)
            .ConfigureAwait(false)
            ?? throw new InvalidOperationException("The installed model has no lifecycle state.");

        if (current.Version != manifest.ModelRevision
            || current.Phase != ModelInstallPhase.Installing)
        {
            throw new InvalidOperationException(
                "Qwen readiness requires the matching model to be in the installing phase.");
        }

        current = current.MoveTo(
            ModelInstallPhase.Prewarming,
            installPath: installPath);
        await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);

        if (!manifest.RuntimeGate.IsPublishable)
        {
            current = current.MoveTo(
                ModelInstallPhase.RuntimeUnsupported,
                errorCode: "runtime_provenance_blocked");
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            return current;
        }

        var prewarm = await runtime.PrewarmAsync(
            manifest,
            installPath,
            cancellationToken).ConfigureAwait(false);
        if (prewarm.Status != QwenRuntimePrewarmStatus.Ready)
        {
            current = current.MoveTo(
                ToInstallPhase(prewarm.Status),
                errorCode: prewarm.ErrorCode ?? ToDefaultError(prewarm.Status));
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            return current;
        }

        current = current.MoveTo(ModelInstallPhase.CanaryTesting);
        await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
        var canary = await runtime.RunCanaryAsync(
            manifest,
            installPath,
            canaryPcm16,
            cancellationToken).ConfigureAwait(false);
        if (!canary.Success || string.IsNullOrWhiteSpace(canary.FinalText))
        {
            current = current.MoveTo(
                ModelInstallPhase.Failed,
                errorCode: canary.ErrorCode ?? "canary_empty_final");
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            return current;
        }

        current = current.MoveTo(ModelInstallPhase.Ready);
        await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
        return current;
    }

    private async ValueTask SaveAsync(
        QwenModelManifest manifest,
        ModelInstallRecord state,
        CancellationToken cancellationToken)
    {
        await stateRepository.SaveAsync(state, cancellationToken).ConfigureAwait(false);
        statePublisher.Publish(manifest, state);
    }

    private static ModelInstallPhase ToInstallPhase(QwenRuntimePrewarmStatus status) => status switch
    {
        QwenRuntimePrewarmStatus.RuntimeUnsupported => ModelInstallPhase.RuntimeUnsupported,
        QwenRuntimePrewarmStatus.HardwareUnsupported => ModelInstallPhase.HardwareUnsupported,
        QwenRuntimePrewarmStatus.Failed => ModelInstallPhase.Failed,
        _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
    };

    private static string ToDefaultError(QwenRuntimePrewarmStatus status) => status switch
    {
        QwenRuntimePrewarmStatus.RuntimeUnsupported => "runtime_unsupported",
        QwenRuntimePrewarmStatus.HardwareUnsupported => "hardware_unsupported",
        QwenRuntimePrewarmStatus.Failed => "prewarm_failed",
        _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
    };

    private static bool IsSilent(ReadOnlySpan<short> samples)
    {
        foreach (var sample in samples)
        {
            if (sample != 0)
            {
                return false;
            }
        }

        return true;
    }
}
