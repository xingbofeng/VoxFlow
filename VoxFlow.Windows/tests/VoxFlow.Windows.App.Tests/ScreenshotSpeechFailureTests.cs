using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotSpeechFailureTests
{
    [Fact]
    public async Task Unexpected_speech_exception_becomes_safe_localized_feedback()
    {
        var state = new ScreenshotResultState(
            Guid.NewGuid(),
            "shot-1",
            "Screenshots/shot/original.png",
            "recognized text",
            []);
        var speech = new ScreenshotSpeechController(new ThrowingSpeechBackend(
            new InvalidOperationException(@"C:\Users\Alice\private\speech-engine.log")));
        using var viewModel = new ScreenshotResultViewModel(
            state,
            new EmptyTransformService(),
            new AssetResolver(),
            new Clipboard(),
            speech,
            initialTab: ScreenshotResultTab.Ocr);

        await viewModel.ToggleSpeechAsync();

        Assert.Equal(ScreenshotResultActionState.Failed, viewModel.SpeechActionState);
        Assert.Equal(L10n.Localize("ScreenshotResultSpeechFailed"), viewModel.SpeechFeedback);
        Assert.Equal(viewModel.SpeechFeedback, viewModel.CurrentFeedback);
        Assert.DoesNotContain("Alice", viewModel.CurrentFeedback, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("speech-engine", viewModel.CurrentFeedback, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Speech_cancellation_is_not_converted_to_failed_feedback()
    {
        var state = new ScreenshotResultState(
            Guid.NewGuid(),
            "shot-1",
            "Screenshots/shot/original.png",
            "recognized text",
            []);
        var speech = new ScreenshotSpeechController(new ThrowingSpeechBackend(
            new OperationCanceledException()));
        using var viewModel = new ScreenshotResultViewModel(
            state,
            new EmptyTransformService(),
            new AssetResolver(),
            new Clipboard(),
            speech,
            initialTab: ScreenshotResultTab.Ocr);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(viewModel.ToggleSpeechAsync);

        Assert.NotEqual(
            L10n.Localize("ScreenshotResultSpeechFailed"),
            viewModel.SpeechFeedback);
    }

    private sealed class EmptyTransformService : IScreenshotTransformStreamingService
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
            Path.GetFullPath(relativePath);
    }

    private sealed class Clipboard : IScreenshotResultClipboard
    {
        public bool TrySetText(string text) => true;
        public Task<bool> TrySetImageAsync(
            string absoluteImagePath,
            CancellationToken cancellationToken = default) => Task.FromResult(true);
    }

    private sealed class ThrowingSpeechBackend(Exception exception) : IScreenshotSpeechBackend
    {
        public bool IsAvailable => throw exception;
        public Task SpeakAsync(string text, CancellationToken cancellationToken) =>
            Task.CompletedTask;
    }
}
