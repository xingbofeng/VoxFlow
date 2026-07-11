using NAudio.CoreAudioApi;
using NAudio.Wave;
using VoxFlow.Windows.Application.FileTranscription;

namespace VoxFlow.Windows.Platform.Audio;

/// <summary>
/// Plays only the PCM WAV created by the bundled, verified FFmpeg runtime.
/// Source containers are never opened directly by the audio device layer.
/// </summary>
public sealed class WasapiFileTranscriptionPlaybackOutput
    : IFileTranscriptionPlaybackOutput
{
    private readonly object sync = new();
    private WaveFileReader? reader;
    private WasapiOut? player;
    private bool disposed;

    public void Start(string preparedAudioPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(preparedAudioPath);
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            StopCore();
            WaveFileReader? nextReader = null;
            WasapiOut? nextPlayer = null;
            try
            {
                nextReader = new WaveFileReader(preparedAudioPath);
                nextPlayer = new WasapiOut(
                    AudioClientShareMode.Shared,
                    useEventSync: false,
                    latency: 100);
                nextPlayer.Init(nextReader);
                nextPlayer.Play();
                reader = nextReader;
                player = nextPlayer;
            }
            catch
            {
                nextPlayer?.Dispose();
                nextReader?.Dispose();
                throw;
            }
        }
    }

    public void Pause()
    {
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            (player ?? throw new InvalidOperationException("Playback has not started."))
                .Pause();
        }
    }

    public void Resume()
    {
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            (player ?? throw new InvalidOperationException("Playback has not started."))
                .Play();
        }
    }

    public void Stop()
    {
        lock (sync)
        {
            if (disposed) return;
            StopCore();
        }
    }

    public void Dispose()
    {
        lock (sync)
        {
            if (disposed) return;
            StopCore();
            disposed = true;
        }
    }

    private void StopCore()
    {
        try
        {
            player?.Stop();
        }
        finally
        {
            player?.Dispose();
            reader?.Dispose();
            player = null;
            reader = null;
        }
    }
}
