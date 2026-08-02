namespace VoxFlow.Windows.Platform.Audio;

public enum AudioSampleEncoding
{
    Float32,
    PcmS16,
}

public sealed record AudioFormat
{
    public AudioFormat(
        int sampleRate,
        int Channels,
        AudioSampleEncoding encoding)
    {
        if (sampleRate is < 8_000 or > 384_000)
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate));
        }

        if (Channels is < 1 or > 32)
        {
            throw new ArgumentOutOfRangeException(nameof(Channels));
        }

        SampleRate = sampleRate;
        this.Channels = Channels;
        Encoding = encoding;
    }

    public static AudioFormat AsrPcm16Mono { get; } = new(
        16_000,
        1,
        AudioSampleEncoding.PcmS16);

    public int SampleRate { get; }

    public int Channels { get; }

    public AudioSampleEncoding Encoding { get; }
}

public sealed record AudioDeviceInfo(
    string Id,
    string Name,
    bool IsDefault,
    bool IsAvailable);

public sealed class AudioDeviceUnavailableException(string message) : Exception(message);

public static class AudioDeviceSelector
{
    public static AudioDeviceInfo Select(
        string? requestedId,
        IReadOnlyList<AudioDeviceInfo> devices)
    {
        ArgumentNullException.ThrowIfNull(devices);
        var selected = !string.IsNullOrWhiteSpace(requestedId)
            ? devices.FirstOrDefault(device =>
                device.IsAvailable
                && string.Equals(device.Id, requestedId, StringComparison.Ordinal))
            : null;
        selected ??= devices.FirstOrDefault(device => device.IsAvailable && device.IsDefault);
        selected ??= devices.FirstOrDefault(device => device.IsAvailable);
        return selected ?? throw new AudioDeviceUnavailableException(
            "No available audio capture device was found.");
    }
}

public sealed class AudioFormatChangedException(
    AudioFormat expected,
    AudioFormat actual) : Exception("The capture device changed its audio format during a session.")
{
    public AudioFormat Expected { get; } = expected;

    public AudioFormat Actual { get; } = actual;
}

public sealed class AudioFormatGuard
{
    private AudioFormat? expected;

    public void Observe(AudioFormat format)
    {
        ArgumentNullException.ThrowIfNull(format);
        if (expected is null)
        {
            expected = format;
            return;
        }

        if (expected != format)
        {
            throw new AudioFormatChangedException(expected, format);
        }
    }
}

public sealed record ConvertedAudioFrame(
    byte[] PcmS16LittleEndian,
    AudioFormat Format,
    double Rms);

public sealed record AudioFrame(
    long Sequence,
    ReadOnlyMemory<byte> PcmS16LittleEndian,
    double Rms = 0);

public sealed class LatestAudioFrameQueue
{
    private readonly object syncRoot = new();
    private readonly Queue<AudioFrame> frames;
    private readonly SemaphoreSlim availableFrames = new(0);
    private readonly int capacity;

    public LatestAudioFrameQueue(int capacity)
    {
        if (capacity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(capacity));
        }

        this.capacity = capacity;
        frames = new Queue<AudioFrame>(capacity);
    }

    public long DroppedFrameCount { get; private set; }

    public void Write(AudioFrame frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        lock (syncRoot)
        {
            if (frames.Count == capacity)
            {
                _ = frames.Dequeue();
                DroppedFrameCount++;
            }
            else
            {
                availableFrames.Release();
            }

            frames.Enqueue(frame);
        }
    }

    public async ValueTask<AudioFrame> ReadAsync(CancellationToken cancellationToken)
    {
        await availableFrames.WaitAsync(cancellationToken).ConfigureAwait(false);
        lock (syncRoot)
        {
            return frames.Dequeue();
        }
    }

    public IReadOnlyList<AudioFrame> Drain()
    {
        lock (syncRoot)
        {
            var result = frames.ToArray();
            while (availableFrames.Wait(0))
            {
            }
            frames.Clear();
            return result;
        }
    }
}
