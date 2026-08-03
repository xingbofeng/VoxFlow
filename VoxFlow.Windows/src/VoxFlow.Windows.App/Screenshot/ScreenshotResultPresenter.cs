using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Screenshot;

public interface IScreenshotResultPresenter : IDisposable
{
    bool Present(
        ScreenshotCompletionKind completionKind,
        ScreenshotCompletionResult completion);

    void Close();
}

/// <summary>
/// Converts a successful completion transaction into the stable presentation
/// state consumed by the thumbnail and expanded panel. Failed, cancelled, or
/// stale completion results never create a result window.
/// </summary>
public sealed class ScreenshotResultPresenter : IScreenshotResultPresenter
{
    private readonly IScreenshotTransformStreamingService transforms;
    private readonly IScreenshotResultAssetResolver assets;
    private readonly IScreenshotResultClipboard clipboard;
    private readonly IScreenshotSpeechBackend speechBackend;
    private readonly IScreenshotResultTransformPersistence? persistence;
    private readonly IScreenshotResultPanelHost panels;
    private bool disposed;

    public ScreenshotResultPresenter(
        IScreenshotTransformStreamingService transforms,
        IScreenshotResultAssetResolver assets,
        IScreenshotResultClipboard clipboard,
        IScreenshotSpeechBackend speechBackend,
        IScreenshotResultTransformPersistence? persistence = null,
        IScreenshotResultPanelHost? panels = null)
    {
        this.transforms = transforms ?? throw new ArgumentNullException(nameof(transforms));
        this.assets = assets ?? throw new ArgumentNullException(nameof(assets));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.speechBackend = speechBackend ?? throw new ArgumentNullException(nameof(speechBackend));
        this.persistence = persistence;
        this.panels = panels ?? new ScreenshotResultPanelController();
    }

    public bool Present(
        ScreenshotCompletionKind completionKind,
        ScreenshotCompletionResult completion)
    {
        var dispatcher = ActiveApplicationDispatcher();
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            return dispatcher.Invoke(() => Present(completionKind, completion));
        }
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(completion);
        if (completion.Status != ScreenshotCompletionStatus.Succeeded
            || completion.Record is not { } record
            || !string.Equals(record.Id, completion.ScreenshotId, StringComparison.Ordinal))
        {
            return false;
        }

        var ocrLines = completion.OcrOutcome is
            { Status: ScreenshotOcrOutcomeStatus.Succeeded } ocr
                ? ocr.Lines
                : [];
        var state = new ScreenshotResultState(
            completion.RunId,
            completion.ScreenshotId,
            record.RenderedImagePath,
            record.OcrText,
            ocrLines,
            completion.OcrOutcome?.Status
                ?? (string.IsNullOrWhiteSpace(record.OcrText)
                    ? ScreenshotOcrOutcomeStatus.Failed
                    : ScreenshotOcrOutcomeStatus.Succeeded));
        SeedCompletedTransform(
            state,
            ScreenshotTransformOperation.Refinement,
            record.RefinedText);
        SeedCompletedTransform(
            state,
            ScreenshotTransformOperation.Translation,
            record.TranslatedText);
        SeedCompletedTransform(
            state,
            ScreenshotTransformOperation.Summary,
            record.SummaryText);

        var route = ScreenshotResultPresentationPolicy.For(completionKind);
        if (route.Kind == ScreenshotResultPresentationKind.None)
        {
            return false;
        }
        var viewModel = new ScreenshotResultViewModel(
            state,
            transforms,
            assets,
            clipboard,
            new ScreenshotSpeechController(speechBackend),
            persistence,
            route.InitialTab,
            record.TranslatedImagePath,
            record.ThumbnailPath);
        panels.Present(viewModel, completionKind);
        return true;
    }

    public void Close()
    {
        var dispatcher = ActiveApplicationDispatcher();
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(Close);
            return;
        }
        panels.CloseActive();
    }

    public void Dispose()
    {
        var dispatcher = ActiveApplicationDispatcher();
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(Dispose);
            return;
        }
        if (disposed)
        {
            return;
        }
        disposed = true;
        panels.Dispose();
    }

    private static System.Windows.Threading.Dispatcher? ActiveApplicationDispatcher()
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        return dispatcher is null
            || dispatcher.HasShutdownStarted
            || dispatcher.HasShutdownFinished
                ? null
                : dispatcher;
    }

    private static void SeedCompletedTransform(
        ScreenshotResultState state,
        ScreenshotTransformOperation operation,
        string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }
        state.Apply(new ScreenshotTransformStarted(
            state.RunId,
            state.ScreenshotId,
            operation));
        state.Apply(new ScreenshotTransformCompleted(
            state.RunId,
            state.ScreenshotId,
            operation,
            text,
            fromCache: true));
    }
}
