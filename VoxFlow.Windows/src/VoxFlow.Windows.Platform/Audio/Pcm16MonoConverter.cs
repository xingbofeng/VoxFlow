using System.Buffers.Binary;

namespace VoxFlow.Windows.Platform.Audio;

public static class Pcm16MonoConverter
{
    public static ConvertedAudioFrame Convert(
        float[] interleavedSamples,
        AudioFormat format)
    {
        ArgumentNullException.ThrowIfNull(interleavedSamples);
        ArgumentNullException.ThrowIfNull(format);
        if (format.Encoding != AudioSampleEncoding.Float32)
        {
            throw new ArgumentException("The format does not describe Float32 samples.", nameof(format));
        }

        ValidateFrameAlignment(interleavedSamples.Length, format.Channels);
        var mono = DownmixFloat(interleavedSamples, format.Channels);
        return Encode(Resample(mono, format.SampleRate));
    }

    public static ConvertedAudioFrame Convert(
        short[] interleavedSamples,
        AudioFormat format)
    {
        ArgumentNullException.ThrowIfNull(interleavedSamples);
        ArgumentNullException.ThrowIfNull(format);
        if (format.Encoding != AudioSampleEncoding.PcmS16)
        {
            throw new ArgumentException("The format does not describe PCM S16 samples.", nameof(format));
        }

        ValidateFrameAlignment(interleavedSamples.Length, format.Channels);
        if (format.SampleRate == AudioFormat.AsrPcm16Mono.SampleRate)
        {
            var exact = DownmixPcm16(interleavedSamples, format.Channels);
            return Encode(exact);
        }

        var normalized = DownmixPcm16(interleavedSamples, format.Channels)
            .Select(sample => sample / 32768F)
            .ToArray();
        return Encode(Resample(normalized, format.SampleRate));
    }

    private static float[] DownmixFloat(float[] input, int channels)
    {
        var output = new float[input.Length / channels];
        for (var frame = 0; frame < output.Length; frame++)
        {
            double sum = 0;
            for (var channel = 0; channel < channels; channel++)
            {
                sum += input[(frame * channels) + channel];
            }

            output[frame] = (float)(sum / channels);
        }

        return output;
    }

    private static short[] DownmixPcm16(short[] input, int channels)
    {
        var output = new short[input.Length / channels];
        for (var frame = 0; frame < output.Length; frame++)
        {
            long sum = 0;
            for (var channel = 0; channel < channels; channel++)
            {
                sum += input[(frame * channels) + channel];
            }

            output[frame] = (short)Math.Clamp(sum / channels, short.MinValue, short.MaxValue);
        }

        return output;
    }

    private static float[] Resample(float[] input, int sourceSampleRate)
    {
        const int targetSampleRate = 16_000;
        if (sourceSampleRate == targetSampleRate)
        {
            return input;
        }

        var outputLength = (int)Math.Round(
            input.Length * (double)targetSampleRate / sourceSampleRate,
            MidpointRounding.AwayFromZero);
        if (outputLength == 0)
        {
            return [];
        }

        var output = new float[outputLength];
        var sourceStep = sourceSampleRate / (double)targetSampleRate;
        for (var index = 0; index < outputLength; index++)
        {
            var sourcePosition = index * sourceStep;
            var left = Math.Min((int)sourcePosition, input.Length - 1);
            var right = Math.Min(left + 1, input.Length - 1);
            var fraction = sourcePosition - left;
            output[index] = (float)(input[left] + ((input[right] - input[left]) * fraction));
        }

        return output;
    }

    private static ConvertedAudioFrame Encode(float[] samples)
    {
        var pcm = new short[samples.Length];
        for (var index = 0; index < samples.Length; index++)
        {
            var clamped = Math.Clamp(samples[index], -1F, 1F);
            pcm[index] = clamped >= 0
                ? (short)Math.Round(clamped * short.MaxValue)
                : (short)Math.Round(clamped * -short.MinValue);
        }

        return Encode(pcm);
    }

    private static ConvertedAudioFrame Encode(short[] samples)
    {
        var bytes = new byte[samples.Length * sizeof(short)];
        double squareSum = 0;
        for (var index = 0; index < samples.Length; index++)
        {
            BinaryPrimitives.WriteInt16LittleEndian(
                bytes.AsSpan(index * sizeof(short), sizeof(short)),
                samples[index]);
            var normalized = samples[index] / 32768D;
            squareSum += normalized * normalized;
        }

        return new ConvertedAudioFrame(
            bytes,
            AudioFormat.AsrPcm16Mono,
            samples.Length == 0 ? 0 : Math.Sqrt(squareSum / samples.Length));
    }

    private static void ValidateFrameAlignment(int sampleCount, int channels)
    {
        if (sampleCount == 0 || sampleCount % channels != 0)
        {
            throw new ArgumentException("Interleaved audio must contain complete frames.");
        }
    }
}
