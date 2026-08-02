using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;

namespace VoxFlow.Windows.App.Composition;

public sealed record CloudAsrConfigurationSnapshot(
    TencentAsrSettingsStatus Tencent,
    AliyunAsrStatus Aliyun,
    VolcengineAsrStatus Volcengine)
{
    public bool TencentConfigured => Tencent.IsComplete;

    public bool AliyunConfigured => Aliyun.CanTestConnection;

    public bool VolcengineConfigured => Volcengine.IsComplete;
}

public sealed class CloudAsrSettingsCoordinator
{
    private readonly TencentAsrSettingsService tencent;
    private readonly AliyunAsrSettingsService aliyun;
    private readonly VolcengineAsrSettingsService volcengine;
    private readonly SettingsStateCoordinator state;

    public CloudAsrSettingsCoordinator(
        TencentAsrSettingsService tencent,
        AliyunAsrSettingsService aliyun,
        VolcengineAsrSettingsService volcengine,
        SettingsStateCoordinator state)
    {
        this.tencent = tencent ?? throw new ArgumentNullException(nameof(tencent));
        this.aliyun = aliyun ?? throw new ArgumentNullException(nameof(aliyun));
        this.volcengine = volcengine ?? throw new ArgumentNullException(nameof(volcengine));
        this.state = state ?? throw new ArgumentNullException(nameof(state));
    }

    public async Task<CloudAsrConfigurationSnapshot> LoadAsync(
        CancellationToken cancellationToken)
    {
        var tencentStatus = await tencent.GetStatusAsync(cancellationToken)
            .ConfigureAwait(false);
        var aliyunStatus = await aliyun.GetStatusAsync(cancellationToken)
            .ConfigureAwait(false);
        var volcengineStatus = await volcengine.GetStatusAsync(cancellationToken)
            .ConfigureAwait(false);
        // Cloud providers with complete credentials are selectable immediately.
        // Connection testing remains an explicit health check, not a selection gate.
        state.RecordCloudProvider(
            AsrProviderId.TencentCloud,
            tencentStatus.IsComplete,
            ready: tencentStatus.IsComplete);
        state.RecordCloudProvider(
            AsrProviderId.AliyunDashScope,
            aliyunStatus.CanTestConnection,
            ready: aliyunStatus.CanTestConnection);
        state.RecordCloudProvider(
            AsrProviderId.Volcengine,
            volcengineStatus.IsComplete,
            ready: volcengineStatus.IsComplete);
        return new CloudAsrConfigurationSnapshot(
            tencentStatus,
            aliyunStatus,
            volcengineStatus);
    }

    public async Task SaveTencentAsync(
        string appId,
        string secretId,
        string secretKey,
        CancellationToken cancellationToken)
    {
        await tencent.SaveAsync(
                new TencentAsrCredentials(appId, secretId, secretKey),
                cancellationToken)
            .ConfigureAwait(false);
        state.RecordCloudProvider(
            AsrProviderId.TencentCloud,
            configured: true,
            ready: true);
        SelectProvider(AsrProviderId.TencentCloud);
    }

    public async Task SaveAliyunAsync(
        string apiKey,
        CancellationToken cancellationToken)
    {
        await aliyun.SaveAsync(apiKey, cancellationToken).ConfigureAwait(false);
        state.RecordCloudProvider(
            AsrProviderId.AliyunDashScope,
            configured: true,
            ready: true);
        SelectProvider(AsrProviderId.AliyunDashScope);
    }

    public async Task SaveVolcengineAsync(
        string appId,
        string accessToken,
        string secretKey,
        CancellationToken cancellationToken)
    {
        await volcengine.SaveAsync(
                new VolcengineAsrCredentials(appId, accessToken, secretKey),
                cancellationToken)
            .ConfigureAwait(false);
        state.RecordCloudProvider(
            AsrProviderId.Volcengine,
            configured: true,
            ready: true);
        SelectProvider(AsrProviderId.Volcengine);
    }

    public async Task<bool> TestAsync(
        AsrProviderId provider,
        CancellationToken cancellationToken)
    {
        var succeeded = provider switch
        {
            AsrProviderId.TencentCloud =>
                (await tencent.TestConnectionAsync(cancellationToken)
                    .ConfigureAwait(false)).Succeeded,
            AsrProviderId.AliyunDashScope =>
                (await aliyun.TestConnectionAsync(cancellationToken)
                    .ConfigureAwait(false)).Succeeded,
            AsrProviderId.Volcengine => await TestVolcengineAsync(cancellationToken)
                .ConfigureAwait(false),
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };
        var configured = await IsConfiguredAsync(provider, cancellationToken)
            .ConfigureAwait(false);
        // Keep the provider selectable after a failed test when credentials remain
        // complete; only the feedback message reports the connection result.
        state.RecordCloudProvider(provider, configured, ready: configured);
        if (succeeded)
        {
            SelectProvider(provider);
        }

        return succeeded;
    }

