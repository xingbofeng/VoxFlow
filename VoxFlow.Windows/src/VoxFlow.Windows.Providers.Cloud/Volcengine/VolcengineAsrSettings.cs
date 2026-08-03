using System.Collections.ObjectModel;
using VoxFlow.Windows.Application.Credentials;

namespace VoxFlow.Windows.Providers.Cloud.Volcengine;

public static class VolcengineAsrDefaults
{
    public const string ResourceId = "volc.bigasr.sauc.duration";
    public const string Model = "bigmodel";

    public static Uri Endpoint { get; } = new(
        "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel");
}

public sealed record VolcengineAsrCredentials(
    string AppId,
    string AccessToken,
    string SecretKey)
{
    public bool IsComplete =>
        !string.IsNullOrWhiteSpace(AppId)
        && !string.IsNullOrWhiteSpace(AccessToken)
        && !string.IsNullOrWhiteSpace(SecretKey);

    public VolcengineAsrCredentials Normalized() => new(
        AppId.Trim(),
        AccessToken.Trim(),
        SecretKey.Trim());

    public override string ToString() =>
        $"VolcengineAsrCredentials {{ IsComplete = {IsComplete} }}";
}

public static class VolcengineCredentialKeys
{
    public const string OwnerKind = "asr";
    public const string OwnerId = "volcengine_asr";

    public static CredentialKey AppId { get; } = new(
        OwnerKind,
        OwnerId,
        "app_id");

    public static CredentialKey AccessToken { get; } = new(
        OwnerKind,
        OwnerId,
        "access_token");

    public static CredentialKey SecretKey { get; } = new(
        OwnerKind,
        OwnerId,
        "secret_key");
}

public sealed record VolcengineAsrStatus(
    Uri Endpoint,
    string ResourceId,
    string Model,
    CredentialPresentation AppId,
    CredentialPresentation AccessToken,
    CredentialPresentation SecretKey)
{
    public bool IsComplete =>
        AppId.Availability == CredentialAvailability.Available
        && AccessToken.Availability == CredentialAvailability.Available
        && SecretKey.Availability == CredentialAvailability.Available;
}

public sealed class VolcengineAsrSettingsService(
    ICredentialVault credentialVault)
{
    public async Task SaveAsync(
        VolcengineAsrCredentials credentials,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(credentials);
        if (!credentials.IsComplete)
        {
            throw new ArgumentException(
                "App ID, access token, and secret key are all required.",
                nameof(credentials));
        }

        var normalized = credentials.Normalized();
        await credentialVault.SaveAsync(
                VolcengineCredentialKeys.AppId,
                normalized.AppId,
                cancellationToken)
            .ConfigureAwait(false);
        await credentialVault.SaveAsync(
                VolcengineCredentialKeys.AccessToken,
                normalized.AccessToken,
                cancellationToken)
            .ConfigureAwait(false);
        await credentialVault.SaveAsync(
                VolcengineCredentialKeys.SecretKey,
                normalized.SecretKey,
                cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<VolcengineAsrStatus> GetStatusAsync(
        CancellationToken cancellationToken)
    {
        var appId = await credentialVault.GetPresentationAsync(
                VolcengineCredentialKeys.AppId,
                cancellationToken)
            .ConfigureAwait(false);
        var accessToken = await credentialVault.GetPresentationAsync(
                VolcengineCredentialKeys.AccessToken,
                cancellationToken)
            .ConfigureAwait(false);
        var secretKey = await credentialVault.GetPresentationAsync(
                VolcengineCredentialKeys.SecretKey,
                cancellationToken)
            .ConfigureAwait(false);
        return new VolcengineAsrStatus(
            VolcengineAsrDefaults.Endpoint,
            VolcengineAsrDefaults.ResourceId,
            VolcengineAsrDefaults.Model,
            appId,
            accessToken,
            secretKey);
    }

    public async Task<VolcengineAsrCredentials?> RevealAsync(
        CancellationToken cancellationToken)
    {
        var appId = await credentialVault.ReadSecretAsync(
                VolcengineCredentialKeys.AppId,
                cancellationToken)
            .ConfigureAwait(false);
        var accessToken = await credentialVault.ReadSecretAsync(
                VolcengineCredentialKeys.AccessToken,
                cancellationToken)
            .ConfigureAwait(false);
        var secretKey = await credentialVault.ReadSecretAsync(
                VolcengineCredentialKeys.SecretKey,
                cancellationToken)
            .ConfigureAwait(false);
        return string.IsNullOrWhiteSpace(appId)
            || string.IsNullOrWhiteSpace(accessToken)
            || string.IsNullOrWhiteSpace(secretKey)
            ? null
            : new VolcengineAsrCredentials(appId, accessToken, secretKey);
    }

    public async Task DeleteAsync(CancellationToken cancellationToken)
    {
        _ = await credentialVault.DeleteOwnerAsync(
                VolcengineCredentialKeys.OwnerKind,
                VolcengineCredentialKeys.OwnerId,
                cancellationToken)
            .ConfigureAwait(false);
    }
}

public sealed class VolcengineHandshakeDescriptor
{
    private VolcengineHandshakeDescriptor(
        IReadOnlyDictionary<string, string> headers)
    {
        Headers = headers;
    }

    public Uri Endpoint => VolcengineAsrDefaults.Endpoint;

    public IReadOnlyDictionary<string, string> Headers { get; }

    public string SafeDiagnostic =>
        $"provider=volcengine; endpoint={Endpoint.Host}; resource={VolcengineAsrDefaults.ResourceId}; model={VolcengineAsrDefaults.Model}";

    public static VolcengineHandshakeDescriptor Create(
        VolcengineAsrCredentials credentials,
        string connectId)
    {
        ArgumentNullException.ThrowIfNull(credentials);
        if (!credentials.IsComplete)
        {
            throw new ArgumentException(
                "Complete Volcengine credentials are required.",
                nameof(credentials));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(connectId);
        var normalized = credentials.Normalized();
        var headers = new ReadOnlyDictionary<string, string>(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["X-Api-App-Key"] = normalized.AppId,
                ["X-Api-Access-Key"] = normalized.AccessToken,
                ["X-Api-Resource-Id"] = VolcengineAsrDefaults.ResourceId,
                ["X-Api-Connect-Id"] = connectId.Trim(),
            });
        return new VolcengineHandshakeDescriptor(headers);
    }

    public override string ToString() => SafeDiagnostic;
}
