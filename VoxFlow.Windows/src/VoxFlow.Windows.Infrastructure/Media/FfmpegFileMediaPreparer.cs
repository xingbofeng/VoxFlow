using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Media;

public sealed class FileMediaPreparationException
    : FileTranscriptionMediaPreparationException
{
    public FileMediaPreparationException(FileTranscriptionErrorCode errorCode)
        : base(errorCode)
    {
    }
}

public sealed record FfmpegMediaProbeResult(
    long DurationMs,
    string FormatName,
    bool HasAudioTrack);

public interface IAvailableDiskSpaceProbe
{
    long GetAvailableBytes(string path);
}

public sealed class AvailableDiskSpaceProbe : IAvailableDiskSpaceProbe
{
    public long GetAvailableBytes(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var root = Path.GetPathRoot(Path.GetFullPath(path))
            ?? throw new IOException("The temporary storage root is unavailable.");
        return new DriveInfo(root).AvailableFreeSpace;
    }
}

public sealed class PreparedFileMedia : IAsyncDisposable
{
    private readonly string taskDirectory;
    private int disposed;

    internal PreparedFileMedia(string preparedAudioPath, long durationMs, string taskDirectory)
    {
        PreparedAudioPath = preparedAudioPath;
        DurationMs = durationMs;
        this.taskDirectory = taskDirectory;
    }

    public string PreparedAudioPath { get; }

    public long DurationMs { get; }

    internal string TaskDirectory => taskDirectory;

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0 && Directory.Exists(taskDirectory))
        {
            Directory.Delete(taskDirectory, recursive: true);
        }

        return ValueTask.CompletedTask;
    }
}

public sealed class PreparedWindowMedia : IFileTranscriptionWindowLease
{
    private int disposed;

    internal PreparedWindowMedia(string audioPath)
    {
        AudioPath = audioPath;
    }

    public string AudioPath { get; }

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0 && File.Exists(AudioPath))
        {
            File.Delete(AudioPath);
        }

        return ValueTask.CompletedTask;
    }
}

public sealed class FfmpegTranscriptionWindowSource : IFileTranscriptionWindowSource
{
    private readonly FfmpegFileMediaPreparer preparer;
    private readonly PreparedFileMedia preparedMedia;

    public FfmpegTranscriptionWindowSource(
        FfmpegFileMediaPreparer preparer,
        PreparedFileMedia preparedMedia)
    {
        this.preparer = preparer ?? throw new ArgumentNullException(nameof(preparer));
        this.preparedMedia = preparedMedia ?? throw new ArgumentNullException(nameof(preparedMedia));
    }

    public async ValueTask<IFileTranscriptionWindowLease> CreateAsync(
        FileTranscriptionWindow window,
        CancellationToken cancellationToken) =>
        await preparer
            .CreateWindowAsync(preparedMedia, window, cancellationToken)
            .ConfigureAwait(false);
}

public sealed class FfmpegPreparedFileTranscriptionMedia
    : IPreparedFileTranscriptionMedia
{
    private readonly PreparedFileMedia preparedMedia;

    internal FfmpegPreparedFileTranscriptionMedia(
        FfmpegFileMediaPreparer preparer,
        PreparedFileMedia preparedMedia)
    {
        ArgumentNullException.ThrowIfNull(preparer);
        this.preparedMedia = preparedMedia
            ?? throw new ArgumentNullException(nameof(preparedMedia));
        WindowSource = new FfmpegTranscriptionWindowSource(preparer, preparedMedia);
    }

    public long DurationMs => preparedMedia.DurationMs;

    public IFileTranscriptionWindowSource WindowSource { get; }

    public ValueTask DisposeAsync() => preparedMedia.DisposeAsync();
}

public sealed class FfmpegFileTranscriptionMediaPreparer
    : IFileTranscriptionMediaPreparer
{
    private readonly FfmpegFileMediaPreparer preparer;
    private readonly string temporaryRoot;

    public FfmpegFileTranscriptionMediaPreparer(
        FfmpegFileMediaPreparer preparer,
        string temporaryRoot)
    {
        this.preparer = preparer ?? throw new ArgumentNullException(nameof(preparer));
        ArgumentException.ThrowIfNullOrWhiteSpace(temporaryRoot);
        this.temporaryRoot = Path.GetFullPath(temporaryRoot);
    }

    public async ValueTask<IPreparedFileTranscriptionMedia> PrepareAsync(
        FileTranscriptionJob job,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(job);
        var prepared = await preparer.PrepareAsync(
            job.SourcePath,
            job.Id,
            temporaryRoot,
            cancellationToken).ConfigureAwait(false);
        return new FfmpegPreparedFileTranscriptionMedia(preparer, prepared);
    }
}

