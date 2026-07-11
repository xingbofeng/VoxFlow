using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;

namespace VoxFlow.Windows.App.Composition;

public sealed record CloudAsrConfigurationSnapshot(
    bool TencentConfigured,
    bool AliyunConfigured,
    bool VolcengineConfigured);

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
        state.RecordCloudProvider(
            AsrProviderId.TencentCloud,
            tencentStatus.IsComplete,
            ready: false);
        state.RecordCloudProvider(
            AsrProviderId.AliyunDashScope,
            aliyunStatus.CanTestConnection,
            ready: false);
        state.RecordCloudProvider(
            AsrProviderId.Volcengine,
            volcengineStatus.IsComplete,
            ready: false);
        return new CloudAsrConfigurationSnapshot(
            tencentStatus.IsComplete,
            aliyunStatus.CanTestConnection,
            volcengineStatus.IsComplete);
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
            ready: false);
    }

    public async Task SaveAliyunAsync(
        string apiKey,
        CancellationToken cancellationToken)
    {
        await aliyun.SaveAsync(apiKey, cancellationToken).ConfigureAwait(false);
        state.RecordCloudProvider(
            AsrProviderId.AliyunDashScope,
            configured: true,
            ready: false);
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
            ready: false);
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
        state.RecordCloudProvider(provider, configured: true, ready: succeeded);
        return succeeded;
    }

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
