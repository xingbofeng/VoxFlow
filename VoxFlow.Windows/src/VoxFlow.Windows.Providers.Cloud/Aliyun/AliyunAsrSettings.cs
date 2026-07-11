using System.Collections.ObjectModel;
using VoxFlow.Windows.Application.Credentials;

namespace VoxFlow.Windows.Providers.Cloud.Aliyun;

public static class AliyunAsrDefaults
{
    public const string Model = "fun-asr-realtime";

    public static Uri Endpoint { get; } = new(
        "wss://dashscope.aliyuncs.com/api-ws/v1/inference");
}

public static class AliyunCredentialKeys
{
    public const string OwnerKind = "asr";
    public const string OwnerId = "aliyun_dashscope_asr";

    public static CredentialKey ApiKey { get; } = new(
        OwnerKind,
        OwnerId,
        "api_key");
}

public sealed record AliyunAsrStatus(
    Uri Endpoint,
    string Model,
    CredentialPresentation ApiKey,
    bool CanTestConnection);

public sealed record AliyunConnectionTestResult(
    bool Succeeded,
    string? ErrorCode)
{
    public override string ToString() =>
        $"AliyunConnectionTestResult {{ Succeeded = {Succeeded}, ErrorCode = {ErrorCode ?? "none"} }}";
}

public interface IAliyunConnectionTester
{
    ValueTask<AliyunConnectionTestResult> TestAsync(
        string apiKey,
        CancellationToken cancellationToken);
}

public sealed class AliyunAsrSettingsService
{
    private readonly ICredentialVault credentialVault;
    private readonly IAliyunConnectionTester connectionTester;

    public AliyunAsrSettingsService(
        ICredentialVault credentialVault,
        IAliyunConnectionTester connectionTester)
    {
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.connectionTester = connectionTester
            ?? throw new ArgumentNullException(nameof(connectionTester));
    }

    public async Task SaveAsync(
        string apiKey,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        await credentialVault.SaveAsync(
                AliyunCredentialKeys.ApiKey,
                apiKey.Trim(),
                cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<AliyunAsrStatus> GetStatusAsync(
        CancellationToken cancellationToken)
    {
        var presentation = await credentialVault.GetPresentationAsync(
                AliyunCredentialKeys.ApiKey,
                cancellationToken)
            .ConfigureAwait(false);
        return new AliyunAsrStatus(
            AliyunAsrDefaults.Endpoint,
            AliyunAsrDefaults.Model,
            presentation,
            CanTestConnection: presentation.Availability == CredentialAvailability.Available);
    }

    public Task<string?> RevealApiKeyAsync(CancellationToken cancellationToken) =>
        credentialVault.ReadSecretAsync(
            AliyunCredentialKeys.ApiKey,
            cancellationToken);

    public async ValueTask<AliyunConnectionTestResult> TestConnectionAsync(
        CancellationToken cancellationToken)
    {
        string? apiKey;
        try
        {
            apiKey = await credentialVault.ReadSecretAsync(
                    AliyunCredentialKeys.ApiKey,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (CredentialUnavailableException)
        {
            return new AliyunConnectionTestResult(
                Succeeded: false,
                ErrorCode: "credentialUnavailable");
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return new AliyunConnectionTestResult(
                Succeeded: false,
                ErrorCode: "notConfigured");
        }

        return await connectionTester.TestAsync(apiKey, cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task DeleteAsync(CancellationToken cancellationToken)
    {
        _ = await credentialVault.DeleteOwnerAsync(
                AliyunCredentialKeys.OwnerKind,
                AliyunCredentialKeys.OwnerId,
                cancellationToken)
            .ConfigureAwait(false);
    }
}

public sealed class AliyunHandshakeDescriptor
{
    private AliyunHandshakeDescriptor(
        Uri endpoint,
        IReadOnlyDictionary<string, string> headers)
    {
        Endpoint = endpoint;
        Headers = headers;
    }

    public Uri Endpoint { get; }

    public IReadOnlyDictionary<string, string> Headers { get; }

    public string SafeDiagnostic =>
        $"provider=aliyun; endpoint={Endpoint.Host}; model={AliyunAsrDefaults.Model}";

    public static AliyunHandshakeDescriptor Create(string apiKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        var headers = new ReadOnlyDictionary<string, string>(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["Authorization"] = $"Bearer {apiKey.Trim()}",
                ["User-Agent"] = "VoxFlow-Windows/1",
            });
        return new AliyunHandshakeDescriptor(AliyunAsrDefaults.Endpoint, headers);
    }

    public override string ToString() => SafeDiagnostic;
}