public sealed class FfmpegFileMediaPreparer
{
    private static readonly JsonSerializerOptions ProbeSerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly HashSet<string> SupportedExtensions = new(
        [".mp3", ".wav", ".m4a", ".aac", ".mp4", ".mov"],
        StringComparer.OrdinalIgnoreCase);

    private readonly FfmpegRuntimeLocator locator;
    private readonly IFfmpegRuntimeVerifier verifier;
    private readonly IFfmpegProcessRunner processRunner;
    private readonly IAvailableDiskSpaceProbe diskSpace;
    private readonly object runtimeVerificationSync = new();
    private bool runtimeVerified;

    public FfmpegFileMediaPreparer(
        FfmpegRuntimeLocator locator,
        IFfmpegRuntimeVerifier verifier,
        IFfmpegProcessRunner processRunner,
        IAvailableDiskSpaceProbe? diskSpace = null)
    {
        this.locator = locator ?? throw new ArgumentNullException(nameof(locator));
        this.verifier = verifier ?? throw new ArgumentNullException(nameof(verifier));
        this.processRunner = processRunner ?? throw new ArgumentNullException(nameof(processRunner));
        this.diskSpace = diskSpace ?? new AvailableDiskSpaceProbe();
    }

    public async Task<FfmpegMediaProbeResult> ProbeAsync(
        string sourcePath,
        CancellationToken cancellationToken)
    {
        ValidateSource(sourcePath);
        EnsureRuntime();

        var request = new FfmpegProcessRequest(
            locator.FfprobePath,
            [
                "-v", "error",
                "-select_streams", "a:0",
                "-show_entries", "stream=index,codec_type:format=duration,format_name",
                "-of", "json",
                sourcePath,
            ]);
        var result = await processRunner.RunAsync(request, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.UnsupportedMedia);
        }

