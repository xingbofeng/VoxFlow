using System.Collections.Concurrent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Providers.Qwen.Native;
using VoxFlow.Windows.Providers.Qwen.Runtime;

namespace VoxFlow.Windows.Providers.Qwen.Tests.Runtime;

public sealed class QwenNativeDictationSessionTests
{
    [Fact]
    public async Task PCM_is_copied_as_little_endian_samples_and_finish_flushes_the_authoritative_final()
    {
        var api = new FakeNativeApi();
        await using var cache = new QwenRuntimeCache(api);
        QwenRuntimeLease lease = await cache.AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None);
        await using var session = new QwenNativeDictationSession(api, lease, variant: 0);
        var final = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, value) => final.TrySetResult(value.Text);

        await session.StartAsync(CancellationToken.None);
        await session.PushAudioAsync(new byte[] { 0x01, 0x00, 0xff, 0x7f }, CancellationToken.None);
        api.Events.Enqueue(new QwenNativeEventData(QwenNativeEventKind.Final, 0, "你好", 0));
        await session.FinishAsync(CancellationToken.None);

        Assert.Equal("你好", await final.Task.WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.Equal([1, 32767], api.PushedSamples);
        Assert.Equal(1, api.FinishCount);
    }

    [Fact]
    public async Task Native_events_are_dispatched_from_a_bounded_background_channel_not_the_caller_context()
    {
        var api = new FakeNativeApi();
        await using var cache = new QwenRuntimeCache(api);
        QwenRuntimeLease lease = await cache.AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None);
        await using var session = new QwenNativeDictationSession(api, lease, variant: 0);
        int callerThread = Environment.CurrentManagedThreadId;
        var final = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, _) => final.TrySetResult(Environment.CurrentManagedThreadId);

        for (int index = 1; index <= QwenNativeDictationSession.EventChannelCapacity * 3; index++)
        {
            api.Events.Enqueue(new QwenNativeEventData(QwenNativeEventKind.Partial, index, $"partial-{index}", 0));
        }

        api.Events.Enqueue(new QwenNativeEventData(QwenNativeEventKind.Final, 0, "done", 0));
        await session.StartAsync(CancellationToken.None);

        int callbackThread = await final.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.NotEqual(callerThread, callbackThread);
    }

    [Fact]
    public async Task Cancellation_stops_polling_and_discards_late_native_events()
    {
        var api = new FakeNativeApi();
        await using var cache = new QwenRuntimeCache(api);
        QwenRuntimeLease lease = await cache.AcquireAsync("qwen3-asr-0.6b", "C:/models/0.6b", CancellationToken.None);
        await using var session = new QwenNativeDictationSession(api, lease, variant: 0);
        int finals = 0;
        session.FinalReceived += (_, _) => Interlocked.Increment(ref finals);

        await session.StartAsync(CancellationToken.None);
        await session.CancelAsync(CancellationToken.None);
        api.Events.Enqueue(new QwenNativeEventData(QwenNativeEventKind.Final, 0, "late", 0));
        await Task.Delay(50);

        Assert.Equal(1, api.CancelCount);
        Assert.Equal(0, finals);
    }

    private sealed class FakeNativeApi : IQwenNativeApi
    {
        private int nextHandle = 100;

        public ConcurrentQueue<QwenNativeEventData> Events { get; } = new();

        public List<short> PushedSamples { get; } = [];

        public int FinishCount { get; private set; }

        public int CancelCount { get; private set; }

        public int AbiVersion => QwenNativeMethods.ExpectedAbiVersion;

        public QwenRuntimeSafeHandle CreateRuntime(string modelPath) => new(nextHandle++, this);

        public QwenSessionSafeHandle CreateSession(QwenRuntimeSafeHandle runtime, int variant) => new(nextHandle++, this);

        public int Start(QwenSessionSafeHandle session) => 0;

        public int PushPcm16(QwenSessionSafeHandle session, ReadOnlySpan<short> samples)
        {
            PushedSamples.AddRange(samples);
            return 0;
        }

        public QwenNativePollResult Poll(QwenSessionSafeHandle session, out QwenNativeEventData @event)
        {
            if (Events.TryDequeue(out QwenNativeEventData? next))
            {
                @event = next;
                return QwenNativePollResult.Event;
            }

            @event = new QwenNativeEventData(QwenNativeEventKind.Progress, 0, string.Empty, 0);
            return QwenNativePollResult.Empty;
        }

        public int Finish(QwenSessionSafeHandle session)
        {
            FinishCount++;
            return 0;
        }

        public void Cancel(QwenSessionSafeHandle session) => CancelCount++;

        public string GetLastError(QwenSessionSafeHandle session) => "native failure";

        public void DestroyRuntime(nint runtime)
        {
        }

        public void DestroySession(nint session)
        {
        }
    }
}
