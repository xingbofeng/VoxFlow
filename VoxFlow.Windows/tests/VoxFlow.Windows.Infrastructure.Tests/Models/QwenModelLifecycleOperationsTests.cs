using System.Net;
using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class QwenModelLifecycleOperationsTests
{
    [Fact]
    public async Task Explicit_download_runs_the_persisted_pipeline_to_ready()
    {
        using var fixture = new LifecycleFixture();

        var result = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Ready, result.Phase);
        Assert.Equal(
            [
                ModelInstallPhase.Queued,
                ModelInstallPhase.Downloading,
                ModelInstallPhase.Verifying,
                ModelInstallPhase.Installing,
                ModelInstallPhase.Prewarming,
                ModelInstallPhase.CanaryTesting,
                ModelInstallPhase.Ready,
            ],
            fixture.Publisher.States
                .Select(state => state.Phase)
                .Distinct()
                .ToArray());
        Assert.Equal(1, fixture.Handler.RequestCount);
        Assert.True(Directory.Exists(fixture.Paths.GetInstallDirectory(
            fixture.Manifest.Variant,
            fixture.Manifest.ModelRevision)));
    }

    [Fact]
    public async Task Missing_user_action_or_space_never_starts_http_transfer()
    {
        using var fixture = new LifecycleFixture();

        var manual = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: false,
            CancellationToken.None);
        fixture.Disk.AvailableBytes = 0;
        var noSpace = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.NotDownloaded, manual.Phase);
        Assert.Equal(ModelInstallPhase.InsufficientSpace, noSpace.Phase);
        Assert.Equal("insufficient_space", noSpace.ErrorCode);
        Assert.Equal(0, fixture.Handler.RequestCount);
    }

    [Fact]
    public async Task Blocked_runtime_provenance_refuses_download_before_any_network_request()
    {
        using var fixture = new LifecycleFixture(runtimePublishable: false);

        var result = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.RuntimeUnsupported, result.Phase);
        Assert.Equal("runtime_provenance_blocked", result.ErrorCode);
        Assert.Equal(0, fixture.Handler.RequestCount);
        Assert.False(Directory.Exists(fixture.Paths.GetVariantStagingRoot(fixture.Manifest.Variant)));
    }

    [Fact]
    public async Task Retry_replaces_a_complete_staging_file_that_failed_sha256()
    {
        using var fixture = new LifecycleFixture();
        fixture.Handler.Content = [9, 9, 9, 9];
        var corrupted = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);
        Assert.Equal(ModelInstallPhase.Corrupted, corrupted.Phase);
        fixture.Handler.Content = [1, 2, 3, 4];

        var recovered = await fixture.Operations.RetryAsync(
            fixture.Manifest,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Ready, recovered.Phase);
        Assert.Equal(2, fixture.Handler.RequestCount);
    }

    [Fact]
    public async Task Valid_installed_payload_recovers_failed_state_without_downloading_again()
    {
        using var fixture = new LifecycleFixture();
        var installed = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);
        Assert.Equal(ModelInstallPhase.Ready, installed.Phase);
        Assert.Equal(1, fixture.Handler.RequestCount);

        await fixture.Repository.SaveAsync(
            new ModelInstallRecord(
                installed.ModelId,
                installed.Version,
                ModelInstallPhase.RuntimeUnsupported,
                installed.BytesDownloaded,
                installed.TotalBytes,
                installed.InstallPath,
                "native_runtime_unavailable"),
            CancellationToken.None);
        var staleStaging = fixture.Paths.GetStagingDirectory(
            fixture.Manifest.Variant,
            fixture.Manifest.ModelRevision);
        Directory.CreateDirectory(staleStaging);
        await File.WriteAllTextAsync(
            Path.Combine(staleStaging, ".download-state.json"),
            "stale");

        var recovered = await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Ready, recovered.Phase);
        Assert.Equal(1, fixture.Handler.RequestCount);
        Assert.False(Directory.Exists(staleStaging));
    }

    [Fact]
    public async Task Deleting_the_selected_model_clears_files_and_all_entry_point_selection()
    {
        using var fixture = new LifecycleFixture(useStateProjection: true);
        await fixture.Operations.DownloadAsync(
            fixture.Manifest,
            userInitiated: true,
            CancellationToken.None);
        fixture.Operations.Select(fixture.Manifest.Id);
        Assert.True(Assert.Single(fixture.Projection!.Current.Menu).IsSelected);

        await fixture.Operations.DeleteAsync(fixture.Manifest, CancellationToken.None);

        var card = Assert.Single(fixture.Projection.Current.Menu);
        Assert.Equal(ModelInstallPhase.NotDownloaded, card.Phase);
        Assert.False(card.IsSelected);
        Assert.False(card.IsSelectable);
        Assert.False(Directory.Exists(fixture.Paths.GetVariantInstallRoot(fixture.Manifest.Variant)));
        Assert.Equal([(fixture.Manifest.Id, fixture.Manifest.ModelRevision)], fixture.Runtime.Released);
    }

    private sealed class LifecycleFixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly HttpClient client;

        public LifecycleFixture(
            bool useStateProjection = false,
            bool runtimePublishable = true)
        {
            byte[] content = [1, 2, 3, 4];
            Manifest = new QwenModelManifest(
                "qwen3-asr-0.6b",
                "Qwen 0.6B",
                QwenVariant.Qwen06B,
                "revision",
                "runtime",
                content.Length,
                [new QwenModelFile(
                    "model.bin",
                    new Uri("https://models.invalid/model.bin"),
                    content.Length,
                    Convert.ToHexString(SHA256.HashData(content)).ToLowerInvariant())],
                new QwenRuntimePublicationGate(
                    runtimePublishable,
                    runtimePublishable ? null : "MSVC validation blocked"));
            Paths = new QwenModelDataPaths(Path.Combine(directory.Path, "LocalAppData"));
            Handler = new CountingHandler(content);
            client = new HttpClient(Handler);
            var packageDownloader = new ResumableModelPackageDownloader(
                new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero));
            Repository = new MemoryRepository();
            Disk = new FakeDiskSpace
            {
                AvailableBytes = QwenModelDownloadPreflight.RequiredFreeBytes(Manifest),
            };
            Runtime = new FakeRuntime();
            Publisher = new CapturingPublisher();
            IModelInstallStatePublisher publisher = Publisher;
            QwenModelStateSynchronizer? synchronizer = null;
            if (useStateProjection)
            {
                var store = new VoxFlowStateStore();
                Projection = new QwenModelEntryPointProjection(store);
                synchronizer = new QwenModelStateSynchronizer(store);
                publisher = new CompositePublisher(Publisher, synchronizer);
            }

            var readiness = new QwenModelReadinessService(
                Repository,
                Runtime,
                publisher,
                new short[] { 0, 100, -100 });
            var deletion = new QwenModelDeletionService(Paths, Repository, Runtime, publisher);
            Operations = new QwenModelLifecycleOperations(
                Paths,
                Disk,
                packageDownloader,
                new QwenModelInstaller(new QwenModelIntegrityVerifier()),
                readiness,
                deletion,
                Repository,
                publisher,
                synchronizer);
        }

        public QwenModelManifest Manifest { get; }
        public QwenModelDataPaths Paths { get; }
        public CountingHandler Handler { get; }
        public MemoryRepository Repository { get; }
        public FakeDiskSpace Disk { get; }
        public FakeRuntime Runtime { get; }
        public CapturingPublisher Publisher { get; }
        public QwenModelEntryPointProjection? Projection { get; }
        public IQwenModelOperations Operations { get; }

        public void Dispose()
        {
            Projection?.Dispose();
            client.Dispose();
            directory.Dispose();
        }
    }

    private sealed class CountingHandler(byte[] content) : HttpMessageHandler
    {
        public byte[] Content { get; set; } = content;

        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(Content),
            });
        }
    }

    private sealed class MemoryRepository : IModelInstallStateRepository
    {
        private readonly Dictionary<string, ModelInstallRecord> states = [];

        public ValueTask<ModelInstallRecord?> LoadAsync(
            string modelId,
            CancellationToken cancellationToken)
        {
            states.TryGetValue(modelId, out var state);
            return ValueTask.FromResult(state);
        }

        public ValueTask SaveAsync(ModelInstallRecord state, CancellationToken cancellationToken)
        {
            states[state.ModelId] = state;
            return ValueTask.CompletedTask;
        }

        public ValueTask DeleteAsync(string modelId, CancellationToken cancellationToken)
        {
            states.Remove(modelId);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeDiskSpace : IModelDiskSpaceProbe
    {
        public long AvailableBytes { get; set; }

        public long GetAvailableBytes(string path) => AvailableBytes;
    }

    private sealed class FakeRuntime : IQwenModelRuntimeReadiness
    {
        public List<(string ModelId, string Revision)> Released { get; } = [];

        public ValueTask<QwenRuntimePrewarmResult> PrewarmAsync(
            QwenModelManifest manifest,
            string installPath,
            CancellationToken cancellationToken) => ValueTask.FromResult(
                new QwenRuntimePrewarmResult(QwenRuntimePrewarmStatus.Ready, null));

        public ValueTask<QwenCanaryResult> RunCanaryAsync(
            QwenModelManifest manifest,
            string installPath,
            ReadOnlyMemory<short> pcm16,
            CancellationToken cancellationToken) => ValueTask.FromResult(
                new QwenCanaryResult(true, "canary final", null));

        public ValueTask ReleaseAsync(
            string modelId,
            string revision,
            CancellationToken cancellationToken)
        {
            Released.Add((modelId, revision));
            return ValueTask.CompletedTask;
        }
    }

    private sealed class CapturingPublisher : IModelInstallStatePublisher
    {
        public List<ModelInstallRecord> States { get; } = [];

        public void Publish(QwenModelManifest manifest, ModelInstallRecord state) =>
            States.Add(state);
    }

    private sealed class CompositePublisher(
        IModelInstallStatePublisher first,
        IModelInstallStatePublisher second) : IModelInstallStatePublisher
    {
        public void Publish(QwenModelManifest manifest, ModelInstallRecord state)
        {
            first.Publish(manifest, state);
            second.Publish(manifest, state);
        }
    }
}
