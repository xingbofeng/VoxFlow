using VoxFlow.Windows.Providers.Qwen.Native;

namespace VoxFlow.Windows.Providers.Qwen.Runtime;

internal sealed class QwenRuntimeCache : IAsyncDisposable
{
    private readonly IQwenNativeApi api;
    private readonly SemaphoreSlim leaseGate = new(1, 1);
    private QwenRuntimeSafeHandle? runtime;
    private string? modelId;
    private string? modelPath;
    private int disposed;

    internal QwenRuntimeCache(IQwenNativeApi api)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
    }

    internal async ValueTask<QwenRuntimeLease> AcquireAsync(
        string requestedModelId,
        string requestedModelPath,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedModelId);
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedModelPath);
        ObjectDisposedException.ThrowIf(
            Volatile.Read(ref disposed) != 0,
            this);

        await leaseGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(
                Volatile.Read(ref disposed) != 0,
                this);

            if (api.AbiVersion != QwenNativeMethods.ExpectedAbiVersion)
            {
                throw new QwenRuntimeUnsupportedException(
                    QwenNativeMethods.ExpectedAbiVersion,
                    api.AbiVersion);
            }

            if (runtime is null ||
                runtime.IsInvalid ||
                !StringComparer.Ordinal.Equals(modelId, requestedModelId) ||
                !StringComparer.OrdinalIgnoreCase.Equals(modelPath, requestedModelPath))
            {
                runtime?.Dispose();
                runtime = api.CreateRuntime(requestedModelPath);
                modelId = requestedModelId;
                modelPath = requestedModelPath;
            }

            return new QwenRuntimeLease(runtime, leaseGate);
        }
        catch
        {
            leaseGate.Release();
            throw;
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        await leaseGate.WaitAsync().ConfigureAwait(false);
        try
        {
            runtime?.Dispose();
            runtime = null;
            modelId = null;
            modelPath = null;
        }
        finally
        {
            leaseGate.Release();
            leaseGate.Dispose();
        }
    }
}

internal sealed class QwenRuntimeLease : IAsyncDisposable
{
    private SemaphoreSlim? gate;

    internal QwenRuntimeLease(
        QwenRuntimeSafeHandle runtime,
        SemaphoreSlim gate)
    {
        Runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        this.gate = gate ?? throw new ArgumentNullException(nameof(gate));
    }

    internal QwenRuntimeSafeHandle Runtime { get; }

    public ValueTask DisposeAsync()
    {
        Interlocked.Exchange(ref gate, null)?.Release();
        return ValueTask.CompletedTask;
    }
}

internal sealed class QwenRuntimeUnsupportedException : Exception
{
    internal QwenRuntimeUnsupportedException(int expectedVersion, int actualVersion)
        : base($"Qwen native ABI {actualVersion} is unsupported; expected {expectedVersion}.")
    {
        ExpectedVersion = expectedVersion;
        ActualVersion = actualVersion;
    }

    internal int ExpectedVersion { get; }

    internal int ActualVersion { get; }
}
