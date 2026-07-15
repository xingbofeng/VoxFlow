using System.Diagnostics;
using System.Runtime.ExceptionServices;

namespace VoxFlow.Windows.Platform.Screenshot;

public enum ScreenshotCaptureReadinessStatus
{
    Ready,
    NoActiveDisplays,
    NoDx11Adapters,
    DisplayMappingIncomplete,
    HybridGpuUnsupported,
    BackendUnavailable,
}

public sealed record ScreenshotCaptureReadiness(
    ScreenshotCaptureReadinessStatus Status,
    int ActiveDisplayCount,
    int MappedDisplayCount,
    int AdapterCount)
{
    public bool IsReady => Status == ScreenshotCaptureReadinessStatus.Ready;
}

public enum ScreenshotCaptureFailureKind
{
    NotReady,
    TimedOut,
    Cancelled,
    InvalidFrame,
    DeviceUnavailable,
}

public sealed class ScreenshotCaptureException : Exception
{
    public ScreenshotCaptureException(
        ScreenshotCaptureFailureKind kind,
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Kind = kind;
    }

    public ScreenshotCaptureFailureKind Kind { get; }
}

public enum ScreenshotCaptureInvalidationReason
{
    DisplayChange,
    DeviceChange,
    DesktopSwitch,
    SessionLock,
    ApplicationShutdown,
    CaptureFailure,
}

/// <summary>
/// Process-scoped owner for ScreenCapture.NET.DX11. The app composes one instance;
/// every invalidation discards the entire backend before the next screenshot begins.
/// </summary>
public sealed class Dx11ScreenshotFrameSource : IDisposable, IScreenshotCaptureInvalidationSink
{
    public const int NativeTimeoutMilliseconds = 75;
    public static readonly TimeSpan DefaultDeadline = TimeSpan.FromSeconds(1);

    private static readonly TimeSpan RetryDelay = TimeSpan.FromMilliseconds(8);
    private static readonly TimeSpan NativeWaitBudget = TimeSpan.FromMilliseconds(
        NativeTimeoutMilliseconds + 25);
    private static readonly Dx11NativeCaptureCircuitBreaker ProcessNativeCaptureCircuitBreaker = new();

    private readonly IDx11CaptureBackendFactory backendFactory;
    private readonly IWindowsPhysicalDisplayCatalog physicalDisplays;
    private readonly Dx11NativeCaptureCircuitBreaker nativeCaptureCircuitBreaker;
    private readonly SemaphoreSlim operationGate = new(1, 1);
    private readonly object stateLock = new();
    private BackendContext? backend;
    private CancellationTokenSource? activeSession;
    private bool backendInvalidated;
    private bool disposed;

    public static string CaptureDependencyVersion =>
        typeof(ScreenCapture.NET.DX11ScreenCaptureService)
            .Assembly
            .GetName()
            .Version?
            .ToString()
        ?? "unknown";

    public Dx11ScreenshotFrameSource()
        : this(
            ScreenCaptureNetDx11BackendFactory.Instance,
            WindowsPhysicalDisplayCatalog.Instance,
            ProcessNativeCaptureCircuitBreaker)
    {
    }

    internal Dx11ScreenshotFrameSource(
        IDx11CaptureBackendFactory backendFactory,
        IWindowsPhysicalDisplayCatalog physicalDisplays)
        : this(backendFactory, physicalDisplays, new Dx11NativeCaptureCircuitBreaker())
    {
    }

    internal Dx11ScreenshotFrameSource(
        IDx11CaptureBackendFactory backendFactory,
        IWindowsPhysicalDisplayCatalog physicalDisplays,
        Dx11NativeCaptureCircuitBreaker nativeCaptureCircuitBreaker)
    {
        this.backendFactory = backendFactory ?? throw new ArgumentNullException(nameof(backendFactory));
        this.physicalDisplays = physicalDisplays ?? throw new ArgumentNullException(nameof(physicalDisplays));
        this.nativeCaptureCircuitBreaker = nativeCaptureCircuitBreaker
            ?? throw new ArgumentNullException(nameof(nativeCaptureCircuitBreaker));
    }

