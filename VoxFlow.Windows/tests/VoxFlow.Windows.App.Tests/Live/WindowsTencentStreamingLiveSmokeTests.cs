using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Media;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Security;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;

namespace VoxFlow.Windows.App.Tests.Live;

public sealed class WindowsTencentStreamingLiveSmokeTests
{
    [WindowsSavedCredentialsLiveFact]
    [Trait("Category", "Live")]
    public async Task Saved_tencent_credentials_stream_the_bundled_pcm_fixture()
    {
        var databasePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow",
            "voxflow.db");
        var connectionFactory = new SqliteConnectionFactory(databasePath, pooling: false);
        using var vault = new SqliteCredentialVault(
            connectionFactory,
            new DpapiCurrentUserDataProtector());
        var settings = new TencentAsrSettingsService(
            vault,
            new TencentSettingsConnectionTester());
        var credentials = await settings.RevealAsync(CancellationToken.None);
        Assert.NotNull(credentials);

        await using var session = new TencentAsrSession(
            credentials,
            TencentAsrOptions.Default,
            Guid.NewGuid().ToString("N"),
            new TencentSignedUrlBuilder(),
            new ClientWebSocketAdapter(),
            finalTimeout: TimeSpan.FromSeconds(30));
        var final = new TaskCompletionSource<AsrFinalResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var failure = new TaskCompletionSource<VoxFlowError>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, value) => final.TrySetResult(value);
        session.Failed += (_, value) => failure.TrySetResult(value);

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(50));
        await session.StartAsync(timeout.Token);
        var fixture = Path.Combine(AppContext.BaseDirectory, "Qwen", "readiness-canary.wav");
        var frames = new PcmWaveFrameSource(frameSizeBytes: 3_200);
        await foreach (var frame in frames.ReadFramesAsync(fixture, timeout.Token))
        {
            if (final.Task.IsCompleted || failure.Task.IsCompleted)
            {
                break;
            }

            await session.PushAudioAsync(frame, timeout.Token);
            await Task.Delay(TimeSpan.FromMilliseconds(100), timeout.Token);
        }

        if (!final.Task.IsCompleted && !failure.Task.IsCompleted)
        {
            await session.FinishAsync(timeout.Token);
        }

        var completed = await Task.WhenAny(
            final.Task,
            failure.Task,
            Task.Delay(TimeSpan.FromSeconds(35), timeout.Token));
        if (completed == failure.Task)
        {
            var error = await failure.Task;
            Assert.Fail($"provider=tencent-cloud; success=false; error={error.Code}");
        }

        Assert.Same(final.Task, completed);
        Assert.False(string.IsNullOrWhiteSpace((await final.Task).Text));
    }
}
