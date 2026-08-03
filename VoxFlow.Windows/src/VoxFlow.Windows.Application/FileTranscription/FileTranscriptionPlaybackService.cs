using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public enum FileTranscriptionPlaybackState
{
    Stopped,
    Playing,
    Paused,
    Failed,
}

public sealed record FileTranscriptionPlaybackResult(
    FileTranscriptionPlaybackState State);

public interface IFileTranscriptionPlaybackLease : IAsyncDisposable
{
    string AudioPath { get; }
}

public interface IFileTranscriptionPlaybackDecoder
{
    ValueTask<IFileTranscriptionPlaybackLease> DecodeAsync(
        FileTranscriptionJob job,
        CancellationToken cancellationToken);
}

public interface IFileTranscriptionPlaybackOutput : IDisposable
{
    void Start(string preparedAudioPath);
    void Pause();
    void Resume();
    void Stop();
}

/// <summary>
/// Keeps preview playback independent of persisted transcription state. Media
/// and device failures are represented only as UI feedback results.
/// </summary>
public sealed class FileTranscriptionPlaybackService : IAsyncDisposable
{
    private readonly IFileTranscriptionPlaybackDecoder decoder;
    private readonly IFileTranscriptionPlaybackOutput output;
    private readonly SemaphoreSlim gate = new(1, 1);
    private IFileTranscriptionPlaybackLease? currentLease;
    private string? currentJobId;
    private FileTranscriptionPlaybackState state = FileTranscriptionPlaybackState.Stopped;
    private int disposed;

    public FileTranscriptionPlaybackService(
        IFileTranscriptionPlaybackDecoder decoder,
        IFileTranscriptionPlaybackOutput output)
    {
        this.decoder = decoder ?? throw new ArgumentNullException(nameof(decoder));
        this.output = output ?? throw new ArgumentNullException(nameof(output));
    }

    public async ValueTask<FileTranscriptionPlaybackResult> ToggleAsync(
        FileTranscriptionJob job,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(job);
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (currentJobId == job.Id && state == FileTranscriptionPlaybackState.Playing)
            {
                try
                {
                    output.Pause();
                    state = FileTranscriptionPlaybackState.Paused;
                    return new FileTranscriptionPlaybackResult(state);
                }
                catch
                {
                    await StopAndReleaseAsync().ConfigureAwait(false);
                    return new FileTranscriptionPlaybackResult(
                        FileTranscriptionPlaybackState.Failed);
                }
            }

            if (currentJobId == job.Id && state == FileTranscriptionPlaybackState.Paused)
            {
                try
                {
                    output.Resume();
                    state = FileTranscriptionPlaybackState.Playing;
                    return new FileTranscriptionPlaybackResult(state);
                }
                catch
                {
                    await StopAndReleaseAsync().ConfigureAwait(false);
                    return new FileTranscriptionPlaybackResult(
                        FileTranscriptionPlaybackState.Failed);
                }
            }

            await StopAndReleaseAsync().ConfigureAwait(false);
            try
            {
                currentLease = await decoder.DecodeAsync(job, cancellationToken)
                    .ConfigureAwait(false);
                output.Start(currentLease.AudioPath);
                currentJobId = job.Id;
                state = FileTranscriptionPlaybackState.Playing;
                return new FileTranscriptionPlaybackResult(state);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                await StopAndReleaseAsync().ConfigureAwait(false);
                throw;
            }
            catch
            {
                await StopAndReleaseAsync().ConfigureAwait(false);
                return new FileTranscriptionPlaybackResult(
                    FileTranscriptionPlaybackState.Failed);
            }
        }
        finally
        {
            gate.Release();
        }
    }

    public async ValueTask StopAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await StopAndReleaseAsync().ConfigureAwait(false);
        }
        finally
        {
            gate.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            await StopAndReleaseAsync().ConfigureAwait(false);
            output.Dispose();
        }
        finally
        {
            gate.Release();
            gate.Dispose();
        }
    }

    private async ValueTask StopAndReleaseAsync()
    {
        if (currentLease is not null || currentJobId is not null)
        {
            try
            {
                output.Stop();
            }
            catch
            {
                // Device teardown cannot affect a transcription job.
            }
        }

        if (currentLease is not null)
        {
            try
            {
                await currentLease.DisposeAsync().ConfigureAwait(false);
            }
            catch
            {
                // Best-effort temporary media cleanup.
            }
        }

        currentLease = null;
        currentJobId = null;
        state = FileTranscriptionPlaybackState.Stopped;
    }
}
