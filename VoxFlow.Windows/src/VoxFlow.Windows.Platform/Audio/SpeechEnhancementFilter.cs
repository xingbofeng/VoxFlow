using System.Buffers.Binary;

namespace VoxFlow.Windows.Platform.Audio;

/// <summary>
/// A conservative streaming high-pass filter for the optional voice-enhancement
/// setting. It removes DC offset and low-frequency microphone rumble without
/// changing timing, sample rate, or frame boundaries expected by ASR providers.
/// </summary>
public sealed class SpeechEnhancementFilter
{
    private readonly double alpha;
    private double previousInput;
    private double previousOutput;

    public SpeechEnhancementFilter(int sampleRate, double cutoffHertz)
    {
        if (sampleRate <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate));
        }

        if (!double.IsFinite(cutoffHertz)
            || cutoffHertz <= 0
            || cutoffHertz >= sampleRate / 2D)
        {
            throw new ArgumentOutOfRangeException(nameof(cutoffHertz));
        }

        var sampleInterval = 1D / sampleRate;
        var timeConstant = 1D / (2D * Math.PI * cutoffHertz);
        alpha = timeConstant / (timeConstant + sampleInterval);
    }

    public short[] Process(ReadOnlySpan<short> input)
    {
        var output = new short[input.Length];
        for (var index = 0; index < input.Length; index++)
        {
            var currentInput = input[index];
            var currentOutput = alpha
                * (previousOutput + currentInput - previousInput);
            previousInput = currentInput;
            previousOutput = currentOutput;
            output[index] = (short)Math.Clamp(
                Math.Round(currentOutput),
                short.MinValue,
                short.MaxValue);
        }

        return output;
    }

    public ConvertedAudioFrame Process(ConvertedAudioFrame frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        var bytes = frame.PcmS16LittleEndian;
        if (bytes.Length % sizeof(short) != 0)
        {
            throw new InvalidDataException("PCM S16 audio is not sample aligned.");
        }

        var samples = new short[bytes.Length / sizeof(short)];
        for (var index = 0; index < samples.Length; index++)
        {
            samples[index] = BinaryPrimitives.ReadInt16LittleEndian(
                bytes.AsSpan(index * sizeof(short), sizeof(short)));
        }

        var enhanced = Process(samples);
        var output = new byte[bytes.Length];
        double squareSum = 0;
        for (var index = 0; index < enhanced.Length; index++)
        {
            BinaryPrimitives.WriteInt16LittleEndian(
                output.AsSpan(index * sizeof(short), sizeof(short)),
                enhanced[index]);
            var normalized = enhanced[index] / 32768D;
            squareSum += normalized * normalized;
        }

        return new ConvertedAudioFrame(
            output,
            frame.Format,
            enhanced.Length == 0 ? 0 : Math.Sqrt(squareSum / enhanced.Length));
    }

    public void Reset()
    {
        previousInput = 0;
        previousOutput = 0;
    }
}