    public ScreenshotCaptureReadiness GetReadiness()
    {
        ThrowIfDisposed();
        operationGate.Wait();
        try
        {
            ThrowIfDisposed();
            if (nativeCaptureCircuitBreaker.IsOpen)
            {
                MarkBackendInvalidated();
                return new ScreenshotCaptureReadiness(
                    ScreenshotCaptureReadinessStatus.BackendUnavailable,
                    ActiveDisplayCount: 0,
                    MappedDisplayCount: 0,
                    AdapterCount: 0);
            }
            var currentBackend = EnsureBackend();
            return BuildTopology(currentBackend.Backend).Readiness;
        }
        catch (Exception exception) when (IsExpectedPlatformFailure(exception))
        {
            MarkBackendInvalidated();
            return new ScreenshotCaptureReadiness(
                ScreenshotCaptureReadinessStatus.BackendUnavailable,
                ActiveDisplayCount: 0,
                MappedDisplayCount: 0,
                AdapterCount: 0);
        }
        finally
        {
            DisposeInvalidatedBackendIfIdle();
            operationGate.Release();
        }
    }

    public Task<FrozenDesktop> FreezeAllDisplaysAsync(CancellationToken cancellationToken = default) =>
        FreezeAllDisplaysAsync(DefaultDeadline, cancellationToken);

    public async Task<FrozenDesktop> FreezeAllDisplaysAsync(
        TimeSpan deadline,
        CancellationToken cancellationToken = default)
    {
        if (deadline <= TimeSpan.Zero || deadline > TimeSpan.FromSeconds(10))
        {
            throw new ArgumentOutOfRangeException(nameof(deadline));
        }

        ThrowIfDisposed();
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        CancellationTokenSource? session = null;
        var stopwatch = Stopwatch.StartNew();
        try
        {
            ThrowIfDisposed();
            if (nativeCaptureCircuitBreaker.IsOpen)
            {
                MarkBackendInvalidated();
                throw new ScreenshotCaptureException(
                    ScreenshotCaptureFailureKind.DeviceUnavailable,
                    "DX11 screenshot capture is quarantined until an earlier native call completes.");
            }
            session = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            lock (stateLock)
            {
                activeSession = session;
            }

            var currentBackend = EnsureBackend();
            var topology = BuildTopology(currentBackend.Backend);
            if (!topology.Readiness.IsReady)
            {
                throw new ScreenshotCaptureException(
                    ScreenshotCaptureFailureKind.NotReady,
                    $"DX11 screenshot capture is not ready ({topology.Readiness.Status}).");
            }

            var remaining = deadline - stopwatch.Elapsed;
            if (remaining <= TimeSpan.Zero)
            {
                throw new ScreenshotCaptureException(
                    ScreenshotCaptureFailureKind.TimedOut,
                    "DX11 screenshot capture timed out before frame acquisition began.");
            }

            var prepared = new List<PreparedDisplayCapture>(topology.Displays.Count);
            try
            {
                foreach (var display in topology.Displays)
                {
                    prepared.Add(PrepareDisplayCapture(currentBackend, display));
                }
                var tasks = prepared
                    .Select(display => CaptureDisplayAsync(display, remaining, session.Token))
                    .ToArray();
                var frames = await Task.WhenAll(tasks).ConfigureAwait(false);
                session.Token.ThrowIfCancellationRequested();
                return new FrozenDesktop(frames);
            }
            finally
            {
                foreach (var display in prepared)
                {
                    display.Dispose();
                }
            }
        }
        catch (OperationCanceledException exception)
        {
            MarkBackendInvalidated();
            throw new ScreenshotCaptureException(
                ScreenshotCaptureFailureKind.Cancelled,
                "DX11 screenshot capture was cancelled.",
                exception);
        }
        catch (ScreenshotCaptureException)
        {
            MarkBackendInvalidated();
            throw;
        }
        catch (Exception exception) when (IsExpectedPlatformFailure(exception))
        {
            MarkBackendInvalidated();
            throw new ScreenshotCaptureException(
                ScreenshotCaptureFailureKind.DeviceUnavailable,
                "DX11 screenshot capture could not acquire the desktop.",
                exception);
        }
        finally
        {
            if (session is not null)
            {
                lock (stateLock)
                {
                    if (ReferenceEquals(activeSession, session))
                    {
                        activeSession = null;
                    }
                }
                session.Dispose();
            }
            DisposeInvalidatedBackendIfIdle();
            operationGate.Release();
        }
    }

    public void Invalidate(ScreenshotCaptureInvalidationReason reason)
    {
        _ = reason;
        lock (stateLock)
        {
            if (disposed)
            {
                return;
            }
            backendInvalidated = true;
            activeSession?.Cancel();
        }
    }

