using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen.Native;
using VoxFlow.Windows.Providers.Qwen.Runtime;

namespace VoxFlow.Windows.Providers.Qwen;

public sealed class QwenDictationProviderRuntime : IAsyncDisposable
{
    private readonly Func<QwenVariant, bool> readiness;
    private readonly QwenRuntimeCache runtimeCache;
    private readonly QwenNativeSessionAttemptFactory attemptFactory;

    public QwenDictationProviderRuntime(
        Func<QwenVariant, bool> readiness,
        Func<QwenVariant, CancellationToken, ValueTask<string>> modelPathResolver)
    {
        this.readiness = readiness ?? throw new ArgumentNullException(nameof(readiness));
        ArgumentNullException.ThrowIfNull(modelPathResolver);
        var api = new QwenNativeApi();
        runtimeCache = new QwenRuntimeCache(api);
        attemptFactory = new QwenNativeSessionAttemptFactory(
            api,
            runtimeCache,
            new DelegateModelPathResolver(modelPathResolver));
    }

    public IDictationAsrProvider CreateProvider(QwenVariant variant)
    {
        if (!Enum.IsDefined(variant))
        {
            throw new ArgumentOutOfRangeException(nameof(variant));
        }
        return new QwenAsrProvider(
            variant,
            new DelegateReadiness(readiness),
            attemptFactory);
    }

    public ValueTask DisposeAsync() => runtimeCache.DisposeAsync();

    private sealed class DelegateReadiness(Func<QwenVariant, bool> readiness)
        : IQwenProviderReadiness
    {
        public bool IsReadyFor(QwenVariant variant) => readiness(variant);
    }

    private sealed class DelegateModelPathResolver(
        Func<QwenVariant, CancellationToken, ValueTask<string>> resolver)
        : IQwenModelPathResolver
    {
        public ValueTask<string> GetReadyModelPathAsync(
            QwenVariant variant,
            CancellationToken cancellationToken) => resolver(variant, cancellationToken);
    }
}