    public void SelectProvider(AsrProviderId provider)
    {
        if (provider is AsrProviderId.Qwen)
        {
            throw new ArgumentException("Use the Qwen model selection path.", nameof(provider));
        }

        state.SelectAsr(provider, null);
    }

    public Task<TencentAsrCredentials?> RevealTencentAsync(
        CancellationToken cancellationToken) =>
        tencent.RevealAsync(cancellationToken);

    public Task<string?> RevealAliyunApiKeyAsync(
        CancellationToken cancellationToken) =>
        aliyun.RevealApiKeyAsync(cancellationToken);

    public Task<VolcengineAsrCredentials?> RevealVolcengineAsync(
        CancellationToken cancellationToken) =>
        volcengine.RevealAsync(cancellationToken);

    public async Task DeleteAsync(
        AsrProviderId provider,
        CancellationToken cancellationToken)
    {
        switch (provider)
        {
            case AsrProviderId.TencentCloud:
                await tencent.DeleteAsync(cancellationToken).ConfigureAwait(false);
                break;
            case AsrProviderId.AliyunDashScope:
                await aliyun.DeleteAsync(cancellationToken).ConfigureAwait(false);
                break;
            case AsrProviderId.Volcengine:
                await volcengine.DeleteAsync(cancellationToken).ConfigureAwait(false);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(provider));
        }

        state.RecordCloudProvider(provider, configured: false, ready: false);
    }

    private async Task<bool> TestVolcengineAsync(CancellationToken cancellationToken)
    {
        var credentials = await volcengine.RevealAsync(cancellationToken)
            .ConfigureAwait(false);
        if (credentials is null)
        {
            return false;
        }

        await using var session = new VolcengineRealtimeAsrSession(
            credentials,
            new ClientWebSocketFactory(),
            finalTimeout: TimeSpan.FromSeconds(15));
        try
        {
            await session.StartAsync(cancellationToken).ConfigureAwait(false);
            await session.CancelAsync(CancellationToken.None).ConfigureAwait(false);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return false;
        }
    }

    private async Task<bool> IsConfiguredAsync(
        AsrProviderId provider,
        CancellationToken cancellationToken) => provider switch
        {
            AsrProviderId.TencentCloud =>
                (await tencent.GetStatusAsync(cancellationToken)
                    .ConfigureAwait(false)).IsComplete,
            AsrProviderId.AliyunDashScope =>
                (await aliyun.GetStatusAsync(cancellationToken)
                    .ConfigureAwait(false)).CanTestConnection,
            AsrProviderId.Volcengine =>
                (await volcengine.GetStatusAsync(cancellationToken)
                    .ConfigureAwait(false)).IsComplete,
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };
}

internal sealed class TencentSettingsConnectionTester : ITencentConnectionTester
{
    public async ValueTask<TencentConnectionTestResult> TestAsync(
        TencentAsrCredentials credentials,
        CancellationToken cancellationToken)
    {
        await using var session = new TencentAsrSession(
            credentials,
            TencentAsrOptions.Default,
            Guid.NewGuid().ToString("N"),
            new TencentSignedUrlBuilder(),
            new ClientWebSocketAdapter(),
            handshakeTimeout: TimeSpan.FromSeconds(10));
        try
        {
            await session.StartAsync(cancellationToken).ConfigureAwait(false);
            await session.CancelAsync(CancellationToken.None).ConfigureAwait(false);
            return TencentConnectionTestResult.Success;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new TencentConnectionTestResult(
                false,
                TencentConnectionTestError.ConnectionFailed);
        }
    }
}

internal sealed class AliyunSettingsConnectionTester : IAliyunConnectionTester
{
    public async ValueTask<AliyunConnectionTestResult> TestAsync(
        string apiKey,
        CancellationToken cancellationToken)
    {
        await using var session = new AliyunRealtimeAsrSession(
            apiKey,
            new ClientWebSocketFactory(),
            connectionTimeout: TimeSpan.FromSeconds(15));
        try
        {
            await session.StartAsync(cancellationToken).ConfigureAwait(false);
            await session.CancelAsync(CancellationToken.None).ConfigureAwait(false);
            return new AliyunConnectionTestResult(true, null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new AliyunConnectionTestResult(false, "connectionFailed");
        }
    }
}
