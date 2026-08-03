using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class ResumableModelFileDownloaderTests
{
    [Fact]
    public async Task Range_206_appends_exactly_at_the_partial_offset()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "model.bin");
        await File.WriteAllBytesAsync(destination + ".partial", [1, 2]);
        var handler = new DelegateHandler(request =>
        {
            Assert.Equal(2, request.Headers.Range!.Ranges.Single().From);
            return Response(
                HttpStatusCode.PartialContent,
                [3, 4],
                new ContentRangeHeaderValue(2, 3, 4));
        });
        using var client = new HttpClient(handler);
        var downloader = new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero);

        var result = await downloader.DownloadAsync(
            ManifestFile([1, 2, 3, 4]),
            destination,
            progress: null,
            CancellationToken.None);

        Assert.Equal(ModelFileDownloadOutcome.Completed, result.Outcome);
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, await File.ReadAllBytesAsync(destination));
        Assert.False(System.IO.File.Exists(destination + ".partial"));
    }

    [Fact]
    public async Task Range_ignored_with_200_replaces_the_partial_file()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "model.bin");
        await File.WriteAllBytesAsync(destination + ".partial", [9, 9]);
        var handler = new DelegateHandler(_ => Response(HttpStatusCode.OK, [1, 2, 3, 4]));
        using var client = new HttpClient(handler);
        var downloader = new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero);

        await downloader.DownloadAsync(ManifestFile([1, 2, 3, 4]), destination, null, CancellationToken.None);

        Assert.Equal(new byte[] { 1, 2, 3, 4 }, await File.ReadAllBytesAsync(destination));
    }

    [Fact]
    public async Task Mismatched_content_range_is_rejected_without_mutating_the_partial()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "model.bin");
        await File.WriteAllBytesAsync(destination + ".partial", [1, 2]);
        var handler = new DelegateHandler(_ => Response(
            HttpStatusCode.PartialContent,
            [3],
            new ContentRangeHeaderValue(3, 3, 4)));
        using var client = new HttpClient(handler);
        var downloader = new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero);

        var error = await Assert.ThrowsAsync<InvalidDataException>(() =>
            downloader.DownloadAsync(ManifestFile([1, 2, 3, 4]), destination, null, CancellationToken.None));

        Assert.Contains("range", error.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(new byte[] { 1, 2 }, await File.ReadAllBytesAsync(destination + ".partial"));
        Assert.False(System.IO.File.Exists(destination));
    }

    [Fact]
    public async Task Transient_network_failures_retry_from_the_preserved_offset()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "model.bin");
        await File.WriteAllBytesAsync(destination + ".partial", [1, 2]);
        var attempts = 0;
        var handler = new DelegateHandler(request =>
        {
            attempts++;
            Assert.Equal(2, request.Headers.Range!.Ranges.Single().From);
            if (attempts < 3)
            {
                throw new HttpRequestException("transient");
            }

            return Response(
                HttpStatusCode.PartialContent,
                [3, 4],
                new ContentRangeHeaderValue(2, 3, 4));
        });
        using var client = new HttpClient(handler);
        var downloader = new ResumableModelFileDownloader(
            client,
            maximumAttempts: 3,
            retryDelay: TimeSpan.Zero);

        await downloader.DownloadAsync(ManifestFile([1, 2, 3, 4]), destination, null, CancellationToken.None);

        Assert.Equal(3, attempts);
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, await File.ReadAllBytesAsync(destination));
    }

    [Fact]
    public async Task Cancellation_preserves_the_bytes_already_written_to_partial()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "model.bin");
        var source = new CancellableChunkStream([1, 2, 3, 4, 5, 6]);
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StreamContent(source),
        };
        response.Content.Headers.ContentLength = 6;
        var handler = new DelegateHandler(_ => response);
        using var client = new HttpClient(handler);
        var downloader = new ResumableModelFileDownloader(client, retryDelay: TimeSpan.Zero);
        using var cancellation = new CancellationTokenSource();

        var download = downloader.DownloadAsync(
            ManifestFile([1, 2, 3, 4, 5, 6]),
            destination,
            bytes =>
            {
                if (bytes >= 2)
                {
                    cancellation.Cancel();
                }
            },
            cancellation.Token);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => download);
        var partial = await File.ReadAllBytesAsync(destination + ".partial");
        Assert.NotEmpty(partial);
        Assert.True(partial.Length < 6);
        Assert.False(System.IO.File.Exists(destination));
    }

    private static QwenModelFile ManifestFile(byte[] content) => new(
        "model.bin",
        new Uri("https://models.invalid/model.bin"),
        content.Length,
        Convert.ToHexString(SHA256.HashData(content)).ToLowerInvariant());

    private static HttpResponseMessage Response(
        HttpStatusCode status,
        byte[] content,
        ContentRangeHeaderValue? range = null)
    {
        var response = new HttpResponseMessage(status)
        {
            Content = new ByteArrayContent(content),
        };
        response.Content.Headers.ContentLength = content.Length;
        response.Content.Headers.ContentRange = range;
        return response;
    }

    private sealed class DelegateHandler(
        Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => Task.FromResult(respond(request));
    }

    private sealed class CancellableChunkStream(byte[] bytes) : Stream
    {
        private int offset;

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
            if (offset >= bytes.Length)
            {
                return 0;
            }

            await Task.Yield();
            var count = Math.Min(2, Math.Min(buffer.Length, bytes.Length - offset));
            bytes.AsMemory(offset, count).CopyTo(buffer);
            offset += count;
            return count;
        }

        public override int Read(byte[] buffer, int bufferOffset, int count) =>
            throw new NotSupportedException();

        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
