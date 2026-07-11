using VoxFlow.Windows.Application.Credentials;

namespace VoxFlow.Windows.Providers.Cloud.Tencent;

public static class TencentAsrDefaults
{
    public const string EngineModelType = "16k_zh";
    public const int VoiceFormat = 1;
    public const bool NeedVad = true;
    public const int MaxSpeakTimeMilliseconds = 30_000;
    public static readonly Uri Endpoint = new("wss://asr.cloud.tencent.com/asr/v2/");
}

public sealed record TencentAsrCredentials
{
    public TencentAsrCredentials(string appId, string secretId, string secretKey)
    {
        AppId = Normalize(appId, nameof(appId));
        SecretId = Normalize(secretId, nameof(secretId));
        SecretKey = Normalize(secretKey, nameof(secretKey));
    }

    public string AppId { get; }

    public string SecretId { get; }

    public string SecretKey { get; }

    public override string ToString() =>
        "TencentAsrCredentials { AppId = [REDACTED], SecretId = [REDACTED], " +
        "SecretKey = [REDACTED] }";

    private static string Normalize(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        return value.Trim();
    }
}

public sealed record TencentAsrOptions
{
    public static TencentAsrOptions Default { get; } = new();

    public string EngineModelType { get; init; } = TencentAsrDefaults.EngineModelType;

    public int VoiceFormat { get; init; } = TencentAsrDefaults.VoiceFormat;

    public bool NeedVad { get; init; } = TencentAsrDefaults.NeedVad;

    public int MaxSpeakTimeMilliseconds { get; init; } =
        TencentAsrDefaults.MaxSpeakTimeMilliseconds;

    public string? HotwordList { get; init; }
}

public static class TencentCredentialKeys
{
    private const string OwnerKind = "asr";
    private const string OwnerId = "tencent_cloud_asr";

    public static readonly CredentialKey AppId = new(OwnerKind, OwnerId, "app_id");
    public static readonly CredentialKey SecretId = new(OwnerKind, OwnerId, "secret_id");
    public static readonly CredentialKey SecretKey = new(OwnerKind, OwnerId, "secret_key");

    public static string ProviderOwnerKind => OwnerKind;

    public static string ProviderOwnerId => OwnerId;
}

public sealed record TencentAsrSettingsStatus(
    CredentialPresentation AppId,
    CredentialPresentation SecretId,
    CredentialPresentation SecretKey,
    TencentAsrOptions Options)
{
    public bool IsComplete =>
        AppId.Availability == CredentialAvailability.Available
        && SecretId.Availability == CredentialAvailability.Available
        && SecretKey.Availability == CredentialAvailability.Available;

    public bool CanTestConnection => IsComplete;
}

public enum TencentConnectionTestError
{
    None,
    IncompleteCredentials,
    CredentialsUnavailable,
    ConnectionFailed,
}

public sealed record TencentConnectionTestResult(
    bool Succeeded,
    TencentConnectionTestError Error)
{
    public static TencentConnectionTestResult Success { get; } =
        new(true, TencentConnectionTestError.None);

    public override string ToString() =>
        $"TencentConnectionTestResult {{ Succeeded = {Succeeded}, Error = {Error} }}";
}

public interface ITencentConnectionTester
{
    ValueTask<TencentConnectionTestResult> TestAsync(
        TencentAsrCredentials credentials,
        CancellationToken cancellationToken);
}

public sealed class TencentAsrSettingsService
{
    private readonly ICredentialVault credentialVault;
    private readonly ITencentConnectionTester connectionTester;

    public TencentAsrSettingsService(
        ICredentialVault credentialVault,
        ITencentConnectionTester connectionTester)
    {
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.connectionTester = connectionTester
            ?? throw new ArgumentNullException(nameof(connectionTester));
    }

    public async Task SaveAsync(
        TencentAsrCredentials credentials,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(credentials);
        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            await credentialVault.SaveAsync(
                TencentCredentialKeys.AppId,
                credentials.AppId,
                cancellationToken).ConfigureAwait(false);
            await credentialVault.SaveAsync(
                TencentCredentialKeys.SecretId,
                credentials.SecretId,
                cancellationToken).ConfigureAwait(false);
            await credentialVault.SaveAsync(
                TencentCredentialKeys.SecretKey,
                credentials.SecretKey,
                cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            await RemovePartialSaveAsync().ConfigureAwait(false);
            throw;
        }
    }

    public async Task<TencentAsrSettingsStatus> GetStatusAsync(
        CancellationToken cancellationToken = default)
    {
        var appId = await credentialVault.GetPresentationAsync(
            TencentCredentialKeys.AppId,
            cancellationToken).ConfigureAwait(false);
        var secretId = await credentialVault.GetPresentationAsync(
            TencentCredentialKeys.SecretId,
            cancellationToken).ConfigureAwait(false);
        var secretKey = await credentialVault.GetPresentationAsync(
            TencentCredentialKeys.SecretKey,
            cancellationToken).ConfigureAwait(false);

        return new TencentAsrSettingsStatus(
            appId,
            secretId,
            secretKey,
            TencentAsrOptions.Default);
    }

    public async Task<TencentAsrCredentials?> RevealAsync(
        CancellationToken cancellationToken = default)
    {
        var appId = await credentialVault.ReadSecretAsync(
            TencentCredentialKeys.AppId,
            cancellationToken).ConfigureAwait(false);
        var secretId = await credentialVault.ReadSecretAsync(
            TencentCredentialKeys.SecretId,
            cancellationToken).ConfigureAwait(false);
        var secretKey = await credentialVault.ReadSecretAsync(
            TencentCredentialKeys.SecretKey,
            cancellationToken).ConfigureAwait(false);

        if (string.IsNullOrWhiteSpace(appId)
            || string.IsNullOrWhiteSpace(secretId)
            || string.IsNullOrWhiteSpace(secretKey))
        {
            return null;
        }

        return new TencentAsrCredentials(appId, secretId, secretKey);
    }

    public async Task<TencentConnectionTestResult> TestConnectionAsync(
        CancellationToken cancellationToken = default)
    {
        TencentAsrCredentials? credentials;
        try
        {
            credentials = await RevealAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (CredentialUnavailableException)
        {
            return new TencentConnectionTestResult(
                false,
                TencentConnectionTestError.CredentialsUnavailable);
        }

        if (credentials is null)
        {
            return new TencentConnectionTestResult(
                false,
                TencentConnectionTestError.IncompleteCredentials);
        }

        return await connectionTester.TestAsync(credentials, cancellationToken)
            .ConfigureAwait(false);
    }

    public Task DeleteAsync(CancellationToken cancellationToken = default) =>
        credentialVault.DeleteOwnerAsync(
            TencentCredentialKeys.ProviderOwnerKind,
            TencentCredentialKeys.ProviderOwnerId,
            cancellationToken);

    private async Task RemovePartialSaveAsync()
    {
        try
        {
            await credentialVault.DeleteOwnerAsync(
                TencentCredentialKeys.ProviderOwnerKind,
                TencentCredentialKeys.ProviderOwnerId,
                CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // Preserve the original safe vault exception. Status remains incomplete
            // even if a best-effort cleanup cannot run.
        }
    }
}
