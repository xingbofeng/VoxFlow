using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Media;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class FfmpegRealMediaFixtureTests
{
    private static readonly Lazy<FfmpegFileMediaPreparer> SharedPreparer = new(
        CreateVerifiedPreparer,
        LazyThreadSafetyMode.ExecutionAndPublication);

    [Theory]
    [InlineData("mp3")]
    [InlineData("wav")]
    [InlineData("m4a")]
    [InlineData("aac")]
    [InlineData("mp4")]
    [InlineData("mov")]
    public async Task Locked_ffprobe_reads_duration_and_first_audio_track_from_real_fixture(
        string extension)
    {
        var result = await CreatePreparer().ProbeAsync(
            FixturePath($"tone.{extension}"),
            CancellationToken.None);

        Assert.True(result.HasAudioTrack);
        Assert.InRange(result.DurationMs, 150, 400);
        Assert.False(string.IsNullOrWhiteSpace(result.FormatName));
    }

    [Fact]
    public async Task Locked_ffprobe_rejects_a_real_video_without_an_audio_track()
    {
        var exception = await Assert.ThrowsAsync<FileMediaPreparationException>(async () =>
            await CreatePreparer().ProbeAsync(
                FixturePath("no-audio.mp4"),
                CancellationToken.None));

        Assert.Equal(FileTranscriptionErrorCode.NoAudioTrack, exception.ErrorCode);
    }

    [Theory]
    [InlineData("mp3")]
    [InlineData("wav")]
    [InlineData("m4a")]
    [InlineData("aac")]
    [InlineData("mp4")]
    [InlineData("mov")]
    public async Task Locked_ffmpeg_normalizes_every_supported_container_to_pcm16_mono_16khz(
        string extension)
    {
        using var temporary = new TemporaryDirectory();
        var source = FixturePath($"tone.{extension}");

        await using var prepared = await CreatePreparer().PrepareAsync(
            source,
            $"fixture-{extension}",
            temporary.Path,
            CancellationToken.None);

        var format = ReadWaveFormat(prepared.PreparedAudioPath);
        Assert.Equal((ushort)1, format.FormatTag);
        Assert.Equal((ushort)1, format.Channels);
        Assert.Equal(16_000, format.SampleRate);
        Assert.Equal((ushort)16, format.BitsPerSample);
        Assert.True(File.Exists(source));
    }

    private static FfmpegFileMediaPreparer CreatePreparer() => SharedPreparer.Value;

    private static FfmpegFileMediaPreparer CreateVerifiedPreparer()
    {
        var installationRoot = Environment.GetEnvironmentVariable(
            "VOXFLOW_TEST_FFMPEG_INSTALL_ROOT");
        installationRoot ??= FindRepositoryWindowsRoot();
        Assert.False(
            string.IsNullOrWhiteSpace(installationRoot),
            "Stage the locked runtime and set VOXFLOW_TEST_FFMPEG_INSTALL_ROOT.");
        var locator = new FfmpegRuntimeLocator(installationRoot!);
        var verification = new FfmpegRuntimeVerifier().Verify(locator.RuntimeDirectory);
        Assert.True(
            verification.IsValid,
            $"Locked FFmpeg runtime verification failed: {verification.Error}/{verification.FileName}.");
        return new FfmpegFileMediaPreparer(
            locator,
            new FfmpegRuntimeVerifier(),
            new FfmpegProcessRunner());
    }

    private static string? FindRepositoryWindowsRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(
                    directory.FullName,
                    "runtime",
                    "ffmpeg",
                    FfmpegRuntimeVerifier.ManifestFileName)))
            {
                return directory.FullName;
            }
        }
        return null;
    }

    private static string FixturePath(string fileName) => Path.Combine(
        AppContext.BaseDirectory,
        "TestResources",
        "FileTranscriptionMedia",
        fileName);

    private static WaveFormatRecord ReadWaveFormat(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new BinaryReader(stream);
        Assert.Equal("RIFF", new string(reader.ReadChars(4)));
        _ = reader.ReadUInt32();
        Assert.Equal("WAVE", new string(reader.ReadChars(4)));
        while (stream.Position + 8 <= stream.Length)
        {
            var chunkId = new string(reader.ReadChars(4));
            var chunkSize = reader.ReadUInt32();
            if (chunkId == "fmt ")
            {
                var result = new WaveFormatRecord(
                    reader.ReadUInt16(),
                    reader.ReadUInt16(),
                    reader.ReadInt32(),
                    SkipToBitsPerSample(reader),
                    chunkSize);
                return result;
            }
            stream.Position += chunkSize + (chunkSize % 2);
        }
        throw new InvalidDataException("The normalized WAV has no fmt chunk.");
    }

    private static ushort SkipToBitsPerSample(BinaryReader reader)
    {
        _ = reader.ReadInt32();
        _ = reader.ReadUInt16();
        return reader.ReadUInt16();
    }

    private sealed record WaveFormatRecord(
        ushort FormatTag,
        ushort Channels,
        int SampleRate,
        ushort BitsPerSample,
        uint ChunkSize);
}