    public void Dispose()
    {
        lock (stateLock)
        {
            if (disposed)
            {
                return;
            }
            disposed = true;
            backendInvalidated = true;
            activeSession?.Cancel();
        }

        operationGate.Wait();
        try
        {
            BackendContext? currentBackend;
            lock (stateLock)
            {
                currentBackend = backend;
                backend = null;
            }
            currentBackend?.RequestDispose();
        }
        finally
        {
            operationGate.Release();
            operationGate.Dispose();
        }
    }

    private BackendContext EnsureBackend()
    {
        BackendContext? staleBackend;
        BackendContext currentBackend;
        lock (stateLock)
        {
            if (backend is not null && !backendInvalidated)
            {
                return backend;
            }

            staleBackend = backend;
            currentBackend = new BackendContext(backendFactory.Create());
            backend = currentBackend;
            backendInvalidated = false;
        }
        staleBackend?.RequestDispose();
        return currentBackend;
    }

    private CaptureTopology BuildTopology(IDx11CaptureBackend currentBackend)
    {
        var activeDisplays = physicalDisplays.GetActiveDisplays();
        if (activeDisplays.Count == 0)
        {
            return CaptureTopology.NotReady(
                ScreenshotCaptureReadinessStatus.NoActiveDisplays,
                activeDisplayCount: 0,
                adapterCount: 0);
        }

        var adapters = currentBackend.GetAdapters();
        if (adapters.Count == 0)
        {
            return CaptureTopology.NotReady(
                ScreenshotCaptureReadinessStatus.NoDx11Adapters,
                activeDisplays.Count,
                adapterCount: 0);
        }

        var dx11Displays = adapters
            .SelectMany(adapter => currentBackend.GetDisplays(adapter))
            .ToArray();
        var mapped = new List<MappedDisplay>(activeDisplays.Count);
        foreach (var activeDisplay in activeDisplays)
        {
            var candidates = dx11Displays
                .Where(candidate => string.Equals(
                    WindowsPhysicalDisplayCatalog.NormalizeDeviceName(candidate.DeviceName),
                    activeDisplay.DeviceName,
                    StringComparison.OrdinalIgnoreCase))
                .Where(candidate =>
                    candidate.Width == activeDisplay.Bounds.Width
                    && candidate.Height == activeDisplay.Bounds.Height)
                .ToArray();
            if (candidates.Length > 0)
            {
                mapped.Add(new MappedDisplay(activeDisplay, candidates));
            }
        }

        var status = mapped.Count == activeDisplays.Count
            ? ScreenshotCaptureReadinessStatus.Ready
            : adapters.Count > 1
                ? ScreenshotCaptureReadinessStatus.HybridGpuUnsupported
                : ScreenshotCaptureReadinessStatus.DisplayMappingIncomplete;
        return new CaptureTopology(
            new ScreenshotCaptureReadiness(
                status,
                activeDisplays.Count,
                mapped.Count,
                adapters.Count),
            mapped);
    }

    private PreparedDisplayCapture PrepareDisplayCapture(
        BackendContext currentBackend,
        MappedDisplay display)
    {
        var backendLease = currentBackend.AcquireLease();
        var captures = new List<IDx11DisplayCapture>(display.Candidates.Count);
        try
        {
            foreach (var candidate in display.Candidates)
            {
                try
                {
                    captures.Add(currentBackend.Backend.CreateDisplayCapture(
                        candidate,
                        NativeTimeoutMilliseconds));
                }
                catch (Exception exception) when (IsExpectedPlatformFailure(exception))
                {
                    // A hybrid-GPU topology may expose an unusable duplicate output.
                    // Other candidates must still be attempted before readiness fails.
                }
            }

            if (captures.Count == 0)
            {
                throw new ScreenshotCaptureException(
                    ScreenshotCaptureFailureKind.DeviceUnavailable,
                    "No DX11 candidate could initialize an active display.");
            }
            return new PreparedDisplayCapture(
                display.Display,
                captures,
                backendLease,
                nativeCaptureCircuitBreaker,
                MarkBackendInvalidated);
        }
        catch
        {
            foreach (var capture in captures)
            {
                DisposeResourceBestEffort(capture);
            }
            DisposeResourceBestEffort(backendLease);
            throw;
        }
    }

