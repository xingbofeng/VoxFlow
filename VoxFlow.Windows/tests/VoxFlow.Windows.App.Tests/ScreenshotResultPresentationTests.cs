using System.Runtime.CompilerServices;
using System.Threading;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Threading;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotResultPresentationTests
{
    [Fact]
    public void Completion_policy_matches_thumbnail_and_direct_ocr_routes()
    {
        Assert.Equal(
            new ScreenshotResultPresentationRoute(
                ScreenshotResultPresentationKind.Thumbnail,
                ScreenshotResultTab.Original),
            ScreenshotResultPresentationPolicy.For(ScreenshotCompletionKind.Complete));
        Assert.Equal(
            new ScreenshotResultPresentationRoute(
                ScreenshotResultPresentationKind.Expanded,
                ScreenshotResultTab.Ocr),
            ScreenshotResultPresentationPolicy.For(ScreenshotCompletionKind.TextRecognition));
        Assert.Equal(
            new ScreenshotResultPresentationRoute(
                ScreenshotResultPresentationKind.Expanded,
                ScreenshotResultTab.Translation),
            ScreenshotResultPresentationPolicy.For(ScreenshotCompletionKind.Translation));
        Assert.Equal(
            ScreenshotResultPresentationKind.None,
            ScreenshotResultPresentationPolicy.For(ScreenshotCompletionKind.Download).Kind);
    }

    [Fact]
    public void Result_window_has_mac_parity_dimensions_keyboard_focus_and_accessible_actions()
    {
        RunSta(() =>
        {
            using var viewModel = CreateViewModel();
            var window = new ScreenshotResultWindow();
            window.DataContext = viewModel;
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.DataBind);

            Assert.Equal(440, window.Width);
            Assert.Equal(560, window.Height);
            Assert.True(window.Topmost);
            Assert.False(window.ShowInTaskbar);
            Assert.Equal(
                "screenshot-result-window",
                AutomationProperties.GetAutomationId(window));
            Assert.Equal(
                "screenshot-result-tabs",
                AutomationProperties.GetAutomationId(window.ResultTabs));
            Assert.Equal(
                [
                    "screenshot-result-tab-original",
                    "screenshot-result-tab-ocr",
                    "screenshot-result-tab-refinement",
                    "screenshot-result-tab-translation",
                    "screenshot-result-tab-summary",
                ],
                new[]
                {
                    window.OriginalTab,
                    window.OcrTab,
                    window.RefinementTab,
                    window.TranslationTab,
                    window.SummaryTab,
                }.Select(AutomationProperties.GetAutomationId));
            Assert.Equal(L10n.Localize("ScreenshotClose"), AutomationProperties.GetName(window.CloseButton));
            Assert.Equal(Visibility.Collapsed, window.RefinementTab.Visibility);
            Assert.Equal(Visibility.Collapsed, window.RefineButton.Visibility);
            Assert.Equal(
                [window.OriginalTab, window.OcrTab, window.TranslationTab, window.SummaryTab],
                window.ResultTabs.Items
                    .OfType<TabItem>()
                    .Where(item => item.Visibility == Visibility.Visible));
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(window.RefineButton)));
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(window.TranslateButton)));
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(window.SpeakButton)));
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(window.CopyTextButton)));
            Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(window.CopyImageButton)));
            Assert.Equal(
                [
                    "screenshot-result-retry",
                    "screenshot-result-stop-speech",
                    "screenshot-result-refine",
                    "screenshot-result-translate",
                    "screenshot-result-speak",
                    "screenshot-result-copy-text",
                    "screenshot-result-copy-image",
                ],
                new[]
                {
                    window.RetryButton,
                    window.StopSpeechButton,
                    window.RefineButton,
                    window.TranslateButton,
                    window.SpeakButton,
                    window.CopyTextButton,
                    window.CopyImageButton,
                }.Select(AutomationProperties.GetAutomationId));
            window.Close();
        });
    }

    [Fact]
    public void Result_window_clamps_to_a_small_200_percent_work_area_and_keeps_actions_scrollable()
    {
        RunSta(() =>
        {
            using var viewModel = CreateViewModel();
            var window = new ScreenshotResultWindow { DataContext = viewModel };
            var workArea = new Rect(-960, 0, 960, 520);

            window.ApplyResponsiveBounds(workArea);
            window.Show();
            window.Dispatcher.Invoke(static () => { }, DispatcherPriority.Loaded);
            window.UpdateLayout();

            Assert.Equal(440, window.Width);
            Assert.Equal(464, window.Height);
            Assert.True(window.Left >= workArea.Left);
            Assert.True(window.Top >= workArea.Top);
            Assert.True(window.Left + window.Width <= workArea.Right);
            Assert.True(window.Top + window.Height <= workArea.Bottom);
            Assert.Equal(
                ScrollBarVisibility.Auto,
                window.WindowScrollViewer.VerticalScrollBarVisibility);
            Assert.Equal(5, window.ResultActionPanel.Children.Count);
            Assert.True(window.WindowScrollViewer.ScrollableHeight > 0);
            window.WindowScrollViewer.ScrollToEnd();
            window.UpdateLayout();
            Assert.Equal(
                window.WindowScrollViewer.ScrollableHeight,
                window.WindowScrollViewer.VerticalOffset,
                precision: 3);
            window.Close();
        });
    }

    [Fact]
    public void Translation_tab_previews_the_same_image_path_that_copy_uses_and_keeps_text()
    {
        RunSta(() =>
        {
            using var viewModel = CreateViewModel();
            var window = new ScreenshotResultWindow { DataContext = viewModel };

            var imageBinding = Assert.IsType<Binding>(BindingOperations.GetBinding(
                window.TranslationImagePreview,
                Image.SourceProperty));
            var textBinding = Assert.IsType<Binding>(BindingOperations.GetBinding(
                window.TranslationTextBox,
                TextBox.TextProperty));

            Assert.Equal(nameof(ScreenshotResultViewModel.CurrentImage), imageBinding.Path.Path);
            Assert.Equal(nameof(ScreenshotResultViewModel.TranslationDisplayText), textBinding.Path.Path);
            window.Close();
        });
    }

    [Fact]
    public void Thumbnail_has_exact_dimensions_and_scheduler_is_cancelled_on_interaction()
    {
        RunSta(() =>
        {
            var scheduler = new CapturingScheduler();
            var window = new ScreenshotResultThumbnailWindow(scheduler);
            var opened = false;
            window.ExpandRequested += (_, _) => opened = true;

            window.BeginAutoDismiss();
            Assert.Equal(TimeSpan.FromSeconds(3), scheduler.Delay);
            Assert.Equal(260, window.Width);
            Assert.Equal(150, window.Height);
            Assert.True(window.Topmost);
            Assert.False(window.ShowInTaskbar);
            Assert.Equal(
                "screenshot-result-thumbnail-window",
                AutomationProperties.GetAutomationId(window));
            Assert.Equal(
                "screenshot-result-thumbnail-open",
                AutomationProperties.GetAutomationId(window.OpenButton));

            window.OpenResult();
            Assert.True(opened);
            Assert.True(scheduler.Token.IsCancelled);
            window.Close();
        });
    }

    [Fact]
    public async Task Speech_toggle_stops_an_active_local_or_system_voice()
    {
        var backend = new BlockingSpeechBackend();
        await using var speech = new ScreenshotSpeechController(backend);

        var speaking = speech.ToggleAsync("read me");
        await backend.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Equal(ScreenshotSpeechState.Speaking, speech.State);
        await speech.ToggleAsync("read me");
        await speaking;

        Assert.Equal(ScreenshotSpeechState.Idle, speech.State);
        Assert.True(backend.CancellationObserved);
    }

    [Fact]
    public async Task Speech_backend_falls_back_to_windows_when_local_voice_is_unavailable()
    {
        var system = new CapturingSpeechBackend();
        var fallback = new FallbackScreenshotSpeechBackend(
            new UnavailableSpeechBackend(),
            system);

        await fallback.SpeakAsync("local text", CancellationToken.None);

        Assert.Equal("local text", system.Text);
    }

    [Fact]
    public void Presenter_builds_state_from_a_successful_completion_and_routes_ocr_directly()
    {
        var runId = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        var record = new ScreenshotRecord(
            "presented-shot",
            "Screenshots/presented/original.png",
            "Screenshots/presented/rendered.png",
            "Screenshots/presented/thumbnail.png",
            800,
            600,
            1234,
            "recognized text",
            now,
            translatedImagePath: "Screenshots/presented/translated.png",
            refinedText: "refined text",
            translatedText: "translated text",
            summaryText: "summary text");
        var completion = new ScreenshotCompletionResult(
            runId,
            record.Id,
            ScreenshotCompletionStatus.Succeeded,
            record,
            new ScreenshotOcrOutcome(
                runId,
                record.Id,
                record.OriginalImagePath,
                ScreenshotOcrOutcomeStatus.Succeeded,
                "recognized text",
                [new ScreenshotOcrLine("recognized text", 99, new ScreenshotPixelBounds(1, 2, 30, 10))]));
        var host = new CapturingPanelHost();
        using var presenter = new ScreenshotResultPresenter(
            new NoopTransformService(),
            new AssetResolver(),
            new NoopClipboard(),
            new UnavailableSpeechBackend(),
            panels: host);

        Assert.True(presenter.Present(ScreenshotCompletionKind.TextRecognition, completion));

        Assert.Equal(ScreenshotCompletionKind.TextRecognition, host.CompletionKind);
        Assert.NotNull(host.ViewModel);
        Assert.Equal(ScreenshotResultTab.Ocr, host.ViewModel.SelectedTab);
        Assert.Equal("recognized text", host.ViewModel.CurrentText);
        Assert.EndsWith("rendered.png", host.ViewModel.OriginalImagePath, StringComparison.Ordinal);
        Assert.EndsWith("thumbnail.png", host.ViewModel.ThumbnailImagePath, StringComparison.Ordinal);
        host.ViewModel.SelectTab(ScreenshotResultTab.Refinement);
        Assert.Equal("refined text", host.ViewModel.CurrentText);
        host.ViewModel.SelectTab(ScreenshotResultTab.Translation);
        Assert.Equal("translated text", host.ViewModel.CurrentText);
    }

    [Fact]
    public void Presenter_does_not_open_a_panel_for_failed_completion()
    {
        var host = new CapturingPanelHost();
        using var presenter = new ScreenshotResultPresenter(
            new NoopTransformService(),
            new AssetResolver(),
            new NoopClipboard(),
            new UnavailableSpeechBackend(),
            panels: host);
        var completion = new ScreenshotCompletionResult(
            Guid.NewGuid(),
            "failed-shot",
            ScreenshotCompletionStatus.AssetFailed);

        Assert.False(presenter.Present(ScreenshotCompletionKind.Complete, completion));
        Assert.Null(host.ViewModel);
    }

    [Theory]
    [InlineData(ScreenshotOcrOutcomeStatus.Empty, "ScreenshotResultOcrEmpty")]
    [InlineData(ScreenshotOcrOutcomeStatus.RuntimeUnavailable, "ScreenshotResultOcrRuntimeUnavailable")]
    [InlineData(ScreenshotOcrOutcomeStatus.InputUnavailable, "ScreenshotResultOcrInputUnavailable")]
    [InlineData(ScreenshotOcrOutcomeStatus.TimedOut, "ScreenshotResultOcrTimedOut")]
    [InlineData(ScreenshotOcrOutcomeStatus.Failed, "ScreenshotResultOcrFailed")]
    public void Presenter_preserves_terminal_ocr_status_for_distinct_result_feedback(
        ScreenshotOcrOutcomeStatus status,
        string expectedLocalizationKey)
    {
        var runId = Guid.NewGuid();
        var record = new ScreenshotRecord(
            "ocr-status-shot",
            "Screenshots/ocr-status/original.png",
            "Screenshots/ocr-status/rendered.png",
            "Screenshots/ocr-status/thumbnail.png",
            800,
            600,
            1234,
            string.Empty,
            DateTimeOffset.UtcNow);
        var completion = new ScreenshotCompletionResult(
            runId,
            record.Id,
            ScreenshotCompletionStatus.Succeeded,
            record,
            new ScreenshotOcrOutcome(
                runId,
                record.Id,
                record.OriginalImagePath,
                status));
        var host = new CapturingPanelHost();
        using var presenter = new ScreenshotResultPresenter(
            new NoopTransformService(),
            new AssetResolver(),
            new NoopClipboard(),
            new UnavailableSpeechBackend(),
            panels: host);

        Assert.True(presenter.Present(ScreenshotCompletionKind.TextRecognition, completion));

        Assert.NotNull(host.ViewModel);
        Assert.Equal(status, host.ViewModel.OcrStatus);
        Assert.Equal(L10n.Localize(expectedLocalizationKey), host.ViewModel.OcrDisplayText);
        Assert.Equal(host.ViewModel.OcrDisplayText, host.ViewModel.CurrentDisplayText);
    }

    private static void RunSta(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "STA UI test timed out.");
        if (failure is not null)
        {
            throw new Xunit.Sdk.XunitException(failure.ToString());
        }
    }

    private static ScreenshotResultViewModel CreateViewModel()
    {
        var state = new ScreenshotResultState(
            Guid.NewGuid(),
            "presentation-shot",
            "Screenshots/presentation/original.png",
            "recognized text",
            []);
        return new ScreenshotResultViewModel(
            state,
            new NoopTransformService(),
            new AssetResolver(),
            new NoopClipboard(),
            new ScreenshotSpeechController(new UnavailableSpeechBackend()));
    }

    private sealed class CapturingScheduler : IScreenshotResultAutoDismissScheduler
    {
        public TimeSpan Delay { get; private set; }
        public CapturingToken Token { get; } = new();

        public IScreenshotResultAutoDismissToken Schedule(TimeSpan delay, Action action)
        {
            Delay = delay;
            return Token;
        }
    }

    private sealed class CapturingToken : IScreenshotResultAutoDismissToken
    {
        public bool IsCancelled { get; private set; }
        public void Cancel() => IsCancelled = true;
        public void Dispose() => Cancel();
    }

    private sealed class BlockingSpeechBackend : IScreenshotSpeechBackend
    {
        public bool IsAvailable => true;
        public bool CancellationObserved { get; private set; }
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task SpeakAsync(string text, CancellationToken cancellationToken)
        {
            Started.TrySetResult();
            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                CancellationObserved = true;
                throw;
            }
        }
    }

    private sealed class NoopTransformService : IScreenshotTransformStreamingService
    {
        public async IAsyncEnumerable<ScreenshotTransformEvent> TransformAsync(
            ScreenshotTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            await Task.CompletedTask;
            yield break;
        }
    }

    private sealed class AssetResolver : IScreenshotResultAssetResolver
    {
        public string ResolveAbsolutePath(string relativePath) =>
            Path.Combine("C:\\VoxFlowData", relativePath.Replace('/', '\\'));
    }

    private sealed class NoopClipboard : IScreenshotResultClipboard
    {
        public bool TrySetText(string text) => true;
        public Task<bool> TrySetImageAsync(
            string absoluteImagePath,
            CancellationToken cancellationToken = default) => Task.FromResult(true);
    }

    private sealed class UnavailableSpeechBackend : IScreenshotSpeechBackend
    {
        public bool IsAvailable => false;
        public Task SpeakAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class CapturingSpeechBackend : IScreenshotSpeechBackend
    {
        public bool IsAvailable => true;
        public string? Text { get; private set; }

        public Task SpeakAsync(string text, CancellationToken cancellationToken)
        {
            Text = text;
            return Task.CompletedTask;
        }
    }

    private sealed class CapturingPanelHost : IScreenshotResultPanelHost
    {
        public ScreenshotResultViewModel? ViewModel { get; private set; }
        public ScreenshotCompletionKind? CompletionKind { get; private set; }

        public void Present(
            ScreenshotResultViewModel viewModel,
            ScreenshotCompletionKind completionKind)
        {
            CloseActive();
            ViewModel = viewModel;
            CompletionKind = completionKind;
        }

        public void CloseActive()
        {
            ViewModel?.Dispose();
            ViewModel = null;
            CompletionKind = null;
        }

        public void Dispose() => CloseActive();
    }
}
