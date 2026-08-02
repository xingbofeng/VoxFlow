using System.Buffers.Binary;
using System.IO.Compression;

namespace VoxFlow.Windows.Providers.Cloud.Volcengine;

public enum VolcengineMessageType : byte
{
    FullClientRequest = 0x1,
    AudioOnlyRequest = 0x2,
    FullServerResponse = 0x9,
    ServerAck = 0xB,
    ServerErrorResponse = 0xF,
}

public enum VolcengineMessageFlags : byte
{
    NoSequence = 0x0,
    PositiveSequence = 0x1,
    NegativeSequence = 0x2,
    NegativeSequenceWithValue = 0x3,
}

public enum VolcengineSerialization : byte
{
    None = 0x0,
    Json = 0x1,
}

public enum VolcengineCompression : byte
{
    None = 0x0,
    Gzip = 0x1,
}

/// <summary>
/// Codec for the Seed binary framing used by Volcengine big-model streaming ASR.
/// Current endpoint and protocol provenance:
/// https://www.volcengine.com/docs/6561/1395846
/// </summary>
public sealed class VolcengineProtocolFrame
{
    private const byte ProtocolVersion = 1;
    private const byte HeaderWords = 1;
    private const int MaxDecodedPayloadBytes = 4 * 1024 * 1024;
    private readonly byte[] payload;

    private VolcengineProtocolFrame(
        VolcengineMessageType messageType,
        VolcengineMessageFlags flags,
        VolcengineSerialization serialization,
        VolcengineCompression compression,
        int? sequence,
        byte[] payload)
    {
        MessageType = messageType;
        Flags = flags;
        Serialization = serialization;
        Compression = compression;
        Sequence = sequence;
        this.payload = payload;
    }

    public VolcengineMessageType MessageType { get; }

    public VolcengineMessageFlags Flags { get; }

    public VolcengineSerialization Serialization { get; }

    public VolcengineCompression Compression { get; }

    public int? Sequence { get; }

    public byte[] Payload => payload.ToArray();

    public bool IsFinal => Flags is
        VolcengineMessageFlags.NegativeSequence or
        VolcengineMessageFlags.NegativeSequenceWithValue;

    public static byte[] EncodeFullClientRequest(
        ReadOnlySpan<byte> jsonPayload,
        int sequence = 1) => Encode(
            VolcengineMessageType.FullClientRequest,
            VolcengineMessageFlags.PositiveSequence,
            VolcengineSerialization.Json,
            VolcengineCompression.Gzip,
            sequence,
            jsonPayload);

    public static byte[] EncodeAudioOnlyRequest(
        ReadOnlySpan<byte> pcmS16LittleEndian,
        int sequence)
    {
        if (sequence <= 1)
        {
            throw new ArgumentOutOfRangeException(nameof(sequence));
        }

        return Encode(
            VolcengineMessageType.AudioOnlyRequest,
            VolcengineMessageFlags.PositiveSequence,
            VolcengineSerialization.None,
            VolcengineCompression.Gzip,
            sequence,
            pcmS16LittleEndian);
    }

    public static byte[] EncodeFinalAudioRequest() => Encode(
        VolcengineMessageType.AudioOnlyRequest,
        VolcengineMessageFlags.NegativeSequence,
        VolcengineSerialization.None,
        VolcengineCompression.None,
        sequence: null,
        ReadOnlySpan<byte>.Empty);

    public static VolcengineProtocolFrame Decode(byte[] encoded)
    {
        ArgumentNullException.ThrowIfNull(encoded);
        return Decode(encoded.AsSpan());
    }

