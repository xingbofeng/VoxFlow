using System.Runtime.InteropServices;
using System.Text;

namespace VoxFlow.Windows.Providers.Qwen.Native;

internal enum QwenNativeEventKind
{
    Ready = 1,
    SpeechStarted = 2,
    Partial = 3,
    Final = 4,
    Progress = 5,
    Metrics = 6,
    Error = 7,
}

internal enum QwenNativePollResult
{
    Error = -1,
    Empty = 0,
    Event = 1,
    Completed = 2,
}

[StructLayout(LayoutKind.Sequential)]
internal readonly struct QwenNativeEventRaw
{
    internal QwenNativeEventRaw(
        QwenNativeEventKind kind,
        long revision,
        nint text,
        nuint textLength,
        double value)
    {
        Kind = kind;
        Revision = revision;
        Text = text;
        TextLength = textLength;
        Value = value;
    }

    internal QwenNativeEventKind Kind { get; }

    internal long Revision { get; }

    internal nint Text { get; }

    internal nuint TextLength { get; }

    internal double Value { get; }
}

internal sealed record QwenNativeEventData(
    QwenNativeEventKind Kind,
    long Revision,
    string Text,
    double Value);

internal static class QwenNativeEventMarshaller
{
    internal const int MaximumTextBytes = 1024 * 1024;
    private static readonly UTF8Encoding StrictUtf8 = new(
        encoderShouldEmitUTF8Identifier: false,
        throwOnInvalidBytes: true);

    internal static QwenNativeEventData Copy(QwenNativeEventRaw raw)
    {
        if (raw.TextLength > (nuint)MaximumTextBytes)
        {
            throw new InvalidDataException("The native Qwen event text exceeded the bounded ABI payload.");
        }

        string text = string.Empty;
        if (raw.TextLength > 0)
        {
            if (raw.Text == 0)
            {
                throw new InvalidDataException("The native Qwen event exposed an invalid UTF-8 pointer.");
            }

            int length = checked((int)raw.TextLength);
            byte[] bytes = new byte[length];
            Marshal.Copy(raw.Text, bytes, 0, length);
            text = StrictUtf8.GetString(bytes);
        }

        return new QwenNativeEventData(
            raw.Kind,
            raw.Revision,
            text,
            raw.Value);
    }
}
