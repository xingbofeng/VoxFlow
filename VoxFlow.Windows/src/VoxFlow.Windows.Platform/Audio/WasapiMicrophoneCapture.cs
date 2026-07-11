using System.Runtime.InteropServices;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace VoxFlow.Windows.Platform.Audio;

public sealed record AudioCapturePolicyOptions(
    bool MutePlaybackDuringRecording,
    bool FeedbackSounds,
    bool VoiceEnhancement,
    bool KeepMicrophoneActive)
{
    public static AudioCapturePolicyOptions Default { get; } = new(
        MutePlaybackDuringRecording: false,
        FeedbackSounds: true,
        VoiceEnhancement: true,
        KeepMicrophoneActive: false);
}

public interface IWasapiMicrophoneCaptureBackend : IAsyncDisposable
{
    event EventHandler<Exception>? CaptureFailed;

    ValueTask StartAsync(
        string? requestedDeviceId,
        AudioCapturePolicyOptions options,
        CancellationToken cancellationToken);

    ValueTask StopAsync(CancellationToken cancellationToken);

    ValueTask<AudioFrame> ReadFrameAsync(CancellationToken cancellationToken);
}

public sealed class WasapiMicrophoneCapture : IWasapiMicrophoneCaptureBackend
{
    private const string PcmSubFormat = "00000001-0000-0010-8000-00aa00389b71";
    private const string FloatSubFormat = "00000003-0000-0010-8000-00aa00389b71";

    private readonly object syncRoot = new();
    private readonly object enhancementGate = new();
    private readonly LatestAudioFrameQueue frames = new(capacity: 96);
    private readonly SpeechEnhancementFilter speechEnhancer = new(
        sampleRate: 16_000,
        cutoffHertz: 80);
    private AudioFormatGuard formatGuard = new();
    private WasapiCapture? capture;
    private MMDevice? captureDevice;
    private PlaybackMuteLease? muteLease;
    private AudioCapturePolicyOptions policy = AudioCapturePolicyOptions.Default;
    private long sequence;
    private bool acceptsFrames;
    private bool disposed;

    public event EventHandler<Exception>? CaptureFailed;

    public long DroppedFrameCount => frames.DroppedFrameCount;

    /// <summary>
    /// In shared mode Windows applies the capture endpoint's configured audio
    /// effects. This records whether that best-effort voice-enhancement path
    /// was requested so UI and diagnostics never claim a guaranteed DSP.
    /// </summary>
    public bool VoiceEnhancementRequested
    {
        get
        {
            lock (syncRoot)
            {
                return policy.VoiceEnhancement;
            }
        }
    }

    public bool IsKeepingMicrophoneActive
    {
        get
        {
            lock (syncRoot)
            {
                return capture is not null && !acceptsFrames && policy.KeepMicrophoneActive;
            }
        }
    }

    public static IReadOnlyList<AudioDeviceInfo> EnumerateDevices()
    {
        using var enumerator = new MMDeviceEnumerator();
        string? defaultId = null;
        if (enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Communications))
        {
            using var defaultEndpoint = enumerator.GetDefaultAudioEndpoint(
                DataFlow.Capture,
                Role.Communications);
            defaultId = defaultEndpoint.ID;
        }

        var endpoints = enumerator.EnumerateAudioEndPoints(
            DataFlow.Capture,
            DeviceState.Active | DeviceState.Disabled | DeviceState.Unplugged);
        List<AudioDeviceInfo> result = [];
        foreach (var device in endpoints)
        {
            using (device)
            {
                result.Add(new AudioDeviceInfo(
                    device.ID,
                    device.FriendlyName,
                    string.Equals(device.ID, defaultId, StringComparison.Ordinal),
                    device.State == DeviceState.Active));
            }
        }

