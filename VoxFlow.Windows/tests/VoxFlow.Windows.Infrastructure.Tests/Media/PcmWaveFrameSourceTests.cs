using VoxFlow.Windows.Infrastructure.Media;

namespace VoxFlow.Windows.Infrastructure.Tests.Media;

public sealed class PcmWaveFrameSourceTests
{
    [Fact]
    public async Task Reads_only_the_pcm_data_as_bounded_even_sized_frames()
    {
        var source = new PcmWaveFrameSource(frameSizeBytes: 4_096);
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "TestResources",
            "FileTranscriptionMedia",
            "tone.wav");
        var frames = new List<byte[]>();

        await foreach (var frame in source.ReadFramesAsync(path, CancellationToken.None))
        {
            frames.Add(frame.ToArray());
        }

        Assert.Equal(6_400, frames.Sum(frame => frame.Length));
        Assert.All(frames, frame =>
        {
            Assert.InRange(frame.Length, 1, 4_096);
            Assert.Equal(0, frame.Length % 2);
        });
        Assert.Equal(2, frames.Count);
    }

    [Fact]
    public async Task Rejects_wav_that_is_not_sixteen_kilohertz_mono_pcm16()
    {
        var path = Path.Combine(Path.GetTempPath(), $"voxflow-invalid-{Guid.NewGuid():N}.wav");
        try
        {
            await File.WriteAllBytesAsync(path, CreateWaveHeader(sampleRate: 44_100));
            var source = new PcmWaveFrameSource();

            await Assert.ThrowsAsync<InvalidDataException>(async () =>
            {
                await foreach (var _ in source.ReadFramesAsync(path, CancellationToken.None))
                {
                }
            });
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static byte[] CreateWaveHeader(int sampleRate)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8);
        writer.Write(38);
        writer.Write("WAVE"u8);
        writer.Write("fmt "u8);
        writer.Write(16);
        writer.Write((ushort)1);
        writer.Write((ushort)1);
        writer.Write(sampleRate);
        writer.Write(sampleRate * 2);
        writer.Write((ushort)2);
        writer.Write((ushort)16);
        writer.Write("data"u8);
        writer.Write(2);
        writer.Write((short)0);
        return stream.ToArray();
    }
}
