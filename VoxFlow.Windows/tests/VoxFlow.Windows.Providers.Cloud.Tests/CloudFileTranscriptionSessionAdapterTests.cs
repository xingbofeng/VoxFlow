using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;

namespace VoxFlow.Windows.Providers.Cloud.Tests;

public sealed class CloudFileTranscriptionSessionAdapterTests
{
    [Fact]
    public async Task Tencent_adapter_creates_the_existing_realtime_session()
    {
        var adapter = new TencentFileTranscriptionSessionAdapter(
            _ => Task.FromResult<TencentAsrCredentials?>(new(
                "app-id", "secret-id", "secret-key")),
            new FakeSocketFactory());

        await using var session = await adapter.CreateSessionAsync(
            RecognitionLanguage.ChineseMandarin,
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Equal(AsrProviderId.TencentCloud, adapter.Provider);
        Assert.IsType<TencentAsrSession>(session);
    }

    [Fact]
    public async Task Aliyun_adapter_creates_the_existing_realtime_session()
    {
        var adapter = new AliyunFileTranscriptionSessionAdapter(
            _ => Task.FromResult<string?>("api-key"),
            new FakeSocketFactory());

        await using var session = await adapter.CreateSessionAsync(
            RecognitionLanguage.English,
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Equal(AsrProviderId.AliyunDashScope, adapter.Provider);
        Assert.IsType<AliyunRealtimeAsrSession>(session);
    }

    [Fact]
    public async Task Volcengine_adapter_creates_the_existing_realtime_session()
    {
        var adapter = new VolcengineFileTranscriptionSessionAdapter(
            _ => Task.FromResult<VolcengineAsrCredentials?>(new(
                "app-id", "access-token", "secret-key")),
            new FakeSocketFactory());

        await using var session = await adapter.CreateSessionAsync(
            RecognitionLanguage.Japanese,
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Equal(AsrProviderId.Volcengine, adapter.Provider);
        Assert.IsType<VolcengineRealtimeAsrSession>(session);
    }

    [Fact]
    public async Task Missing_cloud_credentials_are_reported_without_creating_a_socket()
    {
        var sockets = new FakeSocketFactory();
        var adapter = new AliyunFileTranscriptionSessionAdapter(
            _ => Task.FromResult<string?>(null),
            sockets);

        var error = await Assert.ThrowsAsync<FileTranscriptionProviderUnavailableException>(async () =>
            await adapter.CreateSessionAsync(
                RecognitionLanguage.Automatic,
                Guid.NewGuid(),
                CancellationToken.None));

        Assert.Equal(AsrProviderId.AliyunDashScope, error.Provider);
        Assert.Equal(0, sockets.CreatedCount);
    }

    private sealed class FakeSocketFactory : ICloudWebSocketFactory
    {
        public int CreatedCount { get; private set; }

        public ICloudWebSocket Create()
        {
            CreatedCount++;
            return new FakeSocket();
        }
    }

    private sealed class FakeSocket : ICloudWebSocket
    {
        public ValueTask ConnectAsync(
            CloudWebSocketConnectRequest request,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask SendBinaryAsync(
            ReadOnlyMemory<byte> payload,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask SendTextAsync(
            string payload,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask<CloudWebSocketReceiveMessage> ReceiveAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(CloudWebSocketReceiveMessage.Closed());

        public ValueTask CloseAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
