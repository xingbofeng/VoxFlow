using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Infrastructure.Media;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class FfmpegFileMediaPreparerTests
{
    [Theory]
    [InlineData("mp3")]
    [InlineData("wav")]
    [InlineData("m4a")]
    [InlineData("aac")]
    [InlineData("mp4")]
    [InlineData("mov")]
    public async Task Supported_audio_and_video_fixtures_probe_the_first_audio_track(string extension)
    {
        var sourcePath = FixturePath($"tone.{extension}");
        var runner = new FakeProcessRunner(ProbeJson(hasAudio: true));
        var preparer = CreatePreparer(runner);

        var result = await preparer.ProbeAsync(sourcePath, CancellationToken.None);

        Assert.True(result.HasAudioTrack);
        Assert.InRange(result.DurationMs, 190, 250);
        var request = Assert.Single(runner.Requests);
        Assert.EndsWith("ffprobe.exe", request.ExecutablePath, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(sourcePath, request.Arguments[^1]);
    }

    [Fact]
    public async Task Video_without_an_audio_track_fails_before_media_conversion()
    {
        var runner = new FakeProcessRunner(ProbeJson(hasAudio: false));
        var preparer = CreatePreparer(runner);

        var exception = await Assert.ThrowsAsync<FileMediaPreparationException>(async () =>
            await preparer.ProbeAsync(FixturePath("tone.mp4"), CancellationToken.None));

        Assert.Equal(FileTranscriptionErrorCode.NoAudioTrack, exception.ErrorCode);
        Assert.Single(runner.Requests);
    }

    [Fact]
    public async Task Preparation_normalizes_to_sixteen_kilohertz_mono_pcm_wav()
    {
        using var temporary = new TemporaryDirectory();
        var runner = new FakeProcessRunner(ProbeJson(hasAudio: true), createOutput: true);
        var preparer = CreatePreparer(runner);

        await using var prepared = await preparer.PrepareAsync(
            FixturePath("tone.mov"),
            "job-1",
            temporary.Path,
            CancellationToken.None);

        Assert.True(File.Exists(prepared.PreparedAudioPath));
        Assert.Equal(200, prepared.DurationMs);
        var conversion = runner.Requests[1];
        Assert.EndsWith("ffmpeg.exe", conversion.ExecutablePath, StringComparison.OrdinalIgnoreCase);
        AssertContainsPair(conversion.Arguments, "-ar", "16000");
        AssertContainsPair(conversion.Arguments, "-ac", "1");
        AssertContainsPair(conversion.Arguments, "-c:a", "pcm_s16le");
        Assert.Contains("-vn", conversion.Arguments);
    }

    [Fact]
    public async Task Window_file_uses_the_exact_start_and_truncated_duration_contract()
    {
        using var temporary = new TemporaryDirectory();
        var runner = new FakeProcessRunner(
            ProbeJson(hasAudio: true, durationSeconds: 60),
            createOutput: true);
        var preparer = CreatePreparer(runner);
        await using var prepared = await preparer.PrepareAsync(
            FixturePath("tone.wav"),
            "job-1",
            temporary.Path,
            CancellationToken.None);

        await using var window = await preparer.CreateWindowAsync(
            prepared,
            new FileTranscriptionWindow(2, 57_000, 60_000),
            CancellationToken.None);

        Assert.True(File.Exists(window.AudioPath));
        var slicing = runner.Requests[2];
        AssertContainsPair(slicing.Arguments, "-ss", "57.000");
        AssertContainsPair(slicing.Arguments, "-t", "3.000");
        Assert.EndsWith("segment-000002.wav", window.AudioPath, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Successful_runtime_verification_is_cached_across_probe_and_windows()
    {
        using var temporary = new TemporaryDirectory();
        var runner = new FakeProcessRunner(
            ProbeJson(hasAudio: true, durationSeconds: 1),
            createOutput: true);
        var verifier = new CountingRuntimeVerifier();
        var preparer = new FfmpegFileMediaPreparer(
            new FfmpegRuntimeLocator(@"C:\Program Files\VoxFlow"),
            verifier,
            runner,
            new FixedDiskSpaceProbe(long.MaxValue));

        await using var prepared = await preparer.PrepareAsync(
            FixturePath("tone.wav"), "job-verify", temporary.Path, CancellationToken.None);
        await using var window = await preparer.CreateWindowAsync(
            prepared,
            new FileTranscriptionWindow(0, 0, 1_000),
            CancellationToken.None);

        Assert.Equal(1, verifier.Calls);
    }

    [Fact]
    public async Task Insufficient_space_stops_after_probe_and_preserves_the_source()
    {
        using var temporary = new TemporaryDirectory();
        var source = FixturePath("tone.wav");
        var runner = new FakeProcessRunner(ProbeJson(hasAudio: true));
        var preparer = CreatePreparer(runner, new FixedDiskSpaceProbe(0));

        var exception = await Assert.ThrowsAsync<FileMediaPreparationException>(async () =>
            await preparer.PrepareAsync(source, "job-1", temporary.Path, CancellationToken.None));

        Assert.Equal(FileTranscriptionErrorCode.InsufficientDiskSpace, exception.ErrorCode);
        Assert.Single(runner.Requests);
        Assert.True(File.Exists(source));
    }

    [Fact]
    public async Task Failed_conversion_removes_task_files_and_never_deletes_the_source()
    {
        using var temporary = new TemporaryDirectory();
        var source = FixturePath("tone.wav");
        var runner = new FakeProcessRunner(ProbeJson(hasAudio: true), createOutput: false);
        var preparer = CreatePreparer(runner);

        await Assert.ThrowsAsync<FileMediaPreparationException>(async () =>
            await preparer.PrepareAsync(source, "job-1", temporary.Path, CancellationToken.None));

        var workspaceRoot = Path.Combine(temporary.Path, "VoxFlow-FileTranscription");
        Assert.True(File.Exists(source));
        Assert.True(!Directory.Exists(workspaceRoot) || !Directory.EnumerateFileSystemEntries(workspaceRoot).Any());
    }

    [Fact]
    public void Startup_cleanup_removes_only_stale_task_directories()
    {
        using var temporary = new TemporaryDirectory();
        var workspaceRoot = Path.Combine(temporary.Path, "VoxFlow-FileTranscription");
        var stale = Directory.CreateDirectory(Path.Combine(workspaceRoot, "stale"));
        var current = Directory.CreateDirectory(Path.Combine(workspaceRoot, "current"));
        var unrelated = Directory.CreateDirectory(Path.Combine(temporary.Path, "source-files"));
        Directory.SetLastWriteTimeUtc(stale.FullName, DateTime.UtcNow.AddDays(-2));

        var removed = new FfmpegTemporaryFileCleaner().CleanupStaleDirectories(
            temporary.Path,
            DateTimeOffset.UtcNow.AddDays(-1));

        Assert.Equal(1, removed);
        Assert.False(Directory.Exists(stale.FullName));
        Assert.True(Directory.Exists(current.FullName));
        Assert.True(Directory.Exists(unrelated.FullName));
    }

    private static FfmpegFileMediaPreparer CreatePreparer(
        IFfmpegProcessRunner runner,
        IAvailableDiskSpaceProbe? diskSpace = null) => new(
        new FfmpegRuntimeLocator(@"C:\Program Files\VoxFlow"),
        new AlwaysValidRuntimeVerifier(),
        runner,
        diskSpace ?? new FixedDiskSpaceProbe(long.MaxValue));

    private static string FixturePath(string fileName) => Path.Combine(
        AppContext.BaseDirectory,
        "TestResources",
        "FileTranscriptionMedia",
        fileName);

    private static string ProbeJson(bool hasAudio, double durationSeconds = 0.2) => hasAudio
        ? "{\"streams\":[{\"index\":0,\"codec_type\":\"audio\"}]," +
          $"\"format\":{{\"duration\":\"{durationSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)}\",\"format_name\":\"fixture\"}}}}"
        : "{\"streams\":[],\"format\":{\"duration\":\"0.200000\",\"format_name\":\"mov\"}}";

    private static void AssertContainsPair(
        IReadOnlyList<string> arguments,
        string name,
        string value)
    {
        var index = arguments.IndexOf(name);
        Assert.InRange(index, 0, arguments.Count - 2);
        Assert.Equal(value, arguments[index + 1]);
    }

    private sealed class AlwaysValidRuntimeVerifier : IFfmpegRuntimeVerifier
    {
        public FfmpegRuntimeVerificationResult Verify(string runtimeDirectory) => new(true, null);
    }

    private sealed class CountingRuntimeVerifier : IFfmpegRuntimeVerifier
    {
        public int Calls { get; private set; }
        public FfmpegRuntimeVerificationResult Verify(string runtimeDirectory)
        {
            Calls++;
            return new FfmpegRuntimeVerificationResult(true, null);
        }
    }

    private sealed class FixedDiskSpaceProbe(long availableBytes) : IAvailableDiskSpaceProbe
    {
        public long GetAvailableBytes(string path) => availableBytes;
    }

    private sealed class FakeProcessRunner(string probeJson, bool createOutput = false)
        : IFfmpegProcessRunner
    {
        public List<FfmpegProcessRequest> Requests { get; } = [];

        public Task<FfmpegProcessResult> RunAsync(
            FfmpegProcessRequest request,
            CancellationToken cancellationToken)
        {
            Requests.Add(request);
            if (request.ExecutablePath.EndsWith("ffprobe.exe", StringComparison.OrdinalIgnoreCase))
            {
                return Task.FromResult(new FfmpegProcessResult(0, probeJson, string.Empty, null));
            }

            if (createOutput)
            {
                File.WriteAllBytes(request.Arguments[^1], [1, 2, 3]);
            }

            return Task.FromResult(new FfmpegProcessResult(0, string.Empty, string.Empty, null));
        }
    }
}

internal static class ReadOnlyListTestExtensions
{
    public static int IndexOf<T>(this IReadOnlyList<T> values, T value)
    {
        for (var index = 0; index < values.Count; index++)
        {
            if (EqualityComparer<T>.Default.Equals(values[index], value))
            {
                return index;
            }
        }

        return -1;
    }
}
