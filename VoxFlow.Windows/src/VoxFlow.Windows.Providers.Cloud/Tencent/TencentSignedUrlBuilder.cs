using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace VoxFlow.Windows.Providers.Cloud.Tencent;

public interface ITencentNonceSource
{
    int NextNonce();
}

public sealed class RandomTencentNonceSource : ITencentNonceSource
{
    public int NextNonce() => RandomNumberGenerator.GetInt32(1, int.MaxValue);
}

public sealed class TencentSignedWebSocketRequest
{
    internal TencentSignedWebSocketRequest(Uri connectUri, string engineModelType)
    {
        ConnectUri = connectUri;
        SafeDiagnostic =
            $"wss://asr.cloud.tencent.com/asr/v2/[redacted]?engine_model_type={engineModelType}";
    }

    public Uri ConnectUri { get; }

    public string SafeDiagnostic { get; }

    public override string ToString() => SafeDiagnostic;
}

/// <summary>
/// Builds the signed Tencent real-time ASR WebSocket URL exactly as documented at
/// https://cloud.tencent.com/document/product/1093/48982.
/// </summary>
public sealed class TencentSignedUrlBuilder
{
    private static readonly UTF8Encoding Utf8 = new(false);
    private static readonly TimeSpan SignatureLifetime = TimeSpan.FromHours(24);
    private readonly TimeProvider timeProvider;
    private readonly ITencentNonceSource nonceSource;

    public TencentSignedUrlBuilder(
        TimeProvider? timeProvider = null,
        ITencentNonceSource? nonceSource = null)
    {
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.nonceSource = nonceSource ?? new RandomTencentNonceSource();
    }

    public TencentSignedWebSocketRequest Build(
        TencentAsrCredentials credentials,
        TencentAsrOptions options,
        string voiceId)
    {
        ArgumentNullException.ThrowIfNull(credentials);
        ArgumentNullException.ThrowIfNull(options);
        ArgumentException.ThrowIfNullOrWhiteSpace(voiceId);
        if (voiceId.Length > 128)
        {
            throw new ArgumentOutOfRangeException(nameof(voiceId));
        }

        ValidateOptions(options);
        var nonce = nonceSource.NextNonce();
        if (nonce <= 0 || nonce.ToString(CultureInfo.InvariantCulture).Length > 10)
        {
            throw new InvalidOperationException("The Tencent nonce source returned an invalid value.");
        }

        var timestamp = timeProvider.GetUtcNow().ToUnixTimeSeconds();
        var expired = checked(timestamp + (long)SignatureLifetime.TotalSeconds);
        var parameters = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["engine_model_type"] = options.EngineModelType,
            ["expired"] = expired.ToString(CultureInfo.InvariantCulture),
            ["max_speak_time"] = options.MaxSpeakTimeMilliseconds.ToString(
                CultureInfo.InvariantCulture),
            ["needvad"] = options.NeedVad ? "1" : "0",
            ["nonce"] = nonce.ToString(CultureInfo.InvariantCulture),
            ["secretid"] = credentials.SecretId,
            ["timestamp"] = timestamp.ToString(CultureInfo.InvariantCulture),
            ["voice_format"] = options.VoiceFormat.ToString(CultureInfo.InvariantCulture),
            ["voice_id"] = voiceId,
        };

        if (!string.IsNullOrWhiteSpace(options.HotwordList))
        {
            parameters["hotword_list"] = options.HotwordList.Trim();
        }

        var rawQuery = JoinParameters(parameters, encodeValues: false);
        var signingText = $"asr.cloud.tencent.com/asr/v2/{credentials.AppId}?{rawQuery}";
        var signature = Sign(signingText, credentials.SecretKey);
        var encodedQuery = JoinParameters(parameters, encodeValues: true);
        var uri = new Uri(
            $"wss://asr.cloud.tencent.com/asr/v2/{Uri.EscapeDataString(credentials.AppId)}?" +
            $"{encodedQuery}&signature={Uri.EscapeDataString(signature)}");
        return new TencentSignedWebSocketRequest(uri, options.EngineModelType);
    }

    private static void ValidateOptions(TencentAsrOptions options)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(options.EngineModelType);
        if (options.VoiceFormat != 1)
        {
            throw new ArgumentOutOfRangeException(
                nameof(options),
                "Tencent live PCM requires voice_format=1.");
        }

        if (options.MaxSpeakTimeMilliseconds is < 5_000 or > 30_000)
        {
            throw new ArgumentOutOfRangeException(
                nameof(options),
                "VoxFlow limits a Tencent utterance to 30 seconds.");
        }
    }

    private static string JoinParameters(
        IEnumerable<KeyValuePair<string, string>> parameters,
        bool encodeValues) => string.Join(
            "&",
            parameters.Select(parameter => string.Concat(
                parameter.Key,
                "=",
                encodeValues ? Uri.EscapeDataString(parameter.Value) : parameter.Value)));

    private static string Sign(string signingText, string secretKey)
    {
        var keyBytes = Utf8.GetBytes(secretKey);
        var textBytes = Utf8.GetBytes(signingText);
        try
        {
#pragma warning disable CA5350 // Tencent's documented protocol mandates HMAC-SHA1.
            using var hmac = new HMACSHA1(keyBytes);
#pragma warning restore CA5350
            return Convert.ToBase64String(hmac.ComputeHash(textBytes));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(keyBytes);
            CryptographicOperations.ZeroMemory(textBytes);
        }
    }
}
