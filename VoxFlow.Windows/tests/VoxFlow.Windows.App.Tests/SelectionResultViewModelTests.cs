using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.Application.SelectionTransform;

namespace VoxFlow.Windows.App.Tests;

public sealed class SelectionResultViewModelTests
{
    [Fact]
    public void Footer_copy_targets_the_current_tab_and_rejects_empty_result()
    {
        var clipboard = new CapturingClipboard();
        var viewModel = new SelectionResultViewModel(
            "source text",
            SelectionTransformOperation.Translation,
            new BlockingService(),
            new CapturingHistory(),
            clipboard);

        viewModel.SelectTab(SelectionResultTab.Source);
        Assert.True(viewModel.CopyDisplayedText());
        Assert.Equal("source text", clipboard.Text);
        viewModel.SelectTab(SelectionResultTab.Result);
        Assert.False(viewModel.CopyDisplayedText());
        Assert.Equal("source text", clipboard.Text);
    }
    [Fact]
    public async Task Switching_to_source_cancels_and_records_one_nonempty_partial()
    {
        var service = new BlockingService();
        var history = new CapturingHistory();
        var viewModel = new SelectionResultViewModel("source", SelectionTransformOperation.Translation, service, history);

        var running = viewModel.StartAsync();
        await service.PartialPublished.Task.WaitAsync(TimeSpan.FromSeconds(2));
        viewModel.SelectTab(SelectionResultTab.Source);
        await running;

        Assert.False(viewModel.IsTransforming);
        Assert.Equal("partial", viewModel.ResultText);
        Assert.Equal(SelectionTransformPresentationState.PartiallyCompleted, viewModel.State);
        Assert.Single(history.Records);
        Assert.Equal("partial", history.Records[0].Text);
    }

    [Fact]
    public async Task Close_before_first_partial_does_not_create_history()
    {
        var service = new BlockingService(publishPartial: false);
        var history = new CapturingHistory();
        var viewModel = new SelectionResultViewModel("source", SelectionTransformOperation.Summary, service, history);

        var running = viewModel.StartAsync();
        await service.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        viewModel.Close();
        await running;

        Assert.Empty(history.Records);
        Assert.Equal(SelectionTransformPresentationState.Cancelled, viewModel.State);
    }

    [Fact]
    public async Task Switching_back_to_result_after_cancel_does_not_restart_network()
    {
        var service = new BlockingService();
        var viewModel = new SelectionResultViewModel("source", SelectionTransformOperation.Translation, service, new CapturingHistory());

        var running = viewModel.StartAsync();
        await service.PartialPublished.Task.WaitAsync(TimeSpan.FromSeconds(2));
        viewModel.SelectTab(SelectionResultTab.Source);
        await running;
        viewModel.SelectTab(SelectionResultTab.Result);

        Assert.Equal(1, service.CallCount);
        Assert.Equal("partial", viewModel.DisplayedText);
    }

    [Fact]
    public async Task Replace_and_insert_target_the_displayed_tab_and_surface_copy_fallback()
    {
        var writer = new CapturingWriter(replaceResult: true, insertResult: false);
        var viewModel = new SelectionResultViewModel(
            "source",
            SelectionTransformOperation.Translation,
            new BlockingService(),
            writer: writer);

        viewModel.SelectTab(SelectionResultTab.Source);
        Assert.True(viewModel.CanWriteBack);
        Assert.True(await viewModel.ReplaceDisplayedTextAsync());
        Assert.Equal("source", writer.Replaced);
        Assert.False(await viewModel.InsertAfterDisplayedTextAsync());
        Assert.Equal("source", writer.Inserted);
        Assert.Equal("copied_fallback", viewModel.StatusMessage);
    }

    [Fact]
    public async Task Write_actions_target_the_completed_result_tab()
    {
        var writer = new CapturingWriter(replaceResult: true, insertResult: true);
        var viewModel = new SelectionResultViewModel(
            "source", SelectionTransformOperation.Summary, new CompletedService(), writer: writer);

        await viewModel.StartAsync();

        Assert.Equal("translated", viewModel.DisplayedText);
        Assert.True(await viewModel.ReplaceDisplayedTextAsync());
        Assert.Equal("translated", writer.Replaced);
    }

