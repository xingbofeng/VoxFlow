using System.Speech.Synthesis;

namespace VoxFlow.Windows.App.Selection;

/// <summary>
/// Uses only voices already installed by Windows. Each utterance owns a short
/// lived synthesizer, so cancellation and panel disposal cannot leave speech
/// running after the result panel is gone.
/// </summary>
public sealed class WindowsSystemSpeechBackend : ISelectionSpeechBackend
{
    public bool HasVoice
    {
        get
        {
            try
            {
                using var synthesizer = new SpeechSynthesizer();
                return synthesizer.GetInstalledVoices().Any(voice => voice.Enabled);
            }
            catch
            {
                return false;
            }
        }
    }

    public Task SpeakAsync(string text, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        cancellationToken.ThrowIfCancellationRequested();
        return Task.Run(async () =>
        {
            using var synthesizer = new SpeechSynthesizer();
            var completion = new TaskCompletionSource<SpeakCompletedEventArgs>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            EventHandler<SpeakCompletedEventArgs>? handler = null;
            handler = (_, eventArgs) => completion.TrySetResult(eventArgs);
            synthesizer.SpeakCompleted += handler;
            using var registration = cancellationToken.Register(
                static state => ((SpeechSynthesizer)state!).SpeakAsyncCancelAll(),
                synthesizer);
            try
            {
                synthesizer.SpeakAsync(text);
                var completed = await completion.Task.WaitAsync(cancellationToken)
                    .ConfigureAwait(false);
                if (completed.Cancelled || cancellationToken.IsCancellationRequested)
                {
                    throw new OperationCanceledException(cancellationToken);
                }
                if (completed.Error is not null)
                {
                    throw completed.Error;
                }
            }
            finally
            {
                synthesizer.SpeakCompleted -= handler;
            }
        }, CancellationToken.None);
    }
}
