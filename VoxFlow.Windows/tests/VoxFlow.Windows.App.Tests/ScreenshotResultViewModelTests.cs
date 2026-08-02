using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotResultViewModelTests
{
    [Fact]
    public async Task Refinement_has_a_visible_state_result_and_copy_flow()
    {
        var state = CreateState("rough source");
        var service = new ScriptedTransformService(request =>
        [
            new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation),
            new ScreenshotTransformPartial(request.RunId, request.ScreenshotId, request.Operation, "polished"),
            new ScreenshotTransformCompleted(
                request.RunId,
                request.ScreenshotId,
                request.Operation,
                "polished source",
                false),
        ]);
        var clipboard = new CapturingClipboard();
        using var viewModel = CreateViewModel(state, service, clipboard);

        await viewModel.StartRefinementAsync();

        Assert.Equal(ScreenshotResultTab.Refinement, viewModel.SelectedTab);
        Assert.Equal(ScreenshotTransformOperation.Refinement, Assert.Single(service.Requests).Operation);
        Assert.Equal("rough source", service.Requests[0].SourceText);
        Assert.Equal("polished source", viewModel.RefinementDisplayText);
        Assert.Equal("polished source", viewModel.CurrentText);
        Assert.Equal(ScreenshotResultActionState.Succeeded, viewModel.RefinementActionState);
        Assert.Equal(
            L10n.Localize("ScreenshotResultRefinementComplete"),
            viewModel.RefinementFeedback);
        Assert.True(viewModel.CopyCurrentText());
        Assert.Equal("polished source", clipboard.Text);
    }

    [Fact]
    public async Task Translation_streams_into_its_own_tab_without_changing_ocr()
    {
        var state = CreateState("source text");
        var service = new ScriptedTransformService(request =>
        [
            new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation),
            new ScreenshotTransformPartial(request.RunId, request.ScreenshotId, request.Operation, "译"),
            new ScreenshotTransformCompleted(request.RunId, request.ScreenshotId, request.Operation, "译文", false),
        ]);
        using var viewModel = CreateViewModel(state, service);

        await viewModel.StartTranslationAsync();

        Assert.Equal(ScreenshotResultTab.Translation, viewModel.SelectedTab);
        Assert.Equal("译文", viewModel.CurrentText);
        Assert.Equal("source text", state.OriginalOcrText);
        Assert.Equal(ScreenshotTransformStatus.Completed, state.GetStatus(ScreenshotTransformOperation.Translation));
        Assert.Equal(ScreenshotResultActionState.Succeeded, viewModel.TranslationActionState);
    }

    [Fact]
    public async Task Selecting_summary_uses_translation_and_does_not_repeat_a_completed_request()
    {
        var state = CreateState("source text");
        ApplyCompleted(state, ScreenshotTransformOperation.Translation, "translated source");
        var service = new ScriptedTransformService(request =>
        [
            new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation),
            new ScreenshotTransformCompleted(request.RunId, request.ScreenshotId, request.Operation, "- one", false),
        ]);
        using var viewModel = CreateViewModel(state, service);

        viewModel.SelectTab(ScreenshotResultTab.Summary);
        await viewModel.ActivateSelectedTabAsync();
        await viewModel.ActivateSelectedTabAsync();

        Assert.Single(service.Requests);
        Assert.Equal(ScreenshotTransformOperation.Summary, service.Requests[0].Operation);
        Assert.Equal("translated source", service.Requests[0].SourceText);
        Assert.Equal("- one", viewModel.CurrentText);
    }

    [Fact]
    public async Task Failed_retry_preserves_the_previous_translation_and_other_tabs()
    {
        var state = CreateState("original OCR");
        ApplyCompleted(state, ScreenshotTransformOperation.Translation, "old translation");
        ApplyCompleted(state, ScreenshotTransformOperation.Summary, "old summary");
        var service = new ScriptedTransformService(request =>
        [
            new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation),
            new ScreenshotTransformFailed(
                request.RunId,
                request.ScreenshotId,
                request.Operation,
                "screenshot.transform.request_failed",
                string.Empty),
        ]);
        using var viewModel = CreateViewModel(state, service);

        await viewModel.StartTranslationAsync();

        Assert.Equal("old translation", viewModel.CurrentText);
        Assert.Equal("old summary", state.SummaryText);
        Assert.Equal(ScreenshotResultActionState.Failed, viewModel.TranslationActionState);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.TranslationFeedback));
    }

    [Fact]
    public async Task Summary_failure_is_retryable_without_replacing_ocr_or_translation()
    {
        var state = CreateState("original OCR");
        ApplyCompleted(state, ScreenshotTransformOperation.Translation, "translation");
        var attempt = 0;
        var service = new ScriptedTransformService(request =>
        {
            attempt++;
            return attempt == 1
                ?
                [
                    new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation),
                    new ScreenshotTransformFailed(
                        request.RunId,
                        request.ScreenshotId,
                        request.Operation,
                        "screenshot.transform.request_failed",
                        string.Empty),
                ]
                :
                [
                    new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation),
                    new ScreenshotTransformCompleted(
                        request.RunId,
                        request.ScreenshotId,
                        request.Operation,
                        "summary",
                        false),
                ];
        });
        using var viewModel = CreateViewModel(state, service);
        viewModel.SelectTab(ScreenshotResultTab.Summary);

        await viewModel.ActivateSelectedTabAsync();
        Assert.True(viewModel.CanRetryCurrentTransform);
        await viewModel.RetryCurrentTransformAsync();

        Assert.Equal("summary", viewModel.CurrentText);
        Assert.Equal("original OCR", state.OriginalOcrText);
        Assert.Equal("translation", state.TranslatedText);
    }

    [Fact]
    public async Task Close_rejects_late_transform_callbacks_even_when_service_ignores_cancellation()
    {
        var state = CreateState("source");
        var service = new LateTransformService();
        using var viewModel = CreateViewModel(state, service);

        var running = viewModel.StartTranslationAsync();
        await service.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        viewModel.Close();
        service.PublishLateResult();
        await running;

        Assert.Null(state.TranslatedText);
        Assert.NotEqual(ScreenshotTransformStatus.Completed, state.GetStatus(ScreenshotTransformOperation.Translation));
    }

    [Fact]
    public async Task Image_copy_is_async_disables_reentry_and_publishes_feedback_after_completion()
    {
        var clipboard = new BlockingImageClipboard();
        using var viewModel = CreateViewModel(
            CreateState("OCR text"),
            new ScriptedTransformService(_ => []),
            clipboard);

        var copying = viewModel.CopyCurrentImageAsync();
        await clipboard.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.False(copying.IsCompleted);
        Assert.Equal(ScreenshotResultActionState.Running, viewModel.ImageCopyActionState);
        Assert.False(viewModel.CanCopyImage);
        Assert.False(await viewModel.CopyCurrentImageAsync());

        clipboard.Release.TrySetResult(true);
        Assert.True(await copying.WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.Equal(ScreenshotResultActionState.Succeeded, viewModel.ImageCopyActionState);
        Assert.True(viewModel.CanCopyImage);
        Assert.Equal(
            L10n.Localize("ScreenshotResultCopiedImage"),
            viewModel.ImageCopyFeedback);
    }

    [Fact]
    public async Task Footer_actions_target_current_content_and_keep_failures_independent()
    {
        var state = CreateState("OCR text");
        ApplyCompleted(state, ScreenshotTransformOperation.Translation, "translated text");
        var clipboard = new CapturingClipboard { ImageSucceeds = false, TextSucceeds = true };
        var speech = new ScreenshotSpeechController(new CompletingSpeechBackend());
        using var viewModel = CreateViewModel(
            state,
            new ScriptedTransformService(_ => []),
            clipboard,
            speech,
            translatedImagePath: "Screenshots/shot/translated.png");
        viewModel.SelectTab(ScreenshotResultTab.Translation);

        Assert.True(viewModel.CopyCurrentText());
        Assert.Equal("translated text", clipboard.Text);
        Assert.False(await viewModel.CopyCurrentImageAsync());
        Assert.EndsWith("translated.png", clipboard.ImagePath, StringComparison.Ordinal);
        Assert.Equal(viewModel.CurrentImagePath, clipboard.ImagePath);
        Assert.Equal(ScreenshotResultActionState.Succeeded, viewModel.TextCopyActionState);
        Assert.Equal(ScreenshotResultActionState.Failed, viewModel.ImageCopyActionState);

        await viewModel.ToggleSpeechAsync();
        Assert.Equal("translated text", speech.LastRequestedText);
        Assert.Equal("translated text", viewModel.CurrentText);
    }

    private static ScreenshotResultViewModel CreateViewModel(
        ScreenshotResultState state,
        IScreenshotTransformStreamingService service,
        IScreenshotResultClipboard? clipboard = null,
        ScreenshotSpeechController? speech = null,
        string? translatedImagePath = null) => new(
            state,
            service,
            new PrefixAssetResolver(),
            clipboard ?? new CapturingClipboard(),
            speech ?? new ScreenshotSpeechController(new CompletingSpeechBackend()),
            translatedImagePath: translatedImagePath);

    private static ScreenshotResultState CreateState(string ocrText) => new(
        Guid.NewGuid(),
        "shot-1",
        "Screenshots/shot/original.png",
        ocrText,
        []);

    private static void ApplyCompleted(
        ScreenshotResultState state,
        ScreenshotTransformOperation operation,
        string text)
    {
        Assert.True(state.Apply(new ScreenshotTransformStarted(state.RunId, state.ScreenshotId, operation)));
        Assert.True(state.Apply(new ScreenshotTransformCompleted(
            state.RunId,
            state.ScreenshotId,
            operation,
            text,
            false)));
    }

    private sealed class PrefixAssetResolver : IScreenshotResultAssetResolver
    {
        public string ResolveAbsolutePath(string relativePath) =>
            Path.Combine("C:\\VoxFlowData", relativePath.Replace('/', '\\'));
    }

    private sealed class CapturingClipboard : IScreenshotResultClipboard
    {
        public bool TextSucceeds { get; init; } = true;
        public bool ImageSucceeds { get; init; } = true;
        public string? Text { get; private set; }
        public string? ImagePath { get; private set; }

        public bool TrySetText(string text)
        {
            Text = text;
            return TextSucceeds;
        }

        public Task<bool> TrySetImageAsync(
            string absoluteImagePath,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ImagePath = absoluteImagePath;
            return Task.FromResult(ImageSucceeds);
        }
    }

    private sealed class BlockingImageClipboard : IScreenshotResultClipboard
    {
        public TaskCompletionSource Started { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<bool> Release { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public bool TrySetText(string text) => true;

        public async Task<bool> TrySetImageAsync(
            string absoluteImagePath,
            CancellationToken cancellationToken = default)
        {
            Started.TrySetResult();
            return await Release.Task.WaitAsync(cancellationToken);
        }
    }

    private sealed class CompletingSpeechBackend : IScreenshotSpeechBackend
    {
        public bool IsAvailable => true;
        public Task SpeakAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class ScriptedTransformService(
        Func<ScreenshotTransformRequest, IReadOnlyList<ScreenshotTransformEvent>> script)
        : IScreenshotTransformStreamingService
    {
        public List<ScreenshotTransformRequest> Requests { get; } = [];

        public async IAsyncEnumerable<ScreenshotTransformEvent> TransformAsync(
            ScreenshotTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            Requests.Add(request);
            foreach (var @event in script(request))
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return @event;
            }
            await Task.CompletedTask;
        }
    }

    private sealed class LateTransformService : IScreenshotTransformStreamingService
    {
        private readonly TaskCompletionSource publish = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public void PublishLateResult() => publish.TrySetResult();

        public async IAsyncEnumerable<ScreenshotTransformEvent> TransformAsync(
            ScreenshotTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            yield return new ScreenshotTransformStarted(request.RunId, request.ScreenshotId, request.Operation);
            Started.TrySetResult();
            await publish.Task;
            yield return new ScreenshotTransformCompleted(
                request.RunId,
                request.ScreenshotId,
                request.Operation,
                "late",
                false);
        }
    }
}