    [Fact]
    public async Task Terminal_state_notifies_status_after_the_state_change()
    {
        var viewModel = new SelectionResultViewModel(
            "source",
            SelectionTransformOperation.Translation,
            new CompletedService());
        var observed = new List<(SelectionTransformPresentationState State, string Text)>();
        viewModel.PropertyChanged += (_, change) =>
        {
            if (change.PropertyName == nameof(SelectionResultViewModel.StatusText))
            {
                observed.Add((viewModel.State, viewModel.StatusText));
            }
        };

        await viewModel.StartAsync();

        Assert.Contains(observed, value =>
            value.State == SelectionTransformPresentationState.Completed
            && !string.IsNullOrWhiteSpace(value.Text));
    }

    [Fact]
    public async Task Unexpected_transform_failure_becomes_visible_terminal_feedback()
    {
        var viewModel = new SelectionResultViewModel(
            "source",
            SelectionTransformOperation.Summary,
            new ThrowingService());

        await viewModel.StartAsync();

        Assert.False(viewModel.IsTransforming);
        Assert.Equal(SelectionTransformPresentationState.Failed, viewModel.State);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.StatusText));
    }

    [Fact]
    public void Clipboard_exception_is_converted_to_visible_failure_feedback()
    {
        var viewModel = new SelectionResultViewModel(
            "source",
            SelectionTransformOperation.Translation,
            new BlockingService(),
            clipboard: new ThrowingClipboard());
        viewModel.SelectTab(SelectionResultTab.Source);

        Assert.False(viewModel.CopyDisplayedText());
        Assert.Equal("copy_failed", viewModel.StatusMessage);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.StatusText));
    }

    [Fact]
    public void Speech_state_changes_are_visible_and_switch_the_button_to_stop()
    {
        var viewModel = new SelectionResultViewModel(
            "source",
            SelectionTransformOperation.Translation,
            new BlockingService());
        viewModel.SelectTab(SelectionResultTab.Source);

        viewModel.ReportSpeechState(SelectionSpeechState.Speaking);

        Assert.True(viewModel.IsSpeaking);
        Assert.NotEqual(VoxFlow.Windows.App.Localization.L10n.SelectionResultSpeak, viewModel.SpeakButtonLabel);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.StatusText));

        viewModel.ReportSpeechState(SelectionSpeechState.Idle, userStopped: true);

        Assert.False(viewModel.IsSpeaking);
        Assert.Equal(VoxFlow.Windows.App.Localization.L10n.SelectionResultSpeak, viewModel.SpeakButtonLabel);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.StatusText));
    }

    private sealed class BlockingService(bool publishPartial = true) : ISelectionTransformStreamingService
    {
        public int CallCount { get; private set; }
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource PartialPublished { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
            SelectionTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            CallCount++;
            Started.TrySetResult();
            yield return new SelectionTransformStarted(request.Generation);
            if (publishPartial)
            {
                yield return new SelectionTransformPartial(request.Generation, "partial");
                PartialPublished.TrySetResult();
            }
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
        }
    }

    private sealed class CapturingHistory : ISelectionTransformHistoryRecorder
    {
        public List<SelectionTransformHistoryRecord> Records { get; } = [];

        public void Record(SelectionTransformHistoryRecord record) => Records.Add(record);
    }

    private sealed class CapturingClipboard : ISelectionResultClipboard
    {
        public string? Text { get; private set; }

        public bool TrySetText(string text)
        {
            Text = text;
            return true;
        }
    }

    private sealed class ThrowingClipboard : ISelectionResultClipboard
    {
        public bool TrySetText(string text) =>
            throw new InvalidOperationException("clipboard test failure");
    }

    private sealed class CapturingWriter(bool replaceResult, bool insertResult) : ISelectionResultWriter
    {
        public string? Replaced { get; private set; }
        public string? Inserted { get; private set; }
        public Task<bool> ReplaceAsync(string text, CancellationToken cancellationToken)
        {
            Replaced = text;
            return Task.FromResult(replaceResult);
        }
        public Task<bool> InsertAfterAsync(string text, CancellationToken cancellationToken)
        {
            Inserted = text;
            return Task.FromResult(insertResult);
        }
    }

    private sealed class CompletedService : ISelectionTransformStreamingService
    {
        public async IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
            SelectionTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            yield return new SelectionTransformStarted(request.Generation);
            yield return new SelectionTransformPartial(request.Generation, "translated");
            yield return new SelectionTransformCompleted(request.Generation, "translated");
            await Task.CompletedTask;
        }
    }

    private sealed class ThrowingService : ISelectionTransformStreamingService
    {
        public async IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
            SelectionTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            yield return new SelectionTransformStarted(request.Generation);
            await Task.Yield();
            throw new InvalidOperationException("provider test failure");
        }
    }
}