    private static async Task<FrozenDisplayFrame> CaptureDisplayAsync(
        PreparedDisplayCapture prepared,
        TimeSpan deadline,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        var sawSuccessfulInvalidFrame = false;
        HashSet<IDx11DisplayCapture> unresponsiveCaptures = [];
        while (stopwatch.Elapsed < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            for (var captureIndex = 0; captureIndex < prepared.Captures.Count; captureIndex++)
            {
                var capture = prepared.Captures[captureIndex];
                cancellationToken.ThrowIfCancellationRequested();
                if (unresponsiveCaptures.Contains(capture))
                {
                    continue;
                }
                bool succeeded;
                try
                {
                    var remainingForNativeCall = deadline - stopwatch.Elapsed;
                    if (remainingForNativeCall <= TimeSpan.Zero)
                    {
                        break;
                    }
                    // A lone, valid output may need most of the deadline for its
                    // first desktop-duplication frame (especially when the screen
                    // is static). Only split the budget when Windows exposes
                    // duplicate hybrid-GPU candidates, reserving a fair share for
                    // every later candidate instead of letting the first hang
                    // starve them.
                    var candidatesRemaining = prepared.Captures.Count - captureIndex;
                    var fairCandidateBudget = candidatesRemaining == 1
                        ? remainingForNativeCall
                        : TimeSpan.FromTicks(Math.Max(
                            NativeWaitBudget.Ticks,
                            remainingForNativeCall.Ticks / candidatesRemaining));
                    succeeded = await prepared.TryCaptureAsync(
                            capture,
                            fairCandidateBudget < remainingForNativeCall
                                ? fairCandidateBudget
                                : remainingForNativeCall,
                            cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (TimeoutException)
                {
                    // A duplicate hybrid-GPU output must not consume the display's
                    // entire deadline or accumulate additional stuck native calls.
                    unresponsiveCaptures.Add(capture);
                    continue;
                }
                catch (Exception exception) when (IsExpectedPlatformFailure(exception))
                {
                    continue;
                }

                if (!succeeded)
                {
                    continue;
                }

                byte[] pixels;
                try
                {
                    pixels = capture.CopySuccessfulFrame();
                }
                catch (Exception exception) when (IsExpectedPlatformFailure(exception))
                {
                    sawSuccessfulInvalidFrame = true;
                    continue;
                }

                if (!IsValidOwnedFrame(capture, prepared.Display, pixels))
                {
                    sawSuccessfulInvalidFrame = true;
                    continue;
                }

                return new FrozenDisplayFrame(
                    prepared.Display.DeviceName,
                    capture.Display.Adapter.Id,
                    prepared.Display.Bounds,
                    capture.Display.RotationDegrees,
                    capture.Stride,
                    pixels);
            }

            var remaining = deadline - stopwatch.Elapsed;
            if (remaining > TimeSpan.Zero)
            {
                await Task.Delay(
                    remaining < RetryDelay ? remaining : RetryDelay,
                    cancellationToken).ConfigureAwait(false);
            }
        }

        throw new ScreenshotCaptureException(
            sawSuccessfulInvalidFrame
                ? ScreenshotCaptureFailureKind.InvalidFrame
                : ScreenshotCaptureFailureKind.TimedOut,
            sawSuccessfulInvalidFrame
                ? "DX11 returned an invalid or empty desktop frame."
                : "DX11 desktop frame acquisition timed out.");
    }

    private static bool IsValidOwnedFrame(
        IDx11DisplayCapture capture,
        WindowsPhysicalDisplay display,
        byte[] pixels)
    {
        if (capture.Width != display.Bounds.Width
            || capture.Height != display.Bounds.Height
            || capture.Stride < checked(capture.Width * 4)
            || pixels.Length < checked(capture.Stride * capture.Height))
        {
            return false;
        }

        // Failed/never-populated zones are all zero. Opaque fully black desktops remain valid.
        for (var offset = 0; offset < pixels.Length; offset += 4)
        {
            if (pixels[offset] != 0
                || pixels[offset + 1] != 0
                || pixels[offset + 2] != 0
                || pixels[offset + 3] != 0)
            {
                return true;
            }
        }
        return false;
    }

    private void MarkBackendInvalidated()
    {
        lock (stateLock)
        {
            backendInvalidated = true;
        }
    }

    private void DisposeInvalidatedBackendIfIdle()
    {
        BackendContext? invalidatedBackend = null;
        lock (stateLock)
        {
            if (!backendInvalidated || activeSession is not null)
            {
                return;
            }
            invalidatedBackend = backend;
            backend = null;
        }
        invalidatedBackend?.RequestDispose();
    }

    private void ThrowIfDisposed()
    {
        lock (stateLock)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
        }
    }

    private static bool IsExpectedPlatformFailure(Exception exception) => exception is
        ArgumentException or
        InvalidOperationException or
        NotSupportedException or
        ObjectDisposedException or
        TimeoutException or
        UnauthorizedAccessException or
        System.ComponentModel.Win32Exception or
        System.Runtime.InteropServices.ExternalException or
        SharpGen.Runtime.SharpGenException or
        FileNotFoundException or
        FileLoadException or
        BadImageFormatException or
        DllNotFoundException or
        EntryPointNotFoundException;

    private sealed record MappedDisplay(
        WindowsPhysicalDisplay Display,
        IReadOnlyList<Dx11DisplayDescriptor> Candidates);

    private sealed record CaptureTopology(
        ScreenshotCaptureReadiness Readiness,
        IReadOnlyList<MappedDisplay> Displays)
    {
        public static CaptureTopology NotReady(
            ScreenshotCaptureReadinessStatus status,
            int activeDisplayCount,
            int adapterCount) =>
            new(
                new ScreenshotCaptureReadiness(
                    status,
                    activeDisplayCount,
                    MappedDisplayCount: 0,
                    adapterCount),
                []);
    }

    private sealed class BackendContext
    {
        private readonly object gate = new();
        private int leaseCount;
        private bool disposalRequested;
        private bool disposed;

        public BackendContext(IDx11CaptureBackend backend)
        {
            Backend = backend ?? throw new ArgumentNullException(nameof(backend));
        }

        public IDx11CaptureBackend Backend { get; }

        public IDisposable AcquireLease()
        {
            lock (gate)
            {
                ObjectDisposedException.ThrowIf(disposalRequested || disposed, this);
                leaseCount++;
                return new BackendLease(this);
            }
        }

        public void RequestDispose()
        {
            var disposeNow = false;
            lock (gate)
            {
                if (disposalRequested)
                {
                    return;
                }
                disposalRequested = true;
                if (leaseCount == 0)
                {
                    disposed = true;
                    disposeNow = true;
                }
            }
            if (disposeNow)
            {
                DisposeBackend();
            }
        }

        private void Release()
        {
            var disposeNow = false;
            lock (gate)
            {
                if (leaseCount <= 0)
                {
                    return;
                }
                leaseCount--;
                if (leaseCount == 0 && disposalRequested && !disposed)
                {
                    disposed = true;
                    disposeNow = true;
                }
            }
            if (disposeNow)
            {
                DisposeBackend();
            }
        }

        private void DisposeBackend()
        {
            try
            {
                Backend.Dispose();
            }
            catch
            {
                // A quarantined native backend cannot be recovered; never fault a late task.
            }
        }

        private sealed class BackendLease(BackendContext owner) : IDisposable
        {
            private BackendContext? owner = owner;

            public void Dispose() => Interlocked.Exchange(ref owner, null)?.Release();
        }
    }

    private sealed class PreparedDisplayCapture : IDisposable
    {
        private readonly object gate = new();
        private readonly IDisposable backendLease;
        private readonly Dx11NativeCaptureCircuitBreaker nativeCaptureCircuitBreaker;
        private readonly Action onNativeOperationOrphaned;
        private int activeNativeOperations;
        private bool disposalRequested;
        private bool resourcesDisposed;

        public PreparedDisplayCapture(
            WindowsPhysicalDisplay display,
            IReadOnlyList<IDx11DisplayCapture> captures,
            IDisposable backendLease,
            Dx11NativeCaptureCircuitBreaker nativeCaptureCircuitBreaker,
            Action onNativeOperationOrphaned)
        {
            Display = display;
            Captures = captures;
            this.backendLease = backendLease;
            this.nativeCaptureCircuitBreaker = nativeCaptureCircuitBreaker;
            this.onNativeOperationOrphaned = onNativeOperationOrphaned;
        }

        public WindowsPhysicalDisplay Display { get; }

        public IReadOnlyList<IDx11DisplayCapture> Captures { get; }

        public async Task<bool> TryCaptureAsync(
            IDx11DisplayCapture capture,
            TimeSpan timeout,
            CancellationToken cancellationToken)
        {
            Task<NativeCaptureResult> nativeOperation;
            var circuitOperation = nativeCaptureCircuitBreaker.BeginNativeOperation();
            lock (gate)
            {
                ObjectDisposedException.ThrowIf(disposalRequested, this);
                activeNativeOperations++;
                try
                {
                    nativeOperation = Task.Factory.StartNew(
                        () =>
                        {
                            try
                            {
                                return new NativeCaptureResult(capture.TryCapture(), null);
                            }
                            catch (Exception exception)
                            {
                                return new NativeCaptureResult(false, exception);
                            }
                            finally
                            {
                                try
                                {
                                    CompleteNativeOperation();
                                }
                                finally
                                {
                                    circuitOperation.Complete();
                                }
                            }
                        },
                        CancellationToken.None,
                        TaskCreationOptions.DenyChildAttach | TaskCreationOptions.LongRunning,
                        TaskScheduler.Default);
                }
                catch
                {
                    activeNativeOperations--;
                    circuitOperation.Complete();
                    throw;
                }
            }

            NativeCaptureResult result;
            try
            {
                result = await nativeOperation.WaitAsync(timeout, cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (Exception exception) when (exception is TimeoutException or OperationCanceledException)
            {
                if (circuitOperation.MarkOrphaned())
                {
                    onNativeOperationOrphaned();
                }
                throw;
            }
            if (result.Exception is not null)
            {
                ExceptionDispatchInfo.Capture(result.Exception).Throw();
            }
            return result.Succeeded;
        }

        public void Dispose()
        {
            var disposeNow = false;
            lock (gate)
            {
                if (disposalRequested)
                {
                    return;
                }
                disposalRequested = true;
                if (activeNativeOperations == 0)
                {
                    resourcesDisposed = true;
                    disposeNow = true;
                }
            }
            if (disposeNow)
            {
                DisposeResources();
            }
        }

        private void CompleteNativeOperation()
        {
            var disposeNow = false;
            lock (gate)
            {
                activeNativeOperations--;
                if (activeNativeOperations == 0 && disposalRequested && !resourcesDisposed)
                {
                    resourcesDisposed = true;
                    disposeNow = true;
                }
            }
            if (disposeNow)
            {
                DisposeResources();
            }
        }

        private void DisposeResources()
        {
            foreach (var capture in Captures)
            {
                DisposeResourceBestEffort(capture);
            }
            DisposeResourceBestEffort(backendLease);
        }

        private sealed record NativeCaptureResult(bool Succeeded, Exception? Exception);
    }

    private static void DisposeResourceBestEffort(IDisposable resource)
    {
        try
        {
            resource.Dispose();
        }
        catch
        {
            // Retirement must continue through every capture and backend lease.
        }
    }
}

/// <summary>
/// Process-wide production instances share this circuit. A native desktop-duplication
/// call cannot be cancelled safely, so a timed-out worker owns the circuit until its
/// late completion has released every capture/backend lease.
/// </summary>
internal sealed class Dx11NativeCaptureCircuitBreaker
{
    private readonly object gate = new();
    private int orphanedOperationCount;

    public bool IsOpen
    {
        get
        {
            lock (gate)
            {
                return orphanedOperationCount != 0;
            }
        }
    }

    public NativeOperation BeginNativeOperation() => new(this);

    private void RegisterOrphan()
    {
        lock (gate)
        {
            orphanedOperationCount++;
        }
    }

    private void CompleteOrphan()
    {
        lock (gate)
        {
            if (orphanedOperationCount <= 0)
            {
                return;
            }
            orphanedOperationCount--;
        }
    }

    internal sealed class NativeOperation(Dx11NativeCaptureCircuitBreaker owner)
    {
        private readonly object gate = new();
        private bool orphaned;
        private bool completed;

        public bool MarkOrphaned()
        {
            lock (gate)
            {
                if (completed || orphaned)
                {
                    return false;
                }
                owner.RegisterOrphan();
                orphaned = true;
                return true;
            }
        }

        public void Complete()
        {
            var completeOrphan = false;
            lock (gate)
            {
                if (completed)
                {
                    return;
                }
                completed = true;
                completeOrphan = orphaned;
            }
            if (completeOrphan)
            {
                owner.CompleteOrphan();
            }
        }
    }
}
