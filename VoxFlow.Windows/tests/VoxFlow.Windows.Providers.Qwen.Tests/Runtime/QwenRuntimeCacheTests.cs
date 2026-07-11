using VoxFlow.Windows.Providers.Qwen.Native;
using VoxFlow.Windows.Providers.Qwen.Runtime;

namespace VoxFlow.Windows.Providers.Qwen.Tests.Runtime;

public sealed class QwenRuntimeCacheTests
{
    [Fact]
    public async Task Same_model_reuses_one_runtime_and_serializes_inference_leases()
    {
        var api = new FakeNativeApi();
        await using var cache = new QwenRuntimeCache(api);

        QwenRuntimeLease first = await cache.AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None);
        Task<QwenRuntimeLease> secondTask = cache
            .AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None)
            .AsTask();

        await Task.Yield();
        Assert.False(secondTask.IsCompleted);

        await first.DisposeAsync();
        await using QwenRuntimeLease second = await secondTask;

        Assert.Equal(1, api.RuntimeCreateCount);
        Assert.Same(first.Runtime, second.Runtime);
    }

    [Fact]
    public async Task Different_model_replaces_the_cached_runtime_after_the_active_lease_finishes()
    {
        var api = new FakeNativeApi();
        await using var cache = new QwenRuntimeCache(api);

        QwenRuntimeLease first = await cache.AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None);
        await first.DisposeAsync();
        await using QwenRuntimeLease second = await cache.AcquireAsync("qwen3-asr-1.7b", "C:/models/1.7b", CancellationToken.None);

        Assert.Equal(2, api.RuntimeCreateCount);
        Assert.Single(api.DestroyedRuntimes);
        Assert.NotSame(first.Runtime, second.Runtime);
    }

    [Fact]
    public async Task ABI_mismatch_fails_as_runtime_unsupported_before_loading_a_model()
    {
        var api = new FakeNativeApi { AbiVersion = 99 };
        await using var cache = new QwenRuntimeCache(api);

        QwenRuntimeUnsupportedException error = await Assert.ThrowsAsync<QwenRuntimeUnsupportedException>(
            () => cache.AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None).AsTask());

        Assert.Equal(QwenNativeMethods.ExpectedAbiVersion, error.ExpectedVersion);
        Assert.Equal(99, error.ActualVersion);
        Assert.Equal(0, api.RuntimeCreateCount);
    }

    private sealed class FakeNativeApi : IQwenNativeApi
    {
        private int nextHandle = 100;

        public int AbiVersion { get; set; } = QwenNativeMethods.ExpectedAbiVersion;

        public int RuntimeCreateCount { get; private set; }

        public List<nint> DestroyedRuntimes { get; } = [];

        public QwenRuntimeSafeHandle CreateRuntime(string modelPath)
        {
            RuntimeCreateCount++;
            return new QwenRuntimeSafeHandle(nextHandle++, this);
        }

        public QwenSessionSafeHandle CreateSession(QwenRuntimeSafeHandle runtime, int variant) => throw new NotSupportedException();

        public int Start(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public int PushPcm16(QwenSessionSafeHandle session, ReadOnlySpan<short> samples) => throw new NotSupportedException();

        public QwenNativePollResult Poll(QwenSessionSafeHandle session, out QwenNativeEventData @event) => throw new NotSupportedException();

        public int Finish(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public void Cancel(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public string GetLastError(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public void DestroyRuntime(nint runtime) => DestroyedRuntimes.Add(runtime);

        public void DestroySession(nint session) => throw new NotSupportedException();
    }
}
