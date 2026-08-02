using System.Diagnostics;
using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class Dx11ScreenshotFrameSourceTests
{
    [Fact]
    public async Task First_false_frame_is_not_copied_and_next_success_is_frozen()
    {
        var fixture = SingleDisplayFixture([false, true], SolidBgra(2, 1, 23));
        var source = new Dx11ScreenshotFrameSource(fixture.Factory, fixture.PhysicalDisplays);

        var desktop = await source.FreezeAllDisplaysAsync(
            TimeSpan.FromMilliseconds(300),
            CancellationToken.None);

        Assert.Single(desktop.Frames);
        Assert.Equal(2, fixture.Capture.TryCaptureCount);
        Assert.Equal(1, fixture.Capture.CopyCount);
        Assert.Equal(1, fixture.Capture.DisposeCount);
        Assert.Equal(23, desktop.Frames[0].Bgra.Span[0]);
        Assert.Equal("0:00001234:00005678", desktop.Frames[0].AdapterId);

        source.Dispose();
        Assert.Equal(1, fixture.Backend.DisposeCount);
    }

    [Fact]
    public async Task Static_screen_timeout_never_reads_an_old_zone_buffer_and_resets_service()
    {
        var fixture = SingleDisplayFixture([], SolidBgra(2, 1, 41), defaultOutcome: false);
        using var source = new Dx11ScreenshotFrameSource(fixture.Factory, fixture.PhysicalDisplays);

        var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() =>
            source.FreezeAllDisplaysAsync(
                TimeSpan.FromMilliseconds(35),
                CancellationToken.None));

        Assert.Equal(ScreenshotCaptureFailureKind.TimedOut, exception.Kind);
        Assert.Equal(0, fixture.Capture.CopyCount);
        Assert.True(SpinWait.SpinUntil(
            () => fixture.Capture.DisposeCount == 1 && fixture.Backend.DisposeCount == 1,
            TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public async Task All_zero_success_is_retried_then_reported_as_invalid_instead_of_frozen()
    {
        var fixture = SingleDisplayFixture([], new byte[8], defaultOutcome: true);
        using var source = new Dx11ScreenshotFrameSource(fixture.Factory, fixture.PhysicalDisplays);

        var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() =>
            source.FreezeAllDisplaysAsync(
                TimeSpan.FromMilliseconds(35),
                CancellationToken.None));

        Assert.Equal(ScreenshotCaptureFailureKind.InvalidFrame, exception.Kind);
        Assert.True(fixture.Capture.CopyCount > 0);
        Assert.Equal(1, fixture.Capture.DisposeCount);
    }

    [Fact]
    public async Task Cancellation_stops_retries_and_unregisters_every_zone()
    {
        var fixture = SingleDisplayFixture([], SolidBgra(2, 1, 41), defaultOutcome: false);
        using var source = new Dx11ScreenshotFrameSource(fixture.Factory, fixture.PhysicalDisplays);
        using var cancellation = new CancellationTokenSource();
        cancellation.CancelAfter(TimeSpan.FromMilliseconds(20));

        var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() =>
            source.FreezeAllDisplaysAsync(TimeSpan.FromSeconds(1), cancellation.Token));

        Assert.Equal(ScreenshotCaptureFailureKind.Cancelled, exception.Kind);
        Assert.Equal(0, fixture.Capture.CopyCount);
        Assert.True(SpinWait.SpinUntil(
            () => fixture.Capture.DisposeCount == 1,
            TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public async Task Display_invalidation_cancels_the_active_session_and_discards_its_backend()
    {
        var fixture = SingleDisplayFixture([], SolidBgra(2, 1, 41), defaultOutcome: false);
        using var source = new Dx11ScreenshotFrameSource(fixture.Factory, fixture.PhysicalDisplays);
        var freeze = source.FreezeAllDisplaysAsync(TimeSpan.FromSeconds(1), CancellationToken.None);
        await Task.Delay(TimeSpan.FromMilliseconds(25));

        source.Invalidate(ScreenshotCaptureInvalidationReason.DisplayChange);
        var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() => freeze);

        Assert.Equal(ScreenshotCaptureFailureKind.Cancelled, exception.Kind);
        Assert.True(SpinWait.SpinUntil(
            () => fixture.Capture.DisposeCount == 1 && fixture.Backend.DisposeCount == 1,
            TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public void Readiness_enumerates_every_adapter_and_maps_each_device_name()
    {
        var adapter0 = Adapter(0);
        var adapter1 = Adapter(1);
        var display0 = Display(adapter0, "\\\\.\\DISPLAY1", width: 2, height: 1);
        var display1 = Display(adapter1, "\\\\.\\DISPLAY2", width: 1, height: 2);
        var backend = new FakeBackend(
            [adapter0, adapter1],
            new Dictionary<int, IReadOnlyList<Dx11DisplayDescriptor>>
            {
                [0] = [display0],
                [1] = [display1],
            },
            new Dictionary<string, Func<IDx11DisplayCapture>>());
        using var source = new Dx11ScreenshotFrameSource(
            new FakeBackendFactory(() => backend),
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(-2, 0, 2, 1), false),
                new("\\\\.\\DISPLAY2", new CapturePixelRect(0, 0, 1, 2), true),
            ]));

        var readiness = source.GetReadiness();

        Assert.Equal(ScreenshotCaptureReadinessStatus.Ready, readiness.Status);
        Assert.Equal(2, readiness.AdapterCount);
        Assert.Equal(2, readiness.MappedDisplayCount);
        Assert.Equal(new[] { 0, 1 }, backend.DisplayEnumerationAdapterIndices);
    }

    [Fact]
    public void Invalidation_disposes_the_whole_service_and_next_probe_reenumerates()
    {
        var factory = new FakeBackendFactory(() => SingleDisplayBackend());
        var displays = new FakePhysicalDisplayCatalog(
        [
            new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
        ]);
        using var source = new Dx11ScreenshotFrameSource(factory, displays);

        Assert.True(source.GetReadiness().IsReady);
        source.Invalidate(ScreenshotCaptureInvalidationReason.DisplayChange);
        Assert.True(source.GetReadiness().IsReady);

        Assert.Equal(2, factory.Backends.Count);
        Assert.Equal(1, factory.Backends[0].DisposeCount);
        Assert.Equal(0, factory.Backends[1].DisposeCount);
    }

    [Fact]
    public void Missing_dx11_delivery_asset_is_a_readiness_result_not_an_app_crash()
    {
        using var source = new Dx11ScreenshotFrameSource(
            new ThrowingBackendFactory(new FileNotFoundException("missing capture assembly")),
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
            ]));

        var readiness = source.GetReadiness();

        Assert.Equal(ScreenshotCaptureReadinessStatus.BackendUnavailable, readiness.Status);
    }

    [Fact]
    public async Task Prepared_zones_are_cleaned_when_a_later_display_cannot_initialize()
    {
        var adapter = Adapter(0);
        var firstDisplay = Display(adapter, "\\\\.\\DISPLAY1", 2, 1);
        var secondDisplay = Display(adapter, "\\\\.\\DISPLAY2", 2, 1, displayIndex: 1);
        var firstCapture = new FakeDisplayCapture(
            firstDisplay,
            [true],
            defaultOutcome: true,
            SolidBgra(2, 1, 5));
        var backend = new FakeBackend(
            [adapter],
            new Dictionary<int, IReadOnlyList<Dx11DisplayDescriptor>> { [0] = [firstDisplay, secondDisplay] },
            new Dictionary<string, Func<IDx11DisplayCapture>>
            {
                [firstDisplay.Id] = () => firstCapture,
                [secondDisplay.Id] = () => throw new InvalidOperationException("unavailable"),
            });
        using var source = new Dx11ScreenshotFrameSource(
            new FakeBackendFactory(() => backend),
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
                new("\\\\.\\DISPLAY2", new CapturePixelRect(2, 0, 2, 1), false),
            ]));

        var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() =>
            source.FreezeAllDisplaysAsync(
                TimeSpan.FromMilliseconds(100),
                CancellationToken.None));

        Assert.Equal(ScreenshotCaptureFailureKind.DeviceUnavailable, exception.Kind);
        Assert.Equal(1, firstCapture.DisposeCount);
        Assert.Equal(1, backend.DisposeCount);
    }

    [Fact]
    public async Task Hung_native_capture_opens_circuit_until_late_completion_then_recovers_and_releases()
    {
        var adapter = Adapter(0);
        var display = Display(adapter, "\\\\.\\DISPLAY1", 2, 1);
        var hungCapture = new BlockingDisplayCapture(display, SolidBgra(2, 1, 17));
        var firstBackend = BackendWithCapture(adapter, display, hungCapture);
        var secondBackend = SingleDisplayBackend();
        var backends = new Queue<FakeBackend>([firstBackend, secondBackend]);
        var factory = new FakeBackendFactory(() => backends.Dequeue());
        var circuitBreaker = new Dx11NativeCaptureCircuitBreaker();
        var source = new Dx11ScreenshotFrameSource(
            factory,
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
            ]),
            circuitBreaker);
        using var safetyRelease = new Timer(
            _ => hungCapture.Release(),
            null,
            TimeSpan.FromSeconds(2),
            Timeout.InfiniteTimeSpan);

        try
        {
            var freeze = source.FreezeAllDisplaysAsync(
                TimeSpan.FromMilliseconds(60),
                CancellationToken.None);
            Assert.True(hungCapture.Started.Wait(TimeSpan.FromSeconds(1)));
            var stopwatch = Stopwatch.StartNew();

            var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() => freeze);

            Assert.Equal(ScreenshotCaptureFailureKind.TimedOut, exception.Kind);
            // Bound is intentionally loose under suite load: still well below the 2s safety release.
            Assert.True(stopwatch.Elapsed < TimeSpan.FromMilliseconds(1500), stopwatch.Elapsed.ToString());
            Assert.Equal(0, hungCapture.DisposeCount);
            Assert.Equal(0, hungCapture.CopyCount);
            Assert.Equal(0, firstBackend.DisposeCount);

            stopwatch.Restart();
            Assert.Equal(
                ScreenshotCaptureReadinessStatus.BackendUnavailable,
                source.GetReadiness().Status);
            // Bound is intentionally loose under suite load: still well below the 2s safety release.
            Assert.True(stopwatch.Elapsed < TimeSpan.FromMilliseconds(1500), stopwatch.Elapsed.ToString());
            Assert.Single(factory.Backends);
        }
        finally
        {
            hungCapture.Release();
        }

        Assert.True(SpinWait.SpinUntil(
            () => hungCapture.DisposeCount == 1
                && firstBackend.DisposeCount == 1
                && !circuitBreaker.IsOpen,
            TimeSpan.FromSeconds(1)));
        Assert.False(hungCapture.SawUseAfterDispose);

        Assert.True(source.GetReadiness().IsReady);
        Assert.Equal(2, factory.Backends.Count);
        source.Dispose();
        Assert.Equal(1, secondBackend.DisposeCount);
    }

    [Fact]
    public async Task Process_circuit_rejects_repeated_cross_source_retries_without_new_workers_or_backends()
    {
        var adapter = Adapter(0);
        var display = Display(adapter, "\\\\.\\DISPLAY1", 2, 1);
        var hungCapture = new BlockingDisplayCapture(display, SolidBgra(2, 1, 19));
        var firstBackend = BackendWithCapture(adapter, display, hungCapture);
        var firstFactory = new FakeBackendFactory(() => firstBackend);
        var secondFactory = new FakeBackendFactory(SingleDisplayBackend);
        var displays = new FakePhysicalDisplayCatalog(
        [
            new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
        ]);
        var circuitBreaker = new Dx11NativeCaptureCircuitBreaker();
        var firstSource = new Dx11ScreenshotFrameSource(firstFactory, displays, circuitBreaker);
        using var secondSource = new Dx11ScreenshotFrameSource(secondFactory, displays, circuitBreaker);
        using var safetyRelease = new Timer(
            _ => hungCapture.Release(),
            null,
            TimeSpan.FromSeconds(2),
            Timeout.InfiniteTimeSpan);

        try
        {
            var freeze = firstSource.FreezeAllDisplaysAsync(
                TimeSpan.FromMilliseconds(60),
                CancellationToken.None);
            Assert.True(hungCapture.Started.Wait(TimeSpan.FromSeconds(1)));

            var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() => freeze);

            Assert.Equal(ScreenshotCaptureFailureKind.TimedOut, exception.Kind);
            for (var attempt = 0; attempt < 3; attempt++)
            {
                var retry = await Assert.ThrowsAsync<ScreenshotCaptureException>(() =>
                    secondSource.FreezeAllDisplaysAsync(
                        TimeSpan.FromMilliseconds(100),
                        CancellationToken.None));
                Assert.Equal(ScreenshotCaptureFailureKind.DeviceUnavailable, retry.Kind);
            }
            Assert.Equal(
                ScreenshotCaptureReadinessStatus.BackendUnavailable,
                secondSource.GetReadiness().Status);
            Assert.Single(firstFactory.Backends);
            Assert.Empty(secondFactory.Backends);
            Assert.Equal(1, hungCapture.TryCaptureCount);

            var stopwatch = Stopwatch.StartNew();
            firstSource.Dispose();
            // Bound is intentionally loose under suite load: still well below the 2s safety release.
            Assert.True(stopwatch.Elapsed < TimeSpan.FromMilliseconds(1500), stopwatch.Elapsed.ToString());
            Assert.Equal(0, hungCapture.DisposeCount);
            Assert.Equal(0, firstBackend.DisposeCount);
        }
        finally
        {
            hungCapture.Release();
            firstSource.Dispose();
        }

        Assert.True(SpinWait.SpinUntil(
            () => hungCapture.DisposeCount == 1
                && firstBackend.DisposeCount == 1
                && !circuitBreaker.IsOpen,
            TimeSpan.FromSeconds(1)));
        Assert.True(secondSource.GetReadiness().IsReady);
        Assert.Single(secondFactory.Backends);
        Assert.False(hungCapture.SawUseAfterDispose);
    }

    [Fact]
    public async Task Hung_first_candidate_does_not_consume_the_display_deadline_or_race_cleanup()
    {
        var firstAdapter = Adapter(0);
        var secondAdapter = Adapter(1);
        var firstDisplay = Display(firstAdapter, "\\\\.\\DISPLAY1", 2, 1);
        var secondDisplay = Display(secondAdapter, "\\\\.\\DISPLAY1", 2, 1);
        var hungCapture = new BlockingDisplayCapture(firstDisplay, SolidBgra(2, 1, 17));
        var healthyCapture = new FakeDisplayCapture(
            secondDisplay,
            [true],
            defaultOutcome: true,
            SolidBgra(2, 1, 61));
        var backend = new FakeBackend(
            [firstAdapter, secondAdapter],
            new Dictionary<int, IReadOnlyList<Dx11DisplayDescriptor>>
            {
                [firstAdapter.Index] = [firstDisplay],
                [secondAdapter.Index] = [secondDisplay],
            },
            new Dictionary<string, Func<IDx11DisplayCapture>>
            {
                [firstDisplay.Id] = () => hungCapture,
                [secondDisplay.Id] = () => healthyCapture,
            });
        var source = new Dx11ScreenshotFrameSource(
            new FakeBackendFactory(() => backend),
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
            ]));
        using var safetyRelease = new Timer(
            _ => hungCapture.Release(),
            null,
            TimeSpan.FromSeconds(2),
            Timeout.InfiniteTimeSpan);

        try
        {
            var stopwatch = Stopwatch.StartNew();
            var desktop = await source.FreezeAllDisplaysAsync(
                TimeSpan.FromSeconds(1),
                CancellationToken.None);

            Assert.True(stopwatch.Elapsed < TimeSpan.FromMilliseconds(1_500), stopwatch.Elapsed.ToString());
            Assert.True(hungCapture.Started.IsSet);
            Assert.Equal(61, Assert.Single(desktop.Frames).Bgra.Span[0]);
            Assert.Equal(1, healthyCapture.TryCaptureCount);
            Assert.Equal(1, healthyCapture.CopyCount);
            Assert.Equal(0, hungCapture.CopyCount);

            source.Dispose();
            Assert.Equal(0, hungCapture.DisposeCount);
            Assert.Equal(0, healthyCapture.DisposeCount);
            Assert.Equal(0, backend.DisposeCount);
        }
        finally
        {
            hungCapture.Release();
        }

        Assert.True(SpinWait.SpinUntil(
            () => hungCapture.DisposeCount == 1
                && healthyCapture.DisposeCount == 1
                && backend.DisposeCount == 1,
            TimeSpan.FromSeconds(1)));
        Assert.False(hungCapture.SawUseAfterDispose);
    }

    [Fact]
    public async Task Hung_native_capture_honors_cancellation_and_source_dispose_does_not_race_cleanup()
    {
        var adapter = Adapter(0);
        var display = Display(adapter, "\\\\.\\DISPLAY1", 2, 1);
        var hungCapture = new BlockingDisplayCapture(display, SolidBgra(2, 1, 29));
        var backend = BackendWithCapture(adapter, display, hungCapture);
        var source = new Dx11ScreenshotFrameSource(
            new FakeBackendFactory(() => backend),
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
            ]));
        using var cancellation = new CancellationTokenSource();
        using var safetyRelease = new Timer(
            _ => hungCapture.Release(),
            null,
            TimeSpan.FromSeconds(2),
            Timeout.InfiniteTimeSpan);

        try
        {
            var freeze = source.FreezeAllDisplaysAsync(TimeSpan.FromSeconds(5), cancellation.Token);
            Assert.True(hungCapture.Started.Wait(TimeSpan.FromSeconds(1)));
            var stopwatch = Stopwatch.StartNew();
            cancellation.Cancel();

            var exception = await Assert.ThrowsAsync<ScreenshotCaptureException>(() => freeze);

            Assert.Equal(ScreenshotCaptureFailureKind.Cancelled, exception.Kind);
            // Bound is intentionally loose under suite load: still well below the 2s safety release.
            Assert.True(stopwatch.Elapsed < TimeSpan.FromMilliseconds(1500), stopwatch.Elapsed.ToString());
            Assert.Equal(0, hungCapture.DisposeCount);
            Assert.Equal(0, backend.DisposeCount);

            stopwatch.Restart();
            source.Dispose();
            // Bound is intentionally loose under suite load: still well below the 2s safety release.
            Assert.True(stopwatch.Elapsed < TimeSpan.FromMilliseconds(1500), stopwatch.Elapsed.ToString());
            Assert.Equal(0, hungCapture.DisposeCount);
            Assert.Equal(0, backend.DisposeCount);
        }
        finally
        {
            hungCapture.Release();
        }

        Assert.True(SpinWait.SpinUntil(
            () => hungCapture.DisposeCount == 1 && backend.DisposeCount == 1,
            TimeSpan.FromSeconds(1)));
        Assert.False(hungCapture.SawUseAfterDispose);
        Assert.Equal(0, hungCapture.CopyCount);
    }

    private static CaptureFixture SingleDisplayFixture(
        IEnumerable<bool> outcomes,
        byte[] pixels,
        bool defaultOutcome = false)
    {
        var adapter = Adapter(0);
        var display = Display(adapter, "\\\\.\\DISPLAY1", width: 2, height: 1);
        var capture = new FakeDisplayCapture(display, outcomes, defaultOutcome, pixels);
        var backend = new FakeBackend(
            [adapter],
            new Dictionary<int, IReadOnlyList<Dx11DisplayDescriptor>> { [0] = [display] },
            new Dictionary<string, Func<IDx11DisplayCapture>> { [display.Id] = () => capture });
        return new CaptureFixture(
            new FakeBackendFactory(() => backend),
            backend,
            capture,
            new FakePhysicalDisplayCatalog(
            [
                new("\\\\.\\DISPLAY1", new CapturePixelRect(0, 0, 2, 1), true),
            ]));
    }

    private static FakeBackend SingleDisplayBackend()
    {
        var adapter = Adapter(0);
        var display = Display(adapter, "\\\\.\\DISPLAY1", 2, 1);
        return new FakeBackend(
            [adapter],
            new Dictionary<int, IReadOnlyList<Dx11DisplayDescriptor>> { [0] = [display] },
            new Dictionary<string, Func<IDx11DisplayCapture>>());
    }

    private static FakeBackend BackendWithCapture(
        Dx11AdapterDescriptor adapter,
        Dx11DisplayDescriptor display,
        IDx11DisplayCapture capture) =>
        new(
            [adapter],
            new Dictionary<int, IReadOnlyList<Dx11DisplayDescriptor>> { [adapter.Index] = [display] },
            new Dictionary<string, Func<IDx11DisplayCapture>> { [display.Id] = () => capture });

    private static Dx11AdapterDescriptor Adapter(int index) =>
        new(index, $"{index}:00001234:00005678", $"GPU {index}", 0x1234, 0x5678);

    private static Dx11DisplayDescriptor Display(
        Dx11AdapterDescriptor adapter,
        string deviceName,
        int width,
        int height,
        int displayIndex = 0) =>
        new($"{adapter.Id}:{displayIndex}:{deviceName}", deviceName, width, height, 0, adapter);

    private static byte[] SolidBgra(int width, int height, byte blue)
    {
        var pixels = new byte[checked(width * height * 4)];
        for (var index = 0; index < pixels.Length; index += 4)
        {
            pixels[index] = blue;
            pixels[index + 3] = byte.MaxValue;
        }
        return pixels;
    }

    private sealed record CaptureFixture(
        FakeBackendFactory Factory,
        FakeBackend Backend,
        FakeDisplayCapture Capture,
        FakePhysicalDisplayCatalog PhysicalDisplays);

    private sealed class FakePhysicalDisplayCatalog(IReadOnlyList<WindowsPhysicalDisplay> displays)
        : IWindowsPhysicalDisplayCatalog
    {
        public IReadOnlyList<WindowsPhysicalDisplay> GetActiveDisplays() => displays;
    }

    private sealed class FakeBackendFactory(Func<FakeBackend> create) : IDx11CaptureBackendFactory
    {
        public List<FakeBackend> Backends { get; } = [];

        public IDx11CaptureBackend Create()
        {
            var backend = create();
            Backends.Add(backend);
            return backend;
        }
    }

    private sealed class ThrowingBackendFactory(Exception exception) : IDx11CaptureBackendFactory
    {
        public IDx11CaptureBackend Create() => throw exception;
    }

    private sealed class FakeBackend(
        IReadOnlyList<Dx11AdapterDescriptor> adapters,
        IReadOnlyDictionary<int, IReadOnlyList<Dx11DisplayDescriptor>> displays,
        IReadOnlyDictionary<string, Func<IDx11DisplayCapture>> captures)
        : IDx11CaptureBackend
    {
        public List<int> DisplayEnumerationAdapterIndices { get; } = [];

        private int disposeCount;

        public int DisposeCount => Volatile.Read(ref disposeCount);

        public IReadOnlyList<Dx11AdapterDescriptor> GetAdapters() => adapters;

        public IReadOnlyList<Dx11DisplayDescriptor> GetDisplays(Dx11AdapterDescriptor adapter)
        {
            DisplayEnumerationAdapterIndices.Add(adapter.Index);
            return displays.TryGetValue(adapter.Index, out var result) ? result : [];
        }

        public IDx11DisplayCapture CreateDisplayCapture(
            Dx11DisplayDescriptor display,
            int nativeTimeoutMilliseconds)
        {
            Assert.Equal(Dx11ScreenshotFrameSource.NativeTimeoutMilliseconds, nativeTimeoutMilliseconds);
            return captures.TryGetValue(display.Id, out var createCapture)
                ? createCapture()
                : throw new InvalidOperationException("No capture was configured.");
        }

        public void Dispose() => Interlocked.Increment(ref disposeCount);
    }

    private sealed class FakeDisplayCapture : IDx11DisplayCapture
    {
        private readonly Queue<bool> outcomes;
        private readonly bool defaultOutcome;
        private readonly byte[] pixels;
        private int disposeCount;

        public FakeDisplayCapture(
            Dx11DisplayDescriptor display,
            IEnumerable<bool> outcomes,
            bool defaultOutcome,
            byte[] pixels)
        {
            Display = display;
            this.outcomes = new Queue<bool>(outcomes);
            this.defaultOutcome = defaultOutcome;
            this.pixels = pixels;
        }

        public Dx11DisplayDescriptor Display { get; }

        public int Width => Display.Width;

        public int Height => Display.Height;

        public int Stride => checked(Display.Width * 4);

        public int TryCaptureCount { get; private set; }

        public int CopyCount { get; private set; }

        public int DisposeCount => Volatile.Read(ref disposeCount);

        public bool TryCapture()
        {
            TryCaptureCount++;
            return outcomes.Count > 0 ? outcomes.Dequeue() : defaultOutcome;
        }

        public byte[] CopySuccessfulFrame()
        {
            CopyCount++;
            return pixels.ToArray();
        }

        public void Dispose() => Interlocked.Increment(ref disposeCount);
    }

    private sealed class BlockingDisplayCapture(
        Dx11DisplayDescriptor display,
        byte[] pixels) : IDx11DisplayCapture
    {
        private readonly ManualResetEventSlim release = new(initialState: false);
        private int copyCount;
        private int disposeCount;
        private int sawUseAfterDispose;
        private int tryCaptureCount;

        public ManualResetEventSlim Started { get; } = new(initialState: false);

        public Dx11DisplayDescriptor Display { get; } = display;

        public int Width => Display.Width;

        public int Height => Display.Height;

        public int Stride => checked(Display.Width * 4);

        public int CopyCount => Volatile.Read(ref copyCount);

        public int TryCaptureCount => Volatile.Read(ref tryCaptureCount);

        public int DisposeCount => Volatile.Read(ref disposeCount);

        public bool SawUseAfterDispose => Volatile.Read(ref sawUseAfterDispose) != 0;

        public bool TryCapture()
        {
            Interlocked.Increment(ref tryCaptureCount);
            Started.Set();
            release.Wait();
            RecordUseAfterDispose();
            return true;
        }

        public byte[] CopySuccessfulFrame()
        {
            RecordUseAfterDispose();
            Interlocked.Increment(ref copyCount);
            return pixels.ToArray();
        }

        public void Dispose() => Interlocked.Increment(ref disposeCount);

        public void Release() => release.Set();

        private void RecordUseAfterDispose()
        {
            if (DisposeCount != 0)
            {
                Interlocked.Exchange(ref sawUseAfterDispose, 1);
            }
        }
    }
}
