using System.Runtime.CompilerServices;
using System.Text;
using VoxFlow.Windows.Application.FileTranscription;

namespace VoxFlow.Windows.Infrastructure.Media;

public sealed class PcmWaveFrameSource : IFileTranscriptionPcmFrameSource
{
    private const ushort PcmFormat = 1;
    private const ushort RequiredChannels = 1;
    private const int RequiredSampleRate = 16_000;
    private const ushort RequiredBitsPerSample = 16;
    private const ushort RequiredBlockAlignment = 2;
    private readonly int frameSizeBytes;

    public PcmWaveFrameSource(int frameSizeBytes = 4_096)
    {
        if (frameSizeBytes <= 0 || frameSizeBytes % RequiredBlockAlignment != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(frameSizeBytes));
        }

        this.frameSizeBytes = frameSizeBytes;
    }

    public async IAsyncEnumerable<ReadOnlyMemory<byte>> ReadFramesAsync(
        string audioPath,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(audioPath);
        await using var stream = new FileStream(
            audioPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: frameSizeBytes,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        using var reader = new BinaryReader(stream, Encoding.UTF8, leaveOpen: true);
        var data = ReadAndValidateHeader(reader, stream);
        stream.Position = data.Offset;

        var remaining = data.Length;
        while (remaining > 0)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var count = (int)Math.Min(frameSizeBytes, remaining);
            var frame = new byte[count];
            await stream.ReadExactlyAsync(frame, cancellationToken).ConfigureAwait(false);
            remaining -= count;
            yield return frame;
        }
    }

    private static WaveDataChunk ReadAndValidateHeader(
        BinaryReader reader,
        FileStream stream)
    {
        if (ReadFourCc(reader) != "RIFF")
        {
            throw InvalidWave();
        }

        _ = reader.ReadUInt32();
        if (ReadFourCc(reader) != "WAVE")
        {
            throw InvalidWave();
        }

        WaveFormat? format = null;
        WaveDataChunk? data = null;
        while (stream.Position + 8 <= stream.Length)
        {
            var chunkId = ReadFourCc(reader);
            var chunkLength = reader.ReadUInt32();
            var chunkOffset = stream.Position;
            if (chunkLength > stream.Length - chunkOffset)
            {
                throw InvalidWave();
            }

            if (chunkId == "fmt ")
            {
                if (chunkLength < 16)
                {
                    throw InvalidWave();
                }

                var formatTag = reader.ReadUInt16();
                var channels = reader.ReadUInt16();
                var sampleRate = reader.ReadInt32();
                _ = reader.ReadInt32();
                var blockAlignment = reader.ReadUInt16();
                var bitsPerSample = reader.ReadUInt16();
                format = new WaveFormat(
                    formatTag,
                    channels,
                    sampleRate,
                    blockAlignment,
                    bitsPerSample);
            }
            else if (chunkId == "data")
            {
                data = new WaveDataChunk(chunkOffset, chunkLength);
            }

            var nextChunk = chunkOffset + chunkLength + (chunkLength % 2);
            if (nextChunk > stream.Length)
            {
                throw InvalidWave();
            }
            stream.Position = nextChunk;
            if (format is not null && data is not null)
            {
                break;
            }
        }

        if (format is null
            || data is null
            || format.FormatTag != PcmFormat
            || format.Channels != RequiredChannels
            || format.SampleRate != RequiredSampleRate
            || format.BitsPerSample != RequiredBitsPerSample
            || format.BlockAlignment != RequiredBlockAlignment
            || data.Length % RequiredBlockAlignment != 0)
        {
            throw InvalidWave();
        }

        return data;
    }

    private static string ReadFourCc(BinaryReader reader)
    {
        var bytes = reader.ReadBytes(4);
        if (bytes.Length != 4)
        {
            throw InvalidWave();
        }
        return Encoding.ASCII.GetString(bytes);
    }

    private static InvalidDataException InvalidWave() => new(
        "Expected a 16 kHz mono PCM16 WAV prepared by the bundled FFmpeg runtime.");

    private sealed record WaveFormat(
        ushort FormatTag,
        ushort Channels,
        int SampleRate,
        ushort BlockAlignment,
        ushort BitsPerSample);

    private sealed record WaveDataChunk(long Offset, long Length);
}
