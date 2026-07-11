using System.Collections.ObjectModel;
using System.Text;

namespace VoxFlow.Windows.Providers.Cloud.Common;

public sealed class CloudWebSocketConnectRequest
{
    private static readonly IReadOnlyDictionary<string, string> EmptyHeaders =
        new ReadOnlyDictionary<string, string>(new Dictionary<string, string>());

    public CloudWebSocketConnectRequest(
        Uri uri,
        IReadOnlyDictionary<string, string>? headers = null)
    {
        ArgumentNullException.ThrowIfNull(uri);
        if (!uri.IsAbsoluteUri
            || !string.Equals(uri.Scheme, Uri.UriSchemeWss, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException(
                "A secure WebSocket endpoint is required.",
                nameof(uri));
        }

        Uri = uri;
        Headers = headers is null
            ? EmptyHeaders
            : new ReadOnlyDictionary<string, string>(
                new Dictionary<string, string>(headers, StringComparer.OrdinalIgnoreCase));
        SafeDiagnostic = CreateSafeDiagnostic(uri);
    }

    public Uri Uri { get; }

    public IReadOnlyDictionary<string, string> Headers { get; }

    public string SafeDiagnostic { get; }

    public override string ToString() => SafeDiagnostic;

    private static string CreateSafeDiagnostic(Uri uri)
    {
        var port = uri.IsDefaultPort ? string.Empty : $":{uri.Port}";
        return $"wss://{uri.IdnHost}{port}/[redacted]";
    }
}

public enum CloudWebSocketMessageType
{
    Text,
    Binary,
    Close,
}

public sealed class CloudWebSocketReceiveMessage
{
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private readonly byte[] payload;

    private CloudWebSocketReceiveMessage(
        CloudWebSocketMessageType type,
        ReadOnlySpan<byte> payload)
    {
        Type = type;
        this.payload = payload.ToArray();
    }

    public CloudWebSocketMessageType Type { get; }

    public ReadOnlyMemory<byte> Payload => payload;

    public static CloudWebSocketReceiveMessage Text(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return new CloudWebSocketReceiveMessage(
            CloudWebSocketMessageType.Text,
            StrictUtf8.GetBytes(text));
    }

    public static CloudWebSocketReceiveMessage Binary(ReadOnlySpan<byte> payload) =>
        new(CloudWebSocketMessageType.Binary, payload);

    public static CloudWebSocketReceiveMessage Closed() =>
        new(CloudWebSocketMessageType.Close, ReadOnlySpan<byte>.Empty);

    public string GetText()
    {
        if (Type != CloudWebSocketMessageType.Text)
        {
            throw new InvalidOperationException("The WebSocket message is not text.");
        }

        return StrictUtf8.GetString(payload);
    }
}

public interface ICloudWebSocketFactory
{
    ICloudWebSocket Create();
}

public interface ICloudWebSocket : IAsyncDisposable
{
    ValueTask ConnectAsync(
        CloudWebSocketConnectRequest request,
        CancellationToken cancellationToken);

    ValueTask SendBinaryAsync(
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken);

    ValueTask SendTextAsync(
        string payload,
        CancellationToken cancellationToken);

    ValueTask<CloudWebSocketReceiveMessage> ReceiveAsync(
        CancellationToken cancellationToken);

    ValueTask CloseAsync(CancellationToken cancellationToken);
}
