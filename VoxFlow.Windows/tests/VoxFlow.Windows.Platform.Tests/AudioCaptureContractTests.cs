using System.Buffers.Binary;
using VoxFlow.Windows.Platform.Audio;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class AudioCaptureContractTests
{
    [Fact]
    public void Device_selection_prefers_requested_available_then_default_then_first_available()
    {
        AudioDeviceInfo[] devices =
        [
            new("usb", "USB microphone", IsDefault: false, IsAvailable: true),
            new("built-in", "Built-in microphone", IsDefault: true, IsAvailable: true),
            new("offline", "Disconnected", IsDefault: false, IsAvailable: false),
        ];

        Assert.Equal("usb", AudioDeviceSelector.Select("usb", devices).Id);
        Assert.Equal("built-in", AudioDeviceSelector.Select("offline", devices).Id);
        Assert.Equal("built-in", AudioDeviceSelector.Select("missing", devices).Id);
        Assert.Throws<AudioDeviceUnavailableException>(() =>
            AudioDeviceSelector.Select(null, devices.Where(device => !device.IsAvailable).ToArray()));
    }

    [Fact]
    public void Float_stereo_input_is_resampled_to_16khz_mono_pcm_s16le_with_rms()
    {
        const int inputRate = 48_000;
        const int milliseconds = 100;
        const float amplitude = 0.5F;
        var frameCount = inputRate * milliseconds / 1_000;
        var interleaved = new float[frameCount * 2];
        for (var frame = 0; frame < frameCount; frame++)
        {
            var sample = amplitude * MathF.Sin(2 * MathF.PI * 1_000 * frame / inputRate);
            interleaved[frame * 2] = sample;
            interleaved[(frame * 2) + 1] = sample;
        }

        var converted = Pcm16MonoConverter.Convert(
            interleaved,
            new AudioFormat(inputRate, Channels: 2, AudioSampleEncoding.Float32));

        Assert.Equal(AudioFormat.AsrPcm16Mono, converted.Format);
        Assert.Equal(1_600, converted.PcmS16LittleEndian.Length / sizeof(short));
        Assert.InRange(converted.Rms, 0.34, 0.36);
        Assert.Equal(
            0,
            BinaryPrimitives.ReadInt16LittleEndian(converted.PcmS16LittleEndian.AsSpan(0, 2)));
    }

    [Fact]
    public void Pcm16_stereo_is_downmixed_and_clamped_in_little_endian_order()
    {
        short[] input =
        [
            short.MaxValue, short.MaxValue,
            short.MinValue, short.MinValue,
            16_000, -8_000,
        ];

        var converted = Pcm16MonoConverter.Convert(
            input,
            new AudioFormat(16_000, Channels: 2, AudioSampleEncoding.PcmS16));
        var output = converted.PcmS16LittleEndian;

        Assert.Equal(short.MaxValue, BinaryPrimitives.ReadInt16LittleEndian(output.AsSpan(0, 2)));
        Assert.Equal(short.MinValue, BinaryPrimitives.ReadInt16LittleEndian(output.AsSpan(2, 2)));
        Assert.Equal(4_000, BinaryPrimitives.ReadInt16LittleEndian(output.AsSpan(4, 2)));
    }

    [Fact]
    public void Capture_format_change_fails_the_session_instead_of_reinterpreting_bytes()
    {
        var guard = new AudioFormatGuard();
        guard.Observe(new AudioFormat(48_000, 2, AudioSampleEncoding.Float32));

        var exception = Assert.Throws<AudioFormatChangedException>(() =>
            guard.Observe(new AudioFormat(44_100, 2, AudioSampleEncoding.Float32)));

        Assert.Equal(48_000, exception.Expected.SampleRate);
        Assert.Equal(44_100, exception.Actual.SampleRate);
    }

    [Fact]
    public void Ninety_six_frame_backpressure_keeps_latest_and_counts_drops()
    {
        var queue = new LatestAudioFrameQueue(capacity: 96);
        for (var sequence = 0; sequence < 120; sequence++)
        {
            queue.Write(new AudioFrame(sequence, new byte[] { (byte)sequence }));
        }

        var retained = queue.Drain();

        Assert.Equal(96, retained.Count);
        Assert.Equal(24, queue.DroppedFrameCount);
        Assert.Equal(24, retained[0].Sequence);
        Assert.Equal(119, retained[^1].Sequence);
    }

    [Fact]
    public void Voice_enhancement_removes_low_frequency_dc_without_mutating_input()
    {
        var enhancer = new SpeechEnhancementFilter(sampleRate: 16_000, cutoffHertz: 80);
        var input = Enumerable.Repeat((short)12_000, 16_000).ToArray();
        var original = input.ToArray();

        var enhanced = enhancer.Process(input);

        Assert.Equal(original, input);
        Assert.Equal(input.Length, enhanced.Length);
        Assert.InRange(Math.Abs(enhanced[^1]), 0, 2);
        Assert.NotEqual(input, enhanced);
    }

    [Fact]
    public void Voice_enhancement_keeps_streaming_state_across_audio_frames_and_can_reset()
    {
        var enhancer = new SpeechEnhancementFilter(sampleRate: 16_000, cutoffHertz: 80);
        var first = enhancer.Process(Enumerable.Repeat((short)10_000, 8_000).ToArray());
        var second = enhancer.Process(Enumerable.Repeat((short)10_000, 320).ToArray());

        Assert.InRange(Math.Abs(first[^1]), 0, 2);
        Assert.InRange(Math.Abs(second[0]), 0, 2);

        enhancer.Reset();
        var afterReset = enhancer.Process(Enumerable.Repeat((short)10_000, 320).ToArray());
        Assert.True(Math.Abs(afterReset[0]) > 9_000);
    }
}
