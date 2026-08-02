using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen.Native;

namespace VoxFlow.Windows.Providers.Qwen.Runtime;

internal interface IQwenModelPathResolver
{
    ValueTask<string> GetReadyModelPathAsync(
        QwenVariant variant,
        CancellationToken cancellationToken);
}

internal sealed class QwenNativeSessionAttemptFactory : IQwenSessionAttemptFactory
{
    private readonly IQwenNativeApi api;
    private readonly QwenRuntimeCache runtimeCache;
    private readonly IQwenModelPathResolver modelPathResolver;

    internal QwenNativeSessionAttemptFactory(
        IQwenNativeApi api,
        QwenRuntimeCache runtimeCache,
        IQwenModelPathResolver modelPathResolver)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
        this.runtimeCache = runtimeCache ?? throw new ArgumentNullException(nameof(runtimeCache));
        this.modelPathResolver = modelPathResolver ?? throw new ArgumentNullException(nameof(modelPathResolver));
    }

    public async ValueTask PrewarmAsync(
        QwenVariant variant,
        CancellationToken cancellationToken)
    {
        string path = await modelPathResolver
            .GetReadyModelPathAsync(variant, cancellationToken)
            .ConfigureAwait(false);
        await using QwenRuntimeLease lease = await runtimeCache
            .AcquireAsync(ModelId(variant), path, cancellationToken)
            .ConfigureAwait(false);
    }

    public async ValueTask<IDictationAsrSession> CreateAsync(
        QwenVariant variant,
        Guid generation,
        CancellationToken cancellationToken)
    {
        string path = await modelPathResolver
            .GetReadyModelPathAsync(variant, cancellationToken)
            .ConfigureAwait(false);
        QwenRuntimeLease lease = await runtimeCache
            .AcquireAsync(ModelId(variant), path, cancellationToken)
            .ConfigureAwait(false);
        try
        {
            return new QwenNativeDictationSession(api, lease, NativeVariant(variant));
        }
        catch
        {
            await lease.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }

    private static string ModelId(QwenVariant variant) => variant switch
    {
        QwenVariant.Qwen06B => "qwen3-asr-0.6b",
        QwenVariant.Qwen17B => "qwen3-asr-1.7b",
        _ => throw new ArgumentOutOfRangeException(nameof(variant), variant, null),
    };

    private static int NativeVariant(QwenVariant variant) => variant switch
    {
        QwenVariant.Qwen06B => 0,
        QwenVariant.Qwen17B => 1,
        _ => throw new ArgumentOutOfRangeException(nameof(variant), variant, null),
    };
}
