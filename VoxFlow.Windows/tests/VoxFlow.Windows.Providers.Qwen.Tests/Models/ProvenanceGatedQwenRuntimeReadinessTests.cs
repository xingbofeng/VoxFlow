using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen.Models;

namespace VoxFlow.Windows.Providers.Qwen.Tests.Models;

public sealed class ProvenanceGatedQwenRuntimeReadinessTests
{
    [Fact]
    public async Task Blocked_provenance_returns_runtime_unsupported_without_calling_native_host()
    {
        var host = new FakeNativeHost();
        var runtime = new ProvenanceGatedQwenRuntimeReadiness(host);

        var result = await runtime.PrewarmAsync(
            Manifest(new QwenRuntimePublicationGate(false, "blocked")),
            @"C:\Models\qwen",
            CancellationToken.None);

        Assert.Equal(QwenRuntimePrewarmStatus.RuntimeUnsupported, result.Status);
        Assert.Equal("runtime_provenance_blocked", result.ErrorCode);
        Assert.Equal(0, host.PrewarmCalls);
    }

    [Fact]
    public async Task Publishable_provenance_delegates_prewarm_and_canary_to_the_native_host()
    {
        var host = new FakeNativeHost();
        var runtime = new ProvenanceGatedQwenRuntimeReadiness(host);
        var manifest = Manifest(new QwenRuntimePublicationGate(true, null));

        var prewarm = await runtime.PrewarmAsync(
            manifest,
            @"C:\Models\qwen",
            CancellationToken.None);
        var canary = await runtime.RunCanaryAsync(
            manifest,
            @"C:\Models\qwen",
            new short[] { 0, 100, -100 },
            CancellationToken.None);

        Assert.Equal(QwenRuntimePrewarmStatus.Ready, prewarm.Status);
        Assert.True(canary.Success);
        Assert.Equal(1, host.PrewarmCalls);
        Assert.Equal(1, host.CanaryCalls);
    }

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

    private sealed class FakeNativeHost : IQwenNativeModelReadinessHost
    {
        public int PrewarmCalls { get; private set; }
        public int CanaryCalls { get; private set; }

        public ValueTask<QwenRuntimePrewarmResult> PrewarmAsync(
            QwenModelManifest manifest,
            string installPath,
            CancellationToken cancellationToken)
        {
            PrewarmCalls++;
            return ValueTask.FromResult(new QwenRuntimePrewarmResult(
                QwenRuntimePrewarmStatus.Ready,
                null));
        }

        public ValueTask<QwenCanaryResult> RunCanaryAsync(
            QwenModelManifest manifest,
            string installPath,
            ReadOnlyMemory<short> pcm16,
            CancellationToken cancellationToken)
        {
            CanaryCalls++;
            return ValueTask.FromResult(new QwenCanaryResult(true, "final", null));
        }

        public ValueTask ReleaseAsync(
            string modelId,
            string revision,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }
}
