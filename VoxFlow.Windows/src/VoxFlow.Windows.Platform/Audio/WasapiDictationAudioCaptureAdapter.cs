using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Audio;

public sealed record WasapiDictationAudioOptions(
    string? DeviceId,
    AudioCapturePolicyOptions Policy)
{
    public static WasapiDictationAudioOptions Default { get; } = new(
        DeviceId: null,
        AudioCapturePolicyOptions.Default);
}

public sealed class WasapiDictationAudioCaptureAdapter :
    IDictationAudioCapture,
    IDictationAudioFailureSource,
    IAsyncDisposable
{
    private readonly SemaphoreSlim lifecycleGate = new(1, 1);
    private readonly IWasapiMicrophoneCaptureBackend backend;
    private readonly Func<WasapiDictationAudioOptions> optionsProvider;
    private CancellationTokenSource? pumpCancellation;
    private Task? pumpTask;
    private long capturedByteCount;
    private long capturedFrameCount;
    private int failurePublished;
    private bool running;
    private bool disposed;

    public WasapiDictationAudioCaptureAdapter(
        IWasapiMicrophoneCaptureBackend backend,
        Func<WasapiDictationAudioOptions> optionsProvider)
    {
        this.backend = backend ?? throw new ArgumentNullException(nameof(backend));
        this.optionsProvider = optionsProvider
            ?? throw new ArgumentNullException(nameof(optionsProvider));
        backend.CaptureFailed += OnBackendCaptureFailed;
    }

    public event EventHandler<VoxFlowError>? Failed;

    public long CapturedByteCount => Interlocked.Read(ref capturedByteCount);

    public long CapturedFrameCount => Interlocked.Read(ref capturedFrameCount);

    public async ValueTask StartAsync(
        Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(onFrame);
        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (running)
            {
                throw new InvalidOperationException("Audio capture is already running.");
            }

            var options = optionsProvider()
                ?? throw new InvalidOperationException("Audio capture options are unavailable.");
            pumpCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
            Interlocked.Exchange(ref capturedByteCount, 0);
            Interlocked.Exchange(ref capturedFrameCount, 0);
            Interlocked.Exchange(ref failurePublished, 0);
            try
            {
                await backend.StartAsync(
                        options.DeviceId,
                        options.Policy,
                        pumpCancellation.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                pumpCancellation.Dispose();
                pumpCancellation = null;
                throw;
            }
            catch (Exception exception)
            {
                pumpCancellation.Dispose();
                pumpCancellation = null;
                throw new DictationAudioCaptureException(
                    Classify(exception),
                    exception);
            }

            running = true;
            pumpTask = PumpFramesAsync(onFrame, pumpCancellation.Token);
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    public async ValueTask StopAsync(CancellationToken cancellationToken)
    {
        Task? pump;
        CancellationTokenSource? cancellation;
        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!running)
            {
                return;
            }

            running = false;
            pump = pumpTask;
            pumpTask = null;
            cancellation = pumpCancellation;
            pumpCancellation = null;
            cancellation?.Cancel();
            await backend.StopAsync(CancellationToken.None).ConfigureAwait(false);
        }
        finally
        {
            lifecycleGate.Release();
        }

        if (pump is not null)
        {
            try
            {
                await pump.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Expected when a recording is stopped or cancelled.
            }
        }

        cancellation?.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        await lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
        }
        finally
        {
            lifecycleGate.Release();
        }

        await StopAsync(CancellationToken.None).ConfigureAwait(false);
        backend.CaptureFailed -= OnBackendCaptureFailed;
        await backend.DisposeAsync().ConfigureAwait(false);
        lifecycleGate.Dispose();
    }

    private async Task PumpFramesAsync(
        Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
        CancellationToken cancellationToken)
    {
        try
        {
            while (true)
            {
                var frame = await backend.ReadFrameAsync(cancellationToken)
                    .ConfigureAwait(false);
                cancellationToken.ThrowIfCancellationRequested();
                Interlocked.Increment(ref capturedFrameCount);
                Interlocked.Add(ref capturedByteCount, frame.PcmS16LittleEndian.Length);
                await onFrame(frame.PcmS16LittleEndian, cancellationToken)
                    .ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal session stop.
        }
        catch (Exception exception)
        {
            PublishFailure(Classify(exception));
        }
    }

    private void OnBackendCaptureFailed(object? sender, Exception exception)
    {
        pumpCancellation?.Cancel();
        PublishFailure(Classify(exception));
    }

    private void PublishFailure(VoxFlowError error)
    {
        if (Interlocked.CompareExchange(ref failurePublished, 1, 0) != 0)
        {
            return;
        }

        try
        {
            Failed?.Invoke(this, error);
        }
        catch
        {
            // Audio callback threads cannot execute presentation failures.
        }
    }

    private static VoxFlowError Classify(Exception exception) => new(
        exception switch
        {
            AudioDeviceUnavailableException => VoxFlowErrorCode.AudioDeviceUnavailable,
            AudioFormatChangedException or InvalidDataException =>
                VoxFlowErrorCode.AudioFormatInvalid,
            UnauthorizedAccessException => VoxFlowErrorCode.MicrophonePermissionDenied,
            _ => VoxFlowErrorCode.Unknown,
        });
}
