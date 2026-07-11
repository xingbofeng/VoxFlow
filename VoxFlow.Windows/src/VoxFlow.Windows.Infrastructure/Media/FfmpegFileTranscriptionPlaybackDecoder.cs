using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Media;

public sealed class FfmpegFileTranscriptionPlaybackDecoder
    : IFileTranscriptionPlaybackDecoder
{
    private readonly FfmpegFileMediaPreparer preparer;
    private readonly string temporaryRoot;

    public FfmpegFileTranscriptionPlaybackDecoder(
        FfmpegFileMediaPreparer preparer,
        string temporaryRoot)
    {
        this.preparer = preparer ?? throw new ArgumentNullException(nameof(preparer));
        ArgumentException.ThrowIfNullOrWhiteSpace(temporaryRoot);
        this.temporaryRoot = Path.GetFullPath(temporaryRoot);
    }

    public async ValueTask<IFileTranscriptionPlaybackLease> DecodeAsync(
        FileTranscriptionJob job,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(job);
        var prepared = await preparer.PrepareAsync(
            job.SourcePath,
            $"preview-{job.Id}-{Guid.NewGuid():N}",
            temporaryRoot,
            cancellationToken).ConfigureAwait(false);
        return new PlaybackLease(prepared);
    }

    private sealed class PlaybackLease : IFileTranscriptionPlaybackLease
    {
        private readonly PreparedFileMedia prepared;

        public PlaybackLease(PreparedFileMedia prepared)
        {
            this.prepared = prepared;
        }

        public string AudioPath => prepared.PreparedAudioPath;

        public ValueTask DisposeAsync() => prepared.DisposeAsync();
    }
}