        FfprobeDocument document;
        try
        {
            document = JsonSerializer.Deserialize<FfprobeDocument>(
                result.StandardOutput,
                ProbeSerializerOptions)
                ?? throw new JsonException("ffprobe returned an empty document.");
        }
        catch (JsonException)
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.UnsupportedMedia);
        }

        if (document.Streams is null ||
            !document.Streams.Any(stream =>
                string.Equals(stream.CodecType, "audio", StringComparison.OrdinalIgnoreCase)))
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.NoAudioTrack);
        }

        if (document.Format is null ||
            !double.TryParse(
                document.Format.Duration,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var durationSeconds) ||
            durationSeconds <= 0 ||
            double.IsNaN(durationSeconds) ||
            double.IsInfinity(durationSeconds))
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.UnsupportedMedia);
        }

        return new FfmpegMediaProbeResult(
            Math.Max(1, checked((long)Math.Round(durationSeconds * 1_000))),
            document.Format.FormatName ?? string.Empty,
            true);
    }

    public async Task<PreparedFileMedia> PrepareAsync(
        string sourcePath,
        string jobId,
        string temporaryRoot,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        ArgumentException.ThrowIfNullOrWhiteSpace(temporaryRoot);
        var probe = await ProbeAsync(sourcePath, cancellationToken).ConfigureAwait(false);
        var requiredBytes = Math.Max(16L * 1_024 * 1_024, checked(probe.DurationMs * 64));
        if (diskSpace.GetAvailableBytes(temporaryRoot) < requiredBytes)
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.InsufficientDiskSpace);
        }

        var taskDirectory = Path.Combine(
            Path.GetFullPath(temporaryRoot),
            "VoxFlow-FileTranscription",
            StableDirectoryName(jobId));
        Directory.CreateDirectory(taskDirectory);
        var preparedPath = Path.Combine(taskDirectory, "prepared.wav");

        var request = new FfmpegProcessRequest(
            locator.FfmpegPath,
            [
                "-nostdin",
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-i", sourcePath,
                "-map", "0:a:0",
                "-vn",
                "-ac", "1",
                "-ar", "16000",
                "-c:a", "pcm_s16le",
                preparedPath,
            ]);
        try
        {
            var result = await processRunner.RunAsync(request, cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0 || !File.Exists(preparedPath))
            {
                throw new FileMediaPreparationException(FileTranscriptionErrorCode.UnsupportedMedia);
            }

            return new PreparedFileMedia(preparedPath, probe.DurationMs, taskDirectory);
        }
        catch
        {
            if (Directory.Exists(taskDirectory))
            {
                Directory.Delete(taskDirectory, recursive: true);
            }

            throw;
        }
    }

    public async Task<PreparedWindowMedia> CreateWindowAsync(
        PreparedFileMedia preparedMedia,
        FileTranscriptionWindow window,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(preparedMedia);
        ArgumentNullException.ThrowIfNull(window);
        if (window.StartMs < 0 ||
            window.EndMs <= window.StartMs ||
            window.EndMs > preparedMedia.DurationMs)
        {
            throw new ArgumentOutOfRangeException(nameof(window));
        }

        EnsureRuntime();
        var outputPath = Path.Combine(
            preparedMedia.TaskDirectory,
            $"segment-{window.Index:D6}.wav");
        var request = new FfmpegProcessRequest(
            locator.FfmpegPath,
            [
                "-nostdin",
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-ss", FormatSeconds(window.StartMs),
                "-i", preparedMedia.PreparedAudioPath,
                "-t", FormatSeconds(window.EndMs - window.StartMs),
                "-ac", "1",
                "-ar", "16000",
                "-c:a", "pcm_s16le",
                outputPath,
            ]);
        try
        {
            var result = await processRunner.RunAsync(request, cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0 || !File.Exists(outputPath))
            {
                throw new FileMediaPreparationException(FileTranscriptionErrorCode.UnsupportedMedia);
            }

            return new PreparedWindowMedia(outputPath);
        }
        catch
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }

            throw;
        }
    }

    private void EnsureRuntime()
    {
        if (Volatile.Read(ref runtimeVerified)) return;
        lock (runtimeVerificationSync)
        {
            if (runtimeVerified) return;
            var verification = verifier.Verify(locator.RuntimeDirectory);
            if (!verification.IsValid)
            {
                throw new FileMediaPreparationException(FileTranscriptionErrorCode.RuntimeUnavailable);
            }
            Volatile.Write(ref runtimeVerified, true);
        }
    }

    private static void ValidateSource(string sourcePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        if (!SupportedExtensions.Contains(Path.GetExtension(sourcePath)))
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.UnsupportedMedia);
        }

        if (!File.Exists(sourcePath))
        {
            throw new FileMediaPreparationException(FileTranscriptionErrorCode.SourceUnavailable);
        }
    }

    private static string StableDirectoryName(string jobId)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(jobId));
        return Convert.ToHexString(hash[..12]).ToLowerInvariant();
    }

    private static string FormatSeconds(long milliseconds) =>
        (milliseconds / 1_000D).ToString("0.000", CultureInfo.InvariantCulture);

    private sealed record FfprobeDocument(
        IReadOnlyList<FfprobeStream>? Streams,
        FfprobeFormat? Format);

    private sealed record FfprobeStream(
        int Index,
        [property: System.Text.Json.Serialization.JsonPropertyName("codec_type")]
        string? CodecType);

    private sealed record FfprobeFormat(
        string? Duration,
        [property: System.Text.Json.Serialization.JsonPropertyName("format_name")]
        string? FormatName);
}

public sealed class FfmpegTemporaryFileCleaner
{
    public int CleanupStaleDirectories(string temporaryRoot, DateTimeOffset cutoffUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(temporaryRoot);
        var workspaceRoot = Path.Combine(
            Path.GetFullPath(temporaryRoot),
            "VoxFlow-FileTranscription");
        if (!Directory.Exists(workspaceRoot))
        {
            return 0;
        }

        var removed = 0;
        foreach (var directory in Directory.EnumerateDirectories(workspaceRoot))
        {
            if (Directory.GetLastWriteTimeUtc(directory) >= cutoffUtc.UtcDateTime)
            {
                continue;
            }

            try
            {
                Directory.Delete(directory, recursive: true);
                removed++;
            }
            catch (IOException)
            {
                // A live or externally locked task directory is retried at the next startup.
            }
            catch (UnauthorizedAccessException)
            {
                // Fail closed without touching paths outside the controlled workspace.
            }
        }

        return removed;
    }
}
