using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionPlaybackServiceTests
{
    [Fact]
    public async Task First_toggle_decodes_source_and_starts_wasapi_output()
    {
        var decoder = new FakeDecoder();
        var output = new FakeOutput();
        await using var service = new FileTranscriptionPlaybackService(decoder, output);

        var result = await service.ToggleAsync(Job(), CancellationToken.None);

        Assert.Equal(FileTranscriptionPlaybackState.Playing, result.State);
        Assert.Equal(@"C:\Temp\prepared.wav", output.StartedPath);
        Assert.Equal(1, decoder.DecodeCalls);
    }

    [Fact]
    public async Task Repeated_toggles_pause_and_resume_without_decoding_again()
    {
        var decoder = new FakeDecoder();
        var output = new FakeOutput();
        await using var service = new FileTranscriptionPlaybackService(decoder, output);
        var job = Job();

        await service.ToggleAsync(job, CancellationToken.None);
        var paused = await service.ToggleAsync(job, CancellationToken.None);
        var resumed = await service.ToggleAsync(job, CancellationToken.None);

        Assert.Equal(FileTranscriptionPlaybackState.Paused, paused.State);
        Assert.Equal(FileTranscriptionPlaybackState.Playing, resumed.State);
        Assert.Equal(1, output.PauseCalls);
        Assert.Equal(1, output.ResumeCalls);
        Assert.Equal(1, decoder.DecodeCalls);
    }

    [Fact]
    public async Task Decode_or_output_failure_is_feedback_only_and_never_mutates_the_job()
    {
        var original = Job();
        var decoder = new FakeDecoder { Failure = new IOException("decode failed") };
        await using var service = new FileTranscriptionPlaybackService(decoder, new FakeOutput());

        var result = await service.ToggleAsync(original, CancellationToken.None);

        Assert.Equal(FileTranscriptionPlaybackState.Failed, result.State);
        Assert.Equal(FileTranscriptionJobStatus.Completed, original.Status);
        Assert.Equal("final text", original.FinalText);
        Assert.Null(original.ErrorCode);
    }

    [Fact]
    public async Task Selecting_another_job_stops_and_releases_previous_decode()
    {
        var decoder = new FakeDecoder();
        var output = new FakeOutput();
        await using var service = new FileTranscriptionPlaybackService(decoder, output);

        await service.ToggleAsync(Job("job-1"), CancellationToken.None);
        var firstLease = decoder.Leases[0];
        await service.ToggleAsync(Job("job-2"), CancellationToken.None);

        Assert.Equal(1, output.StopCalls);
        Assert.True(firstLease.Disposed);
        Assert.Equal(2, decoder.DecodeCalls);
    }

    [Fact]
    public async Task Explicit_stop_releases_prepared_media_for_job_deletion()
    {
        var decoder = new FakeDecoder();
        var output = new FakeOutput();
        await using var service = new FileTranscriptionPlaybackService(decoder, output);
        await service.ToggleAsync(Job(), CancellationToken.None);

        await service.StopAsync(CancellationToken.None);

        Assert.Equal(1, output.StopCalls);
        Assert.True(decoder.Leases[0].Disposed);
    }

    private static FileTranscriptionJob Job(string id = "job-1") => new(
        id,
        $@"C:\Media\{id}.mp4",
        $"{id}.mp4",
        AsrProviderId.Qwen,
        RecognitionLanguage.Automatic,
        1,
        status: FileTranscriptionJobStatus.Completed,
        finalText: "final text");

    private sealed class FakeDecoder : IFileTranscriptionPlaybackDecoder
    {
        public Exception? Failure { get; init; }
        public int DecodeCalls { get; private set; }
        public List<FakeLease> Leases { get; } = [];

        public ValueTask<IFileTranscriptionPlaybackLease> DecodeAsync(
            FileTranscriptionJob job,
            CancellationToken cancellationToken)
        {
            DecodeCalls++;
            if (Failure is not null) throw Failure;
            var lease = new FakeLease();
            Leases.Add(lease);
            return ValueTask.FromResult<IFileTranscriptionPlaybackLease>(lease);
        }
    }

    private sealed class FakeLease : IFileTranscriptionPlaybackLease
    {
        public string AudioPath => @"C:\Temp\prepared.wav";
        public bool Disposed { get; private set; }
        public ValueTask DisposeAsync()
        {
            Disposed = true;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeOutput : IFileTranscriptionPlaybackOutput
    {
        public string? StartedPath { get; private set; }
        public int PauseCalls { get; private set; }
        public int ResumeCalls { get; private set; }
        public int StopCalls { get; private set; }
        public void Start(string preparedAudioPath) => StartedPath = preparedAudioPath;
        public void Pause() => PauseCalls++;
        public void Resume() => ResumeCalls++;
        public void Stop() => StopCalls++;
        public void Dispose() { }
    }
}
