using VoxFlow.Windows.App.Selection;

namespace VoxFlow.Windows.App.Tests;

public sealed class SelectionSpeechControllerTests
{
    [Fact]
    public async Task Starting_new_speech_cancels_previous_and_keeps_latest_active()
    {
        var backend = new BlockingSpeechBackend();
        await using var controller = new SelectionSpeechController(backend);

        var first = controller.SpeakAsync("first");
        await backend.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var second = controller.SpeakAsync("second");
        await backend.SecondStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal(SelectionSpeechState.Speaking, controller.State);
        backend.CompleteSecond();
        await second;
        await first;
        Assert.Equal(SelectionSpeechState.Idle, controller.State);
    }

    [Fact]
    public async Task Stop_and_close_cancel_playback_immediately()
    {
        var backend = new BlockingSpeechBackend();
        await using var controller = new SelectionSpeechController(backend);

        var running = controller.SpeakAsync("text");
        await backend.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        controller.Stop();
        await running;

        Assert.Equal(SelectionSpeechState.Idle, controller.State);
        Assert.True(backend.CancellationObserved);
    }

    [Fact]
    public async Task No_system_voice_reports_unavailable_without_throwing()
    {
        await using var controller = new SelectionSpeechController(new NoVoiceBackend());

        await controller.SpeakAsync("text");

        Assert.Equal(SelectionSpeechState.Unavailable, controller.State);
    }

    private sealed class NoVoiceBackend : ISelectionSpeechBackend
    {
        public bool HasVoice => false;
        public Task SpeakAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class BlockingSpeechBackend : ISelectionSpeechBackend
    {
        private int invocation;
        private readonly TaskCompletionSource completeSecond = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource SecondStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public bool HasVoice => true;
        public bool CancellationObserved { get; private set; }

        public async Task SpeakAsync(string text, CancellationToken cancellationToken)
        {
            var current = Interlocked.Increment(ref invocation);
            (current == 1 ? Started : SecondStarted).TrySetResult();
            try
            {
                if (current == 1)
                {
                    await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                }
                else
                {
                    await completeSecond.Task.WaitAsync(cancellationToken);
                }
            }
            catch (OperationCanceledException)
            {
                CancellationObserved = true;
                throw;
            }
        }

        public void CompleteSecond() => completeSecond.TrySetResult();
    }
}
