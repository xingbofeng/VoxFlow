using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;

namespace VoxFlow.Windows.Infrastructure.Models;

public enum ModelFileDownloadOutcome
{
    Completed,
}

public sealed record ModelFileDownloadResult(
    ModelFileDownloadOutcome Outcome,
    long BytesDownloaded);

public sealed class ResumableModelFileDownloader
{
    private const int BufferSize = 64 * 1024;
    private readonly HttpClient httpClient;
    private readonly int maximumAttempts;
    private readonly TimeSpan retryDelay;

    public ResumableModelFileDownloader(
        HttpClient httpClient,
        int maximumAttempts = 3,
        TimeSpan? retryDelay = null)
    {
        this.httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        if (maximumAttempts <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumAttempts));
        }

        this.maximumAttempts = maximumAttempts;
        this.retryDelay = retryDelay ?? TimeSpan.FromSeconds(1);
    }

    public async Task<ModelFileDownloadResult> DownloadAsync(
        QwenModelFile file,
        string destinationPath,
        Action<long>? progress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(file);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);
        var fullDestinationPath = Path.GetFullPath(destinationPath);
        var partialPath = fullDestinationPath + ".partial";
        Directory.CreateDirectory(Path.GetDirectoryName(fullDestinationPath)!);

        if (File.Exists(fullDestinationPath))
        {
            var installedLength = new FileInfo(fullDestinationPath).Length;
            if (installedLength == file.Bytes
                && await HasExpectedSha256Async(
                    fullDestinationPath,
                    file.Sha256,
                    cancellationToken).ConfigureAwait(false))
            {
                progress?.Invoke(installedLength);
                return new ModelFileDownloadResult(ModelFileDownloadOutcome.Completed, installedLength);
            }

            File.Delete(fullDestinationPath);
        }

        for (var attempt = 1; attempt <= maximumAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var offset = File.Exists(partialPath) ? new FileInfo(partialPath).Length : 0;
            if (offset > file.Bytes)
            {
                throw new InvalidDataException("The partial model file exceeds the manifest size.");
            }

            if (offset == file.Bytes)
            {
                File.Move(partialPath, fullDestinationPath, overwrite: true);
                progress?.Invoke(offset);
                return new ModelFileDownloadResult(ModelFileDownloadOutcome.Completed, offset);
            }

            try
            {
                await DownloadAttemptAsync(
                    file,
                    partialPath,
                    offset,
                    progress,
                    cancellationToken).ConfigureAwait(false);

                var completedLength = new FileInfo(partialPath).Length;
                if (completedLength != file.Bytes)
                {
                    throw new EndOfStreamException(
                        $"Model transfer ended at {completedLength} of {file.Bytes} bytes.");
                }

                File.Move(partialPath, fullDestinationPath, overwrite: true);
                return new ModelFileDownloadResult(
                    ModelFileDownloadOutcome.Completed,
                    completedLength);
            }
            catch (Exception exception) when (
                attempt < maximumAttempts && IsTransient(exception))
            {
                if (retryDelay > TimeSpan.Zero)
                {
                    await Task.Delay(retryDelay, cancellationToken).ConfigureAwait(false);
                }
            }
        }

        throw new InvalidOperationException("The model transfer retry loop ended unexpectedly.");
    }

    private async Task DownloadAttemptAsync(
        QwenModelFile file,
        string partialPath,
        long offset,
        Action<long>? progress,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, file.Source);
        if (offset > 0)
        {
            request.Headers.Range = new RangeHeaderValue(offset, null);
        }

        using var response = await httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken).ConfigureAwait(false);

        var mode = response.StatusCode switch
        {
            HttpStatusCode.PartialContent => ValidatePartialResponse(response, offset, file.Bytes),
            HttpStatusCode.OK => ValidateFullResponse(response, file.Bytes),
            _ => throw new HttpRequestException(
                $"Model server returned HTTP {(int)response.StatusCode}.",
                inner: null,
                response.StatusCode),
        };

        await using var source = await response.Content
            .ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        await using var destination = new FileStream(
            partialPath,
            mode,
            FileAccess.Write,
            FileShare.Read,
            BufferSize,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        var totalWritten = mode == FileMode.Append ? offset : 0;
        var buffer = new byte[BufferSize];
        while (true)
        {
            var read = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken)
                .ConfigureAwait(false);
            totalWritten = checked(totalWritten + read);
            if (totalWritten > file.Bytes)
            {
                throw new InvalidDataException("Model server sent more bytes than declared by the manifest.");
            }

            progress?.Invoke(totalWritten);
        }

        await destination.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static FileMode ValidatePartialResponse(
        HttpResponseMessage response,
        long offset,
        long expectedBytes)
    {
        var range = response.Content.Headers.ContentRange;
        if (range?.From != offset
            || range.To != expectedBytes - 1
            || range.Length != expectedBytes)
        {
            throw new InvalidDataException("Model server returned a mismatched Content-Range.");
        }

        var expectedContentLength = expectedBytes - offset;
        if (response.Content.Headers.ContentLength is long contentLength
            && contentLength != expectedContentLength)
        {
            throw new InvalidDataException("Model partial response length does not match Content-Range.");
        }

        return offset == 0 ? FileMode.Create : FileMode.Append;
    }

    private static FileMode ValidateFullResponse(
        HttpResponseMessage response,
        long expectedBytes)
    {
        if (response.Content.Headers.ContentLength is long contentLength
            && contentLength != expectedBytes)
        {
            throw new InvalidDataException("Model response length does not match the manifest.");
        }

        return FileMode.Create;
    }

    private static bool IsTransient(Exception exception) => exception switch
    {
        HttpRequestException { StatusCode: null } => true,
        HttpRequestException { StatusCode: HttpStatusCode.RequestTimeout } => true,
        HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests } => true,
        HttpRequestException { StatusCode: >= HttpStatusCode.InternalServerError } => true,
        IOException when exception is not InvalidDataException => true,
        _ => false,
    };

    private static async Task<bool> HasExpectedSha256Async(
        string path,
        string expectedSha256,
        CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            128 * 1024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        var digest = await SHA256.HashDataAsync(stream, cancellationToken)
            .ConfigureAwait(false);
        return Convert.ToHexString(digest)
            .Equals(expectedSha256, StringComparison.OrdinalIgnoreCase);
    }
}
