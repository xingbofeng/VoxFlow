using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests.Models;

public sealed class QwenModelReadinessServiceTests
{
    [Fact]
    public async Task Blocked_runtime_provenance_becomes_unsupported_without_loading_native_code()
    {
        var manifest = Manifest(new QwenRuntimePublicationGate(false, "MSVC validation blocked"));
        var repository = new MemoryRepository(Installed(manifest));
        var runtime = new FakeRuntime();
        var publisher = new CapturingPublisher();
        var service = new QwenModelReadinessService(
            repository,
            runtime,
            publisher,
            NonSilentCanary);

        var result = await service.EvaluateAsync(manifest, @"C:\Models\qwen", CancellationToken.None);

        Assert.Equal(ModelInstallPhase.RuntimeUnsupported, result.Phase);
        Assert.Equal("runtime_provenance_blocked", result.ErrorCode);
        Assert.Equal(0, runtime.PrewarmCalls);
        Assert.Equal(
            [ModelInstallPhase.Prewarming, ModelInstallPhase.RuntimeUnsupported],
            publisher.States.Select(state => state.Phase).ToArray());
    }

    [Fact]
    public async Task Runtime_unsupported_result_never_runs_canary_or_becomes_ready()
    {
        var manifest = Manifest(new QwenRuntimePublicationGate(true, null));
        var repository = new MemoryRepository(Installed(manifest));
        var runtime = new FakeRuntime
        {
            PrewarmResult = new QwenRuntimePrewarmResult(
                QwenRuntimePrewarmStatus.RuntimeUnsupported,
                "abi_mismatch"),
        };
        var service = new QwenModelReadinessService(
            repository,
            runtime,
            new CapturingPublisher(),
            NonSilentCanary);

        var result = await service.EvaluateAsync(manifest, @"C:\Models\qwen", CancellationToken.None);

        Assert.Equal(ModelInstallPhase.RuntimeUnsupported, result.Phase);
        Assert.Equal("abi_mismatch", result.ErrorCode);
        Assert.Equal(0, runtime.CanaryCalls);
    }

    [Fact]
    public async Task Canary_failure_after_prewarm_does_not_mark_the_model_ready()
    {
        var manifest = Manifest(new QwenRuntimePublicationGate(true, null));
        var repository = new MemoryRepository(Installed(manifest));
        var runtime = new FakeRuntime
        {
            CanaryResult = new QwenCanaryResult(false, null, "canary_no_final"),
        };
        var publisher = new CapturingPublisher();
        var service = new QwenModelReadinessService(
            repository,
            runtime,
            publisher,
            NonSilentCanary);

        var result = await service.EvaluateAsync(manifest, @"C:\Models\qwen", CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Failed, result.Phase);
        Assert.Equal("canary_no_final", result.ErrorCode);
        Assert.Contains(runtime.CanaryAudio, sample => sample != 0);
        Assert.DoesNotContain(publisher.States, state => state.Phase == ModelInstallPhase.Ready);
    }

    [Fact]
    public async Task Successful_prewarm_and_non_silent_canary_are_both_required_for_ready()
    {
        var manifest = Manifest(new QwenRuntimePublicationGate(true, null));
        var repository = new MemoryRepository(Installed(manifest));
        var runtime = new FakeRuntime();
        var publisher = new CapturingPublisher();
        var service = new QwenModelReadinessService(
            repository,
            runtime,
            publisher,
            NonSilentCanary);

        var result = await service.EvaluateAsync(manifest, @"C:\Models\qwen", CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Ready, result.Phase);
        Assert.Equal(
            [ModelInstallPhase.Prewarming, ModelInstallPhase.CanaryTesting, ModelInstallPhase.Ready],
            publisher.States.Select(state => state.Phase).ToArray());
        Assert.Equal(result, repository.State);
    }

    private static readonly short[] NonSilentCanary = [0, 64, -128, 256, 0];

    private static ModelInstallRecord Installed(QwenModelManifest manifest) => new(
        manifest.Id,
        manifest.ModelRevision,
        ModelInstallPhase.Installing,
        manifest.TotalBytes,
        manifest.TotalBytes,
        @"C:\Models\qwen",
        null);

    private static QwenModelManifest Manifest(QwenRuntimePublicationGate gate)
    {
        byte[] bytes = [1];
        return new QwenModelManifest(
            "qwen3-asr-0.6b",
            "Qwen 0.6B",
            QwenVariant.Qwen06B,
            "revision",
            "runtime",
            bytes.Length,
            [new QwenModelFile(
                "model.bin",
                new Uri("https://models.invalid/model.bin"),
                bytes.Length,
                Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant())],
            gate);
    }

    private sealed class MemoryRepository(ModelInstallRecord state)
        : IModelInstallStateRepository
    {
        public ModelInstallRecord? State { get; private set; } = state;

        public ValueTask<ModelInstallRecord?> LoadAsync(
            string modelId,
            CancellationToken cancellationToken) => ValueTask.FromResult(State);

        public ValueTask SaveAsync(
            ModelInstallRecord state,
            CancellationToken cancellationToken)
        {
            State = state;
            return ValueTask.CompletedTask;
        }

        public ValueTask DeleteAsync(string modelId, CancellationToken cancellationToken)
        {
            State = null;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class CapturingPublisher : IModelInstallStatePublisher
    {
        public List<ModelInstallRecord> States { get; } = [];

        public void Publish(QwenModelManifest manifest, ModelInstallRecord state) =>
            States.Add(state);
    }

    private sealed class FakeRuntime : IQwenModelRuntimeReadiness
    {
        public QwenRuntimePrewarmResult PrewarmResult { get; init; } =
            new(QwenRuntimePrewarmStatus.Ready, null);

        public QwenCanaryResult CanaryResult { get; init; } =
            new(true, "canary final", null);

        public int PrewarmCalls { get; private set; }

        public int CanaryCalls { get; private set; }

        public short[] CanaryAudio { get; private set; } = [];

        public ValueTask<QwenRuntimePrewarmResult> PrewarmAsync(
            QwenModelManifest manifest,
            string installPath,
            CancellationToken cancellationToken)
        {
            PrewarmCalls++;
            return ValueTask.FromResult(PrewarmResult);
        }

        public ValueTask<QwenCanaryResult> RunCanaryAsync(
            QwenModelManifest manifest,
            string installPath,
            ReadOnlyMemory<short> pcm16,
            CancellationToken cancellationToken)
        {
            CanaryCalls++;
            CanaryAudio = pcm16.ToArray();
            return ValueTask.FromResult(CanaryResult);
        }

        public ValueTask ReleaseAsync(
            string modelId,
            string revision,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }
}
