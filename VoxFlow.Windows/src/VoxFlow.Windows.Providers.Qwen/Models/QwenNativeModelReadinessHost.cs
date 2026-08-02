using System.Buffers.Binary;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen.Native;
using VoxFlow.Windows.Providers.Qwen.Runtime;

namespace VoxFlow.Windows.Providers.Qwen.Models;

public sealed class QwenNativeModelReadinessHost : IQwenNativeModelReadinessHost, IAsyncDisposable
{
    private static readonly TimeSpan CanaryTimeout = TimeSpan.FromMinutes(8);
    private readonly QwenNativeApi api = new();
    private readonly QwenRuntimeCache cache;

    public QwenNativeModelReadinessHost() => cache = new QwenRuntimeCache(api);

    public async ValueTask<QwenRuntimePrewarmResult> PrewarmAsync(
        QwenModelManifest manifest,
        string installPath,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var lease = await cache.AcquireAsync(
                manifest.Id,
                installPath,
                cancellationToken).ConfigureAwait(false);
            return new QwenRuntimePrewarmResult(QwenRuntimePrewarmStatus.Ready, null);
        }
        catch (QwenRuntimeUnsupportedException)
        {
            return new QwenRuntimePrewarmResult(
                QwenRuntimePrewarmStatus.RuntimeUnsupported,
                "runtime_unsupported");
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or BadImageFormatException)
        {
            return new QwenRuntimePrewarmResult(
                QwenRuntimePrewarmStatus.RuntimeUnsupported,
                "native_runtime_unavailable");
        }
        catch
        {
            return new QwenRuntimePrewarmResult(
                QwenRuntimePrewarmStatus.Failed,
                "prewarm_failed");
        }
    }

    public async ValueTask<QwenCanaryResult> RunCanaryAsync(
        QwenModelManifest manifest,
        string installPath,
        ReadOnlyMemory<short> pcm16,
        CancellationToken cancellationToken)
    {
        QwenRuntimeLease lease;
        try
        {
            lease = await cache.AcquireAsync(
                manifest.Id,
                installPath,
                cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            return new QwenCanaryResult(false, null, "canary_runtime_unavailable");
        }

        await using var session = new QwenNativeDictationSession(
            api,
            lease,
            manifest.Variant == QwenVariant.Qwen06B ? 0 : 1);
        var completion = new TaskCompletionSource<QwenCanaryResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, result) => completion.TrySetResult(
            new QwenCanaryResult(true, result.Text, null));
        session.Failed += (_, _) => completion.TrySetResult(
            new QwenCanaryResult(false, null, "canary_native_failure"));

        try
        {
            await session.StartAsync(cancellationToken).ConfigureAwait(false);
            var bytes = new byte[pcm16.Length * sizeof(short)];
            for (var index = 0; index < pcm16.Length; index++)
            {
                BinaryPrimitives.WriteInt16LittleEndian(
                    bytes.AsSpan(index * sizeof(short), sizeof(short)),
                    pcm16.Span[index]);
            }
            await session.PushAudioAsync(bytes, cancellationToken).ConfigureAwait(false);
            await session.FinishAsync(cancellationToken).ConfigureAwait(false);
            return await completion.Task.WaitAsync(
                CanaryTimeout,
                cancellationToken).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            return new QwenCanaryResult(false, null, "canary_timeout");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new QwenCanaryResult(false, null, "canary_failed");
        }
    }

    public ValueTask ReleaseAsync(
        string modelId,
        string revision,
        CancellationToken cancellationToken) => cache.ReleaseAsync(modelId, cancellationToken);

    public ValueTask DisposeAsync() => cache.DisposeAsync();
}
