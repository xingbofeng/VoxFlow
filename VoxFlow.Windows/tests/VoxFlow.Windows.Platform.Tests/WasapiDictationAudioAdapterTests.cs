using System.Threading.Channels;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Audio;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WasapiDictationAudioAdapterTests
{
    [Fact]
    public async Task Adapter_starts_selected_policy_pumps_real_queue_frames_and_stops_cleanly()
    {
        var backend = new FakeWasapiCaptureBackend();
        var options = new WasapiDictationAudioOptions(
            DeviceId: "usb-mic",
            new AudioCapturePolicyOptions(
                MutePlaybackDuringRecording: true,
                FeedbackSounds: false,
                VoiceEnhancement: true,
                KeepMicrophoneActive: true));
        await using var adapter = new WasapiDictationAudioCaptureAdapter(
            backend,
            () => options);
        var delivered = new TaskCompletionSource<ReadOnlyMemory<byte>>(
            TaskCreationOptions.RunContinuationsAsynchronously);

        await adapter.StartAsync(
            (frame, _) =>
            {
                delivered.TrySetResult(frame);
                return ValueTask.CompletedTask;
            },
            CancellationToken.None);
        backend.Enqueue(new AudioFrame(7, new byte[] { 1, 2, 3, 4 }, Rms: 0.25));

        Assert.Equal(
            new byte[] { 1, 2, 3, 4 },
            (await delivered.Task.WaitAsync(TimeSpan.FromSeconds(2))).ToArray());
        Assert.Equal("usb-mic", backend.RequestedDeviceId);
        Assert.Equal(options.Policy, backend.Policy);

        await adapter.StopAsync(CancellationToken.None);

        Assert.Equal(1, backend.StopCalls);
    }

    [Theory]
    [MemberData(nameof(CaptureFailures))]
    public async Task Backend_failure_is_classified_for_the_orchestrator(
        Exception exception,
        VoxFlowErrorCode expected)
    {
        var backend = new FakeWasapiCaptureBackend();
        await using var adapter = new WasapiDictationAudioCaptureAdapter(
            backend,
            () => WasapiDictationAudioOptions.Default);
        var failed = new TaskCompletionSource<VoxFlowError>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        ((IDictationAudioFailureSource)adapter).Failed += (_, error) =>
            failed.TrySetResult(error);
        await adapter.StartAsync((_, _) => ValueTask.CompletedTask, CancellationToken.None);

        backend.EmitFailure(exception);

        Assert.Equal(
            expected,
            (await failed.Task.WaitAsync(TimeSpan.FromSeconds(2))).Code);
    }

    public static TheoryData<Exception, VoxFlowErrorCode> CaptureFailures => new()
    {
        { new AudioDeviceUnavailableException("device removed"), VoxFlowErrorCode.AudioDeviceUnavailable },
        {
            new AudioFormatChangedException(
                new AudioFormat(48_000, 2, AudioSampleEncoding.Float32),
                new AudioFormat(44_100, 2, AudioSampleEncoding.Float32)),
            VoxFlowErrorCode.AudioFormatInvalid
        },
        { new UnauthorizedAccessException("privacy denied"), VoxFlowErrorCode.MicrophonePermissionDenied },
        { new InvalidOperationException("capture stopped"), VoxFlowErrorCode.Unknown },
    };

    private sealed class FakeWasapiCaptureBackend : IWasapiMicrophoneCaptureBackend
    {
        private readonly Channel<AudioFrame> frames = Channel.CreateUnbounded<AudioFrame>();

        public event EventHandler<Exception>? CaptureFailed;

        public string? RequestedDeviceId { get; private set; }

        public AudioCapturePolicyOptions? Policy { get; private set; }

        public int StopCalls { get; private set; }

        public ValueTask StartAsync(
            string? requestedDeviceId,
            AudioCapturePolicyOptions options,
            CancellationToken cancellationToken)
        {
            RequestedDeviceId = requestedDeviceId;
            Policy = options;
            return ValueTask.CompletedTask;
        }

        public ValueTask StopAsync(CancellationToken cancellationToken)
        {
            StopCalls++;
            return ValueTask.CompletedTask;
        }

        public ValueTask<AudioFrame> ReadFrameAsync(CancellationToken cancellationToken) =>
            frames.Reader.ReadAsync(cancellationToken);

        public ValueTask DisposeAsync()
        {
            frames.Writer.TryComplete();
            return ValueTask.CompletedTask;
        }

        public void Enqueue(AudioFrame frame) => frames.Writer.TryWrite(frame);

        public void EmitFailure(Exception exception) =>
            CaptureFailed?.Invoke(this, exception);
    }
}
