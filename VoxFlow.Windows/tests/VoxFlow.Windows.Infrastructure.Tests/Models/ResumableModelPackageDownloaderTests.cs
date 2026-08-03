using System.Net;
using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class ResumableModelPackageDownloaderTests
{
    [Fact]
    public async Task Concurrent_requests_for_the_same_revision_share_one_transfer()
    {
        using var directory = new TemporaryDirectory();
        var responseGate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var requestStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var requestCount = 0;
        var handler = new AsyncDelegateHandler(async (_, cancellationToken) =>
        {
            Interlocked.Increment(ref requestCount);
            requestStarted.TrySetResult();
            await responseGate.Task.WaitAsync(cancellationToken);
            return Response([1, 2, 3, 4]);
        });
        using var client = new HttpClient(handler);
        var packageDownloader = new ResumableModelPackageDownloader(
            new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero));
        var manifest = Manifest([1, 2, 3, 4]);

        var first = packageDownloader.StartAsync(manifest, directory.Path);
        await requestStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var second = packageDownloader.StartAsync(manifest, directory.Path);

        Assert.Same(first, second);
        responseGate.SetResult();
        var result = await first;
        Assert.Equal(ModelPackageDownloadOutcome.Completed, result.Outcome);
        Assert.Equal(1, requestCount);
        Assert.True(File.Exists(Path.Combine(directory.Path, "payload", "model.bin")));
        Assert.True(File.Exists(Path.Combine(directory.Path, ".download-state.json")));
        Assert.Empty(Directory.EnumerateFiles(
            directory.Path,
            ".download-state.json.tmp-*"));
    }

    [Theory]
    [InlineData(true, ModelPackageDownloadOutcome.Paused)]
    [InlineData(false, ModelPackageDownloadOutcome.Cancelled)]
    public async Task Pause_or_cancel_preserves_partial_and_download_state(
        bool pause,
        ModelPackageDownloadOutcome expectedOutcome)
    {
        using var directory = new TemporaryDirectory();
        var stream = new GateAfterFirstChunkStream([1, 2, 3, 4, 5, 6]);
        var handler = new AsyncDelegateHandler((_, _) => Task.FromResult(Response(stream, 6)));
        using var client = new HttpClient(handler);
        var packageDownloader = new ResumableModelPackageDownloader(
            new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero));
        var manifest = Manifest([1, 2, 3, 4, 5, 6]);

        var download = packageDownloader.StartAsync(manifest, directory.Path);
        await stream.FirstChunkRead.WaitAsync(TimeSpan.FromSeconds(5));
        if (pause)
        {
            await packageDownloader.PauseAsync(manifest.Id, manifest.ModelRevision);
        }
        else
        {
            await packageDownloader.CancelAsync(manifest.Id, manifest.ModelRevision);
        }

        var result = await download;
        Assert.Equal(expectedOutcome, result.Outcome);
        Assert.True(File.Exists(Path.Combine(directory.Path, "payload", "model.bin.partial")));
        Assert.True(new FileInfo(Path.Combine(directory.Path, "payload", "model.bin.partial")).Length > 0);
        Assert.True(File.Exists(Path.Combine(directory.Path, ".download-state.json")));
    }

    private static QwenModelManifest Manifest(byte[] bytes) => new(
        "qwen3-asr-0.6b",
        "Qwen 0.6B",
        QwenVariant.Qwen06B,
        "revision",
        "runtime",
        bytes.Length,
        [new QwenModelFile(
            "model.bin",
            new Uri("https://models.invalid/model.bin"),
            bytes.Length,
            Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant())],
        new QwenRuntimePublicationGate(true, null));

    private static HttpResponseMessage Response(byte[] bytes) => new(HttpStatusCode.OK)
    {
        Content = new ByteArrayContent(bytes),
    };

    private static HttpResponseMessage Response(Stream stream, long length)
    {
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StreamContent(stream),
        };
        response.Content.Headers.ContentLength = length;
        return response;
    }

    private sealed class AsyncDelegateHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => respond(request, cancellationToken);
    }

    private sealed class GateAfterFirstChunkStream(byte[] bytes) : Stream
    {
        private readonly TaskCompletionSource firstChunkRead =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int offset;

        public Task FirstChunkRead => firstChunkRead.Task;
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => bytes.Length;
        public override long Position { get => offset; set => throw new NotSupportedException(); }

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (offset == 0)
            {
                var count = Math.Min(2, buffer.Length);
                bytes.AsMemory(0, count).CopyTo(buffer);
                offset = count;
                firstChunkRead.TrySetResult();
                return count;
            }

            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }

        public override int Read(byte[] buffer, int bufferOffset, int count) =>
            throw new NotSupportedException();

        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