        return result;
    }

    public ValueTask StartAsync(
        string? requestedDeviceId,
        AudioCapturePolicyOptions options,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        cancellationToken.ThrowIfCancellationRequested();
        lock (syncRoot)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            policy = options;
            lock (enhancementGate)
            {
                speechEnhancer.Reset();
            }
            if (capture is null || !DeviceMatches(requestedDeviceId))
            {
                DisposeCaptureUnsafe();
                CreateCaptureUnsafe(requestedDeviceId);
            }

            acceptsFrames = true;
            if (policy.MutePlaybackDuringRecording)
            {
                muteLease ??= PlaybackMuteLease.TryAcquire();
            }

            if (capture!.CaptureState != CaptureState.Capturing)
            {
                capture.StartRecording();
            }
        }

        if (options.FeedbackSounds)
        {
            WindowsFeedbackSound.PlayStart();
        }

        return ValueTask.CompletedTask;
    }

    public ValueTask StopAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        AudioCapturePolicyOptions currentPolicy;
        lock (syncRoot)
        {
            if (disposed)
            {
                return ValueTask.CompletedTask;
            }

            currentPolicy = policy;
            acceptsFrames = false;
            muteLease?.Dispose();
            muteLease = null;
            if (!policy.KeepMicrophoneActive)
            {
                DisposeCaptureUnsafe();
            }
        }

        if (currentPolicy.FeedbackSounds)
        {
            WindowsFeedbackSound.PlayStop();
        }

        return ValueTask.CompletedTask;
    }

    public ValueTask<AudioFrame> ReadFrameAsync(CancellationToken cancellationToken) =>
        frames.ReadAsync(cancellationToken);

    public async ValueTask DisposeAsync()
    {
        lock (syncRoot)
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            acceptsFrames = false;
            muteLease?.Dispose();
            muteLease = null;
            DisposeCaptureUnsafe();
        }

        await Task.CompletedTask.ConfigureAwait(false);
        GC.SuppressFinalize(this);
    }

    private bool DeviceMatches(string? requestedDeviceId)
    {
        if (captureDevice is null)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(requestedDeviceId))
        {
            var selected = AudioDeviceSelector.Select(null, EnumerateDevices());
            return string.Equals(captureDevice.ID, selected.Id, StringComparison.Ordinal);
        }

        return string.Equals(captureDevice.ID, requestedDeviceId, StringComparison.Ordinal);
    }

    private void CreateCaptureUnsafe(string? requestedDeviceId)
    {
        var selected = AudioDeviceSelector.Select(requestedDeviceId, EnumerateDevices());
        using var enumerator = new MMDeviceEnumerator();
        captureDevice = enumerator.GetDevice(selected.Id);
        capture = new WasapiCapture(
            captureDevice,
            useEventSync: true,
            audioBufferMillisecondsLength: 20)
        {
            ShareMode = AudioClientShareMode.Shared,
        };
        formatGuard = new AudioFormatGuard();
        capture.DataAvailable += OnDataAvailable;
        capture.RecordingStopped += OnRecordingStopped;
    }

    private void DisposeCaptureUnsafe()
    {
        if (capture is not null)
        {
            capture.DataAvailable -= OnDataAvailable;
            capture.RecordingStopped -= OnRecordingStopped;
            if (capture.CaptureState == CaptureState.Capturing)
            {
                capture.StopRecording();
            }

            capture.Dispose();
            capture = null;
        }

        captureDevice?.Dispose();
        captureDevice = null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        try
        {
            WasapiCapture? currentCapture;
            bool applyVoiceEnhancement;
            lock (syncRoot)
            {
                if (!acceptsFrames || disposed)
                {
                    return;
                }

                currentCapture = capture;
                applyVoiceEnhancement = policy.VoiceEnhancement;
            }

            if (currentCapture is null || e.BytesRecorded <= 0)
            {
                return;
            }

            var format = Describe(currentCapture.WaveFormat);
            formatGuard.Observe(format);
            var converted = Convert(e.Buffer, e.BytesRecorded, format);
            if (applyVoiceEnhancement)
            {
                lock (enhancementGate)
                {
                    converted = speechEnhancer.Process(converted);
                }
            }
            frames.Write(new AudioFrame(
                Interlocked.Increment(ref sequence) - 1,
                converted.PcmS16LittleEndian,
                converted.Rms));
        }
        catch (Exception exception)
        {
            lock (syncRoot)
            {
                acceptsFrames = false;
            }

            RaiseCaptureFailed(exception);
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception is not null)
        {
            RaiseCaptureFailed(e.Exception);
        }
    }

    private void RaiseCaptureFailed(Exception exception)
    {
        try
        {
            CaptureFailed?.Invoke(this, exception);
        }
        catch
        {
            // Capture callbacks cannot be allowed to tear down the WASAPI thread.
        }
    }

    private static AudioFormat Describe(WaveFormat waveFormat)
    {
        var encoding = waveFormat.Encoding switch
        {
            WaveFormatEncoding.IeeeFloat when waveFormat.BitsPerSample == 32 =>
                AudioSampleEncoding.Float32,
            WaveFormatEncoding.Pcm when waveFormat.BitsPerSample == 16 =>
                AudioSampleEncoding.PcmS16,
            WaveFormatEncoding.Extensible when waveFormat is WaveFormatExtensible extensible
                && extensible.SubFormat.ToString().Equals(FloatSubFormat, StringComparison.OrdinalIgnoreCase)
                && waveFormat.BitsPerSample == 32 => AudioSampleEncoding.Float32,
            WaveFormatEncoding.Extensible when waveFormat is WaveFormatExtensible extensible
                && extensible.SubFormat.ToString().Equals(PcmSubFormat, StringComparison.OrdinalIgnoreCase)
                && waveFormat.BitsPerSample == 16 => AudioSampleEncoding.PcmS16,
            _ => throw new NotSupportedException(
                $"Unsupported WASAPI capture format: {waveFormat.Encoding}, " +
                $"{waveFormat.BitsPerSample} bits."),
        };

        return new AudioFormat(waveFormat.SampleRate, waveFormat.Channels, encoding);
    }

    private static ConvertedAudioFrame Convert(
        byte[] buffer,
        int bytesRecorded,
        AudioFormat format)
    {
        if (format.Encoding == AudioSampleEncoding.Float32)
        {
            if (bytesRecorded % sizeof(float) != 0)
            {
                throw new InvalidDataException("Float32 WASAPI buffer is not sample aligned.");
            }

            var samples = new float[bytesRecorded / sizeof(float)];
            Buffer.BlockCopy(buffer, 0, samples, 0, bytesRecorded);
            return Pcm16MonoConverter.Convert(samples, format);
        }

        if (bytesRecorded % sizeof(short) != 0)
        {
            throw new InvalidDataException("PCM S16 WASAPI buffer is not sample aligned.");
        }

        var pcm = new short[bytesRecorded / sizeof(short)];
        Buffer.BlockCopy(buffer, 0, pcm, 0, bytesRecorded);
        return Pcm16MonoConverter.Convert(pcm, format);
    }

    private sealed class PlaybackMuteLease : IDisposable
    {
        private readonly MMDevice device;
        private readonly bool originalMute;
        private bool disposed;

        private PlaybackMuteLease(MMDevice device)
        {
            this.device = device;
            originalMute = device.AudioEndpointVolume.Mute;
            device.AudioEndpointVolume.Mute = true;
        }

        public static PlaybackMuteLease? TryAcquire()
        {
            try
            {
                using var enumerator = new MMDeviceEnumerator();
                if (!enumerator.HasDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia))
                {
                    return null;
                }

                return new PlaybackMuteLease(
                    enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia));
            }
            catch
            {
                return null;
            }
        }

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            try
            {
                device.AudioEndpointVolume.Mute = originalMute;
            }
            finally
            {
                device.Dispose();
            }
        }
    }

    private static partial class WindowsFeedbackSound
    {
        private const uint MbOk = 0;
        private const uint MbIconAsterisk = 0x40;

        public static void PlayStart() => _ = MessageBeep(MbIconAsterisk);

        public static void PlayStop() => _ = MessageBeep(MbOk);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool MessageBeep(uint type);
    }
}