    public static VolcengineProtocolFrame Decode(ReadOnlySpan<byte> encoded)
    {
        if (encoded.Length < 8)
        {
            throw new InvalidDataException("Volcengine frame is too short.");
        }

        var version = encoded[0] >> 4;
        var headerBytes = (encoded[0] & 0x0F) * 4;
        if (version != ProtocolVersion
            || headerBytes < 4
            || headerBytes > encoded.Length)
        {
            throw new InvalidDataException("Volcengine frame header is invalid.");
        }

        if (!Enum.IsDefined((VolcengineMessageType)(encoded[1] >> 4))
            || !Enum.IsDefined((VolcengineMessageFlags)(encoded[1] & 0x0F))
            || !Enum.IsDefined((VolcengineSerialization)(encoded[2] >> 4))
            || !Enum.IsDefined((VolcengineCompression)(encoded[2] & 0x0F)))
        {
            throw new InvalidDataException("Volcengine frame flags are invalid.");
        }

        var messageType = (VolcengineMessageType)(encoded[1] >> 4);
        var flags = (VolcengineMessageFlags)(encoded[1] & 0x0F);
        var serialization = (VolcengineSerialization)(encoded[2] >> 4);
        var compression = (VolcengineCompression)(encoded[2] & 0x0F);
        var cursor = headerBytes;
        int? sequence = null;
        if (flags is VolcengineMessageFlags.PositiveSequence
            or VolcengineMessageFlags.NegativeSequenceWithValue)
        {
            if (encoded.Length < cursor + sizeof(int))
            {
                throw new InvalidDataException("Volcengine frame sequence is missing.");
            }

            sequence = BinaryPrimitives.ReadInt32BigEndian(
                encoded.Slice(cursor, sizeof(int)));
            cursor += sizeof(int);
        }

        if (encoded.Length < cursor + sizeof(uint))
        {
            throw new InvalidDataException("Volcengine frame payload length is missing.");
        }

        var payloadLength = BinaryPrimitives.ReadUInt32BigEndian(
            encoded.Slice(cursor, sizeof(uint)));
        cursor += sizeof(uint);
        if (payloadLength > int.MaxValue
            || encoded.Length != cursor + (int)payloadLength)
        {
            throw new InvalidDataException("Volcengine frame payload length is invalid.");
        }

        var encodedPayload = encoded.Slice(cursor, (int)payloadLength);
        var decodedPayload = compression == VolcengineCompression.Gzip
            ? Decompress(encodedPayload)
            : encodedPayload.ToArray();
        return new VolcengineProtocolFrame(
            messageType,
            flags,
            serialization,
            compression,
            sequence,
            decodedPayload);
    }

    private static byte[] Encode(
        VolcengineMessageType messageType,
        VolcengineMessageFlags flags,
        VolcengineSerialization serialization,
        VolcengineCompression compression,
        int? sequence,
        ReadOnlySpan<byte> payload)
    {
        if (flags is VolcengineMessageFlags.PositiveSequence
                or VolcengineMessageFlags.NegativeSequenceWithValue
            && sequence is null)
        {
            throw new ArgumentException("This frame flag requires a sequence number.");
        }

        var encodedPayload = compression == VolcengineCompression.Gzip
            ? Compress(payload)
            : payload.ToArray();
        var sequenceBytes = sequence is null ? 0 : sizeof(int);
        var result = new byte[4 + sequenceBytes + sizeof(uint) + encodedPayload.Length];
        result[0] = (byte)((ProtocolVersion << 4) | HeaderWords);
        result[1] = (byte)(((byte)messageType << 4) | (byte)flags);
        result[2] = (byte)(((byte)serialization << 4) | (byte)compression);
        result[3] = 0;
        var cursor = 4;
        if (sequence is not null)
        {
            BinaryPrimitives.WriteInt32BigEndian(
                result.AsSpan(cursor, sizeof(int)),
                sequence.Value);
            cursor += sizeof(int);
        }

        BinaryPrimitives.WriteUInt32BigEndian(
            result.AsSpan(cursor, sizeof(uint)),
            (uint)encodedPayload.Length);
        cursor += sizeof(uint);
        encodedPayload.CopyTo(result.AsSpan(cursor));
        return result;
    }

    private static byte[] Compress(ReadOnlySpan<byte> payload)
    {
        if (payload.IsEmpty)
        {
            return [];
        }

        using var output = new MemoryStream();
        using (var gzip = new GZipStream(
            output,
            CompressionLevel.SmallestSize,
            leaveOpen: true))
        {
            gzip.Write(payload);
        }

        return output.ToArray();
    }

    private static byte[] Decompress(ReadOnlySpan<byte> payload)
    {
        if (payload.IsEmpty)
        {
            return [];
        }

        using var input = new MemoryStream(payload.ToArray(), writable: false);
        using var gzip = new GZipStream(input, CompressionMode.Decompress);
        using var output = new MemoryStream();
        var buffer = new byte[16 * 1024];
        while (true)
        {
            var read = gzip.Read(buffer, 0, buffer.Length);
            if (read == 0)
            {
                break;
            }

            if (output.Length + read > MaxDecodedPayloadBytes)
            {
                throw new InvalidDataException("Volcengine frame payload is too large.");
            }

            output.Write(buffer, 0, read);
        }

        return output.ToArray();
    }
}
