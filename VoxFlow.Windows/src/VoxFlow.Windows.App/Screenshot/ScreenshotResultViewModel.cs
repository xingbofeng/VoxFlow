using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotResultActionState
{
    Idle,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

/// <summary>
/// Presentation owner for one stable screenshot/run pair. Transform streams,
/// clipboard actions, and speech report independent state so one failure never
/// clears content produced by another action.
/// </summary>
public sealed class ScreenshotResultViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly ScreenshotResultState result;
    private readonly IScreenshotTransformStreamingService transforms;
    private readonly IScreenshotResultClipboard clipboard;
    private readonly ScreenshotSpeechController speech;
    private readonly IScreenshotResultTransformPersistence? persistence;
    private readonly IScreenshotResultImageLoader imageLoader;
    private readonly SynchronizationContext? synchronizationContext;
    private readonly object gate = new();
    private readonly Dictionary<ScreenshotTransformOperation, CancellationTokenSource> cancellations = [];
    private readonly Dictionary<ScreenshotTransformOperation, Task> activeTasks = [];
    private readonly Dictionary<ScreenshotTransformOperation, long> operationGenerations =
        Enum.GetValues<ScreenshotTransformOperation>().ToDictionary(operation => operation, _ => 0L);
    private ScreenshotResultTab selectedTab;
    private ScreenshotResultActionState textCopyActionState;
    private ScreenshotResultActionState imageCopyActionState;
    private ScreenshotResultActionState speechActionState;
    private string? textCopyFeedback;
    private string? imageCopyFeedback;
    private string? speechFeedback;
    private string? persistenceFeedback;
    private string? latestFooterFeedback;
    private CancellationTokenSource? imageCopyCancellation;
    private CancellationTokenSource? imageLoadCancellation;
    private Task? activeImageLoad;
    private string? activeImagePath;
    private long imageCopyGeneration;
    private long imageLoadGeneration;
    private BitmapSource? loadedImage;
    private string? loadedImagePath;
    private bool closed;
    private bool disposed;

    public ScreenshotResultViewModel(
        ScreenshotResultState result,
        IScreenshotTransformStreamingService transforms,
        IScreenshotResultAssetResolver assets,
        IScreenshotResultClipboard clipboard,
        ScreenshotSpeechController speech,
        IScreenshotResultTransformPersistence? persistence = null,
        ScreenshotResultTab initialTab = ScreenshotResultTab.Original,
        string? translatedImagePath = null,
        string? thumbnailImagePath = null,
        IScreenshotResultImageLoader? imageLoader = null)
    {
        this.result = result ?? throw new ArgumentNullException(nameof(result));
        this.transforms = transforms ?? throw new ArgumentNullException(nameof(transforms));
        ArgumentNullException.ThrowIfNull(assets);
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.speech = speech ?? throw new ArgumentNullException(nameof(speech));
        this.persistence = persistence;
        this.imageLoader = imageLoader ?? new ScreenshotResultImageLoader();
        if (!Enum.IsDefined(initialTab)) throw new ArgumentOutOfRangeException(nameof(initialTab));
        synchronizationContext = SynchronizationContext.Current;
        selectedTab = initialTab;
        OriginalImagePath = assets.ResolveAbsolutePath(result.OriginalImagePath);
        TranslatedImagePath = string.IsNullOrWhiteSpace(translatedImagePath)
            ? null
            : assets.ResolveAbsolutePath(translatedImagePath);
        ThumbnailImagePath = string.IsNullOrWhiteSpace(thumbnailImagePath)
            ? OriginalImagePath
            : assets.ResolveAbsolutePath(thumbnailImagePath);
        speech.StateChanged += OnSpeechStateChanged;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Title => L10n.Localize("ScreenshotResultTitle");
    public string OriginalTabLabel => L10n.Localize("ScreenshotOriginal");
    public string OcrTabLabel => L10n.Localize("ScreenshotOcrTab");
    public string RefinementTabLabel => L10n.Localize("ScreenshotRefinedTab");
    public string TranslationTabLabel => L10n.Localize("ScreenshotTranslationTab");
    public string SummaryTabLabel => L10n.Localize("ScreenshotSummaryTab");
    public string CloseLabel => L10n.Localize("ScreenshotClose");
    public string CopyTextLabel => L10n.Localize("ScreenshotCopyText");
    public string CopyImageLabel => L10n.Localize("ScreenshotCopyImage");
    public string RetryLabel => L10n.Localize("ScreenshotResultRetry");
    public string ImageUnavailableLabel => L10n.Localize("ScreenshotImageUnavailable");
    public string OpenResultLabel => L10n.Localize("ScreenshotResultOpen");
    public string ScreenshotResultStopSpeakingLabel =>
        L10n.Localize("ScreenshotResultStopSpeaking");

    public string TranslateButtonLabel => TranslationActionState == ScreenshotResultActionState.Running
        ? L10n.Localize("ScreenshotResultCancelTranslation")
        : L10n.Localize("ScreenshotResultTranslate");

    public string RefineButtonLabel => RefinementActionState == ScreenshotResultActionState.Running
        ? L10n.Localize("ScreenshotResultCancelRefinement")
        : L10n.Localize("ScreenshotResultRefine");

    public string SpeakButtonLabel => speech.State == ScreenshotSpeechState.Speaking
        ? L10n.Localize("ScreenshotResultStopSpeaking")
        : L10n.Localize("ScreenshotResultSpeak");

    public string OriginalImagePath { get; }

    public string? TranslatedImagePath { get; }

    public string ThumbnailImagePath { get; }

    public bool HasOriginalImage => File.Exists(OriginalImagePath);

    public bool HasThumbnailImage => File.Exists(ThumbnailImagePath);

    public string ThumbnailFallbackText => string.IsNullOrWhiteSpace(result.OriginalOcrText)
        ? OcrStatusMessage()
        : result.OriginalOcrText;

    public ScreenshotOcrOutcomeStatus OcrStatus => result.OcrStatus;

    public ScreenshotResultTab SelectedTab
    {
        get => selectedTab;
        private set
        {
            if (selectedTab == value)
            {
                return;
            }
            selectedTab = value;
            NotifyAll();
        }
    }

    public int SelectedTabIndex
    {
        get => (int)SelectedTab;
        set
        {
            if (Enum.IsDefined(typeof(ScreenshotResultTab), value))
            {
                SelectTab((ScreenshotResultTab)value);
            }
        }
    }

    public string CurrentText => SelectedTab switch
    {
        ScreenshotResultTab.Original => string.Empty,
        ScreenshotResultTab.Ocr => result.OriginalOcrText,
        ScreenshotResultTab.Refinement => TransformText(
            ScreenshotTransformOperation.Refinement,
            result.RefinedText),
        ScreenshotResultTab.Translation => TransformText(
            ScreenshotTransformOperation.Translation,
            result.TranslatedText),
        ScreenshotResultTab.Summary => TransformText(
            ScreenshotTransformOperation.Summary,
            result.SummaryText),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public string CurrentDisplayText => SelectedTab switch
    {
        ScreenshotResultTab.Ocr => OcrDisplayText,
        ScreenshotResultTab.Refinement => RefinementDisplayText,
        ScreenshotResultTab.Translation => TranslationDisplayText,
        ScreenshotResultTab.Summary => SummaryDisplayText,
        _ => L10n.Localize("ScreenshotResultNoText"),
    };

    public string OcrDisplayText => string.IsNullOrWhiteSpace(result.OriginalOcrText)
        ? OcrStatusMessage()
        : result.OriginalOcrText;

    public string RefinementDisplayText
    {
        get
        {
            var text = TransformText(
                ScreenshotTransformOperation.Refinement,
                result.RefinedText);
            return string.IsNullOrWhiteSpace(text)
                ? L10n.Localize("ScreenshotResultNoRefinement")
                : text;
        }
    }

    public string TranslationDisplayText
    {
        get
        {
            var text = TransformText(
                ScreenshotTransformOperation.Translation,
                result.TranslatedText);
            return string.IsNullOrWhiteSpace(text)
                ? L10n.Localize("ScreenshotResultNoTranslation")
                : text;
        }
    }

    public string SummaryDisplayText
    {
        get
        {
            var text = TransformText(
                ScreenshotTransformOperation.Summary,
                result.SummaryText);
            return string.IsNullOrWhiteSpace(text)
                ? L10n.Localize("ScreenshotResultNoSummary")
                : text;
        }
    }

    public bool IsCurrentTextPlaceholder => string.IsNullOrWhiteSpace(CurrentText);

    public string CurrentImagePath => SelectedTab == ScreenshotResultTab.Translation
        && !string.IsNullOrWhiteSpace(TranslatedImagePath)
            ? TranslatedImagePath!
            : OriginalImagePath;

    public BitmapSource? CurrentImage => string.Equals(
            loadedImagePath,
            CurrentImagePath,
            StringComparison.OrdinalIgnoreCase)
        ? loadedImage
        : null;

    public bool CanCopyText => SelectedTab != ScreenshotResultTab.Original
        && !string.IsNullOrWhiteSpace(CurrentText);

    public bool CanCopyImage => !string.IsNullOrWhiteSpace(CurrentImagePath)
        && ImageCopyActionState != ScreenshotResultActionState.Running;

    public bool CanSpeak => SelectedTab != ScreenshotResultTab.Original
        && !string.IsNullOrWhiteSpace(CurrentText);

    public bool CanRefine => !string.IsNullOrWhiteSpace(
            TransformSource(ScreenshotTransformOperation.Refinement))
        && TranslationActionState != ScreenshotResultActionState.Running
        && SummaryActionState != ScreenshotResultActionState.Running;

    public bool CanTranslate => !string.IsNullOrWhiteSpace(TransformSource(ScreenshotTransformOperation.Translation))
        && RefinementActionState != ScreenshotResultActionState.Running
        && SummaryActionState != ScreenshotResultActionState.Running;

    public bool CanRetryCurrentTransform => SelectedTab switch
    {
        ScreenshotResultTab.Refinement =>
            RefinementActionState is ScreenshotResultActionState.Failed
                or ScreenshotResultActionState.Cancelled,
        ScreenshotResultTab.Translation =>
            TranslationActionState is ScreenshotResultActionState.Failed
                or ScreenshotResultActionState.Cancelled,
        ScreenshotResultTab.Summary =>
            SummaryActionState is ScreenshotResultActionState.Failed
                or ScreenshotResultActionState.Cancelled,
        _ => false,
    };

    public bool IsSpeaking => speech.State == ScreenshotSpeechState.Speaking;

    public ScreenshotResultActionState RefinementActionState =>
        Map(result.GetStatus(ScreenshotTransformOperation.Refinement));

    public ScreenshotResultActionState TranslationActionState =>
        Map(result.GetStatus(ScreenshotTransformOperation.Translation));

    public ScreenshotResultActionState SummaryActionState =>
        Map(result.GetStatus(ScreenshotTransformOperation.Summary));

    public ScreenshotResultActionState TextCopyActionState
    {
        get => textCopyActionState;
        private set => SetField(ref textCopyActionState, value);
    }

    public ScreenshotResultActionState ImageCopyActionState
    {
        get => imageCopyActionState;
        private set => SetField(ref imageCopyActionState, value);
    }

    public ScreenshotResultActionState SpeechActionState
    {
        get => speechActionState;
        private set => SetField(ref speechActionState, value);
    }

    public string? RefinementFeedback => TransformFeedback(ScreenshotTransformOperation.Refinement);

    public string? TranslationFeedback => TransformFeedback(ScreenshotTransformOperation.Translation);

    public string? SummaryFeedback => TransformFeedback(ScreenshotTransformOperation.Summary);

    public string? TextCopyFeedback
    {
        get => textCopyFeedback;
        private set => SetField(ref textCopyFeedback, value);
    }

    public string? ImageCopyFeedback
    {
        get => imageCopyFeedback;
        private set => SetField(ref imageCopyFeedback, value);
    }

    public string? SpeechFeedback
    {
        get => speechFeedback;
        private set => SetField(ref speechFeedback, value);
    }

    public string? PersistenceFeedback
    {
        get => persistenceFeedback;
        private set => SetField(ref persistenceFeedback, value);
    }

    public string CurrentFeedback
    {
        get
        {
            var transformFeedback = SelectedTab switch
            {
                ScreenshotResultTab.Refinement => RefinementFeedback,
                ScreenshotResultTab.Translation => TranslationFeedback,
                ScreenshotResultTab.Summary => SummaryFeedback,
                _ => null,
            };
            var transformIsRunning = SelectedTab switch
            {
                ScreenshotResultTab.Refinement =>
                    RefinementActionState == ScreenshotResultActionState.Running,
                ScreenshotResultTab.Translation =>
                    TranslationActionState == ScreenshotResultActionState.Running,
                ScreenshotResultTab.Summary =>
                    SummaryActionState == ScreenshotResultActionState.Running,
                _ => false,
            };
            return transformIsRunning
                ? transformFeedback ?? string.Empty
                : latestFooterFeedback
                    ?? transformFeedback
                    ?? PersistenceFeedback
                    ?? string.Empty;
        }
    }

    public void SelectTab(ScreenshotResultTab tab)
    {
        ThrowIfClosed();
        if (!Enum.IsDefined(tab)) throw new ArgumentOutOfRangeException(nameof(tab));
        SelectedTab = tab;
    }

    public Task ActivateSelectedTabAsync() => SelectedTab switch
    {
        ScreenshotResultTab.Refinement when string.IsNullOrWhiteSpace(result.RefinedText)
            && CanRefine =>
            StartTransformAsync(ScreenshotTransformOperation.Refinement, force: false),
        ScreenshotResultTab.Translation when string.IsNullOrWhiteSpace(result.TranslatedText)
            && CanTranslate =>
            StartTransformAsync(ScreenshotTransformOperation.Translation, force: false),
        ScreenshotResultTab.Summary when string.IsNullOrWhiteSpace(result.SummaryText)
            && RefinementActionState != ScreenshotResultActionState.Running
            && TranslationActionState != ScreenshotResultActionState.Running =>
            StartTransformAsync(ScreenshotTransformOperation.Summary, force: false),
        _ => Task.CompletedTask,
    };

    public Task StartRefinementAsync()
    {
        SelectTab(ScreenshotResultTab.Refinement);
        return StartTransformAsync(ScreenshotTransformOperation.Refinement, force: true);
    }

    public Task StartTranslationAsync()
    {
        SelectTab(ScreenshotResultTab.Translation);
        return StartTransformAsync(ScreenshotTransformOperation.Translation, force: true);
    }

    public Task StartSummaryAsync()
    {
        SelectTab(ScreenshotResultTab.Summary);
        return StartTransformAsync(ScreenshotTransformOperation.Summary, force: true);
    }

    public Task RetryCurrentTransformAsync() => SelectedTab switch
    {
        ScreenshotResultTab.Refinement => StartRefinementAsync(),
        ScreenshotResultTab.Translation => StartTranslationAsync(),
        ScreenshotResultTab.Summary => StartSummaryAsync(),
        _ => Task.CompletedTask,
    };

    public void CancelRefinement() => CancelTransform(ScreenshotTransformOperation.Refinement);

    public void CancelTranslation() => CancelTransform(ScreenshotTransformOperation.Translation);

    public void CancelSummary() => CancelTransform(ScreenshotTransformOperation.Summary);

    public bool CopyCurrentText()
    {
        ThrowIfClosed();
        var text = CurrentText;
        if (SelectedTab == ScreenshotResultTab.Original || string.IsNullOrWhiteSpace(text))
        {
            TextCopyActionState = ScreenshotResultActionState.Failed;
            TextCopyFeedback = L10n.Localize("ScreenshotResultNoTextToCopy");
            latestFooterFeedback = TextCopyFeedback;
            NotifyAll();
            return false;
        }

        var copied = clipboard.TrySetText(text);
        TextCopyActionState = copied
            ? ScreenshotResultActionState.Succeeded
            : ScreenshotResultActionState.Failed;
        TextCopyFeedback = L10n.Localize(copied
            ? "ScreenshotResultCopiedText"
            : "ScreenshotResultCopyTextFailed");
        latestFooterFeedback = TextCopyFeedback;
        NotifyAll();
        return copied;
    }

    public async Task<bool> CopyCurrentImageAsync()
    {
        ThrowIfClosed();
        var imagePath = CurrentImagePath;
        if (string.IsNullOrWhiteSpace(imagePath))
        {
            PublishImageCopyResult(copied: false);
            return false;
        }

        CancellationTokenSource cancellation;
        long generation;
        lock (gate)
        {
            if (imageCopyCancellation is not null)
            {
                return false;
            }
            cancellation = new CancellationTokenSource();
            imageCopyCancellation = cancellation;
            generation = ++imageCopyGeneration;
        }
        ImageCopyActionState = ScreenshotResultActionState.Running;
        ImageCopyFeedback = null;
        latestFooterFeedback = null;
        NotifyAll();

        var copied = false;
        try
        {
            copied = await clipboard.TrySetImageAsync(
                imagePath,
                cancellation.Token);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            return false;
        }
        catch
        {
            copied = false;
        }
        finally
        {
            lock (gate)
            {
                if (ReferenceEquals(imageCopyCancellation, cancellation))
                {
                    imageCopyCancellation = null;
                }
            }
            cancellation.Dispose();
        }

        lock (gate)
        {
            if (closed || generation != imageCopyGeneration)
            {
                return false;
            }
        }
        PublishImageCopyResult(copied);
        return copied;
    }

    public Task LoadCurrentImageAsync()
    {
        if (SelectedTab is not (ScreenshotResultTab.Original or ScreenshotResultTab.Translation))
        {
            CancellationTokenSource? obsoleteLoad;
            lock (gate)
            {
                imageLoadGeneration++;
                obsoleteLoad = imageLoadCancellation;
                imageLoadCancellation = null;
                activeImageLoad = null;
                activeImagePath = null;
                loadedImage = null;
                loadedImagePath = null;
            }
            obsoleteLoad?.Cancel();
            return Task.CompletedTask;
        }
        var imagePath = CurrentImagePath;
        CancellationTokenSource cancellation;
        long generation;
        CancellationTokenSource? previous;
        Task task;
        lock (gate)
        {
            if (closed)
            {
                return Task.CompletedTask;
            }
            if (string.Equals(
                    loadedImagePath,
                    imagePath,
                    StringComparison.OrdinalIgnoreCase))
            {
                return Task.CompletedTask;
            }
            if (activeImageLoad is not null
                && imageLoadCancellation is not null
                && string.Equals(
                    activeImagePath,
                    imagePath,
                    StringComparison.OrdinalIgnoreCase))
            {
                return activeImageLoad;
            }
            previous = imageLoadCancellation;
            cancellation = new CancellationTokenSource();
            imageLoadCancellation = cancellation;
            activeImagePath = imagePath;
            generation = ++imageLoadGeneration;
            task = RunImageLoadAsync(imagePath, generation, cancellation);
            activeImageLoad = task;
        }
        previous?.Cancel();
        return task;
    }

    private async Task RunImageLoadAsync(
        string imagePath,
        long generation,
        CancellationTokenSource cancellation)
    {
        await Task.Yield();
        BitmapSource? image = null;
        try
        {
            image = await imageLoader.LoadPreviewAsync(
                imagePath,
                cancellation.Token);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            return;
        }
        catch
        {
            image = null;
        }
        finally
        {
            lock (gate)
            {
                if (ReferenceEquals(imageLoadCancellation, cancellation))
                {
                    imageLoadCancellation = null;
                    activeImageLoad = null;
                    activeImagePath = null;
                }
            }
            cancellation.Dispose();
        }

        lock (gate)
        {
            if (closed || generation != imageLoadGeneration)
            {
                return;
            }
            loadedImage = image;
            loadedImagePath = imagePath;
        }
        NotifyAll();
    }

    private void PublishImageCopyResult(bool copied)
    {
        ImageCopyActionState = copied
            ? ScreenshotResultActionState.Succeeded
            : ScreenshotResultActionState.Failed;
        ImageCopyFeedback = L10n.Localize(copied
            ? "ScreenshotResultCopiedImage"
            : "ScreenshotResultCopyImageFailed");
        latestFooterFeedback = ImageCopyFeedback;
        NotifyAll();
    }

    public async Task ToggleSpeechAsync()
    {
        ThrowIfClosed();
        if (speech.State == ScreenshotSpeechState.Speaking)
        {
            speech.Stop();
            SpeechActionState = ScreenshotResultActionState.Cancelled;
            SpeechFeedback = L10n.Localize("ScreenshotResultSpeechStopped");
            latestFooterFeedback = SpeechFeedback;
            NotifyAll();
            return;
        }

        var text = CurrentText;
        if (SelectedTab == ScreenshotResultTab.Original || string.IsNullOrWhiteSpace(text))
        {
            SpeechActionState = ScreenshotResultActionState.Failed;
            SpeechFeedback = L10n.Localize("ScreenshotResultNoTextToSpeak");
            latestFooterFeedback = SpeechFeedback;
            NotifyAll();
            return;
        }

        SpeechActionState = ScreenshotResultActionState.Running;
        SpeechFeedback = L10n.Localize("ScreenshotResultSpeaking");
        latestFooterFeedback = SpeechFeedback;
        NotifyAll();
        try
        {
            await speech.ToggleAsync(text);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            ReportSpeechFailure();
            return;
        }
        switch (speech.State)
        {
            case ScreenshotSpeechState.Idle:
                SpeechActionState = ScreenshotResultActionState.Succeeded;
                SpeechFeedback = L10n.Localize("ScreenshotResultSpeechComplete");
                break;
            case ScreenshotSpeechState.Unavailable:
                SpeechActionState = ScreenshotResultActionState.Failed;
                SpeechFeedback = L10n.Localize("ScreenshotResultSpeechUnavailable");
                break;
            case ScreenshotSpeechState.Failed:
                SpeechActionState = ScreenshotResultActionState.Failed;
                SpeechFeedback = L10n.Localize("ScreenshotResultSpeechFailed");
                break;
            case ScreenshotSpeechState.Speaking:
                break;
            default:
                throw new ArgumentOutOfRangeException();
        }
        latestFooterFeedback = SpeechFeedback;
        NotifyAll();
    }

    internal void ReportSpeechFailure()
    {
        SpeechActionState = ScreenshotResultActionState.Failed;
        SpeechFeedback = L10n.Localize("ScreenshotResultSpeechFailed");
        latestFooterFeedback = SpeechFeedback;
        NotifyAll();
    }

    public void StopSpeech()
    {
        speech.Stop();
        SpeechActionState = ScreenshotResultActionState.Cancelled;
        SpeechFeedback = L10n.Localize("ScreenshotResultSpeechStopped");
        latestFooterFeedback = SpeechFeedback;
        NotifyAll();
    }

    public void Close()
    {
        CancellationTokenSource? copyCancellation;
        CancellationTokenSource? loadCancellation;
        lock (gate)
        {
            if (closed)
            {
                return;
            }
            closed = true;
            imageCopyGeneration++;
            imageLoadGeneration++;
            copyCancellation = imageCopyCancellation;
            loadCancellation = imageLoadCancellation;
            imageCopyCancellation = null;
            imageLoadCancellation = null;
            activeImageLoad = null;
            activeImagePath = null;
        }
        copyCancellation?.Cancel();
        loadCancellation?.Cancel();
        CancelTransformCore(ScreenshotTransformOperation.Refinement);
        CancelTransformCore(ScreenshotTransformOperation.Translation);
        CancelTransformCore(ScreenshotTransformOperation.Summary);
        speech.Stop();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        speech.StateChanged -= OnSpeechStateChanged;
        Close();
        speech.DisposeAsync().AsTask().GetAwaiter().GetResult();
    }

    private Task StartTransformAsync(ScreenshotTransformOperation operation, bool force)
    {
        ThrowIfClosed();
        var sourceText = TransformSource(operation);
        if (string.IsNullOrWhiteSpace(sourceText))
        {
            SetMissingSourceFeedback(operation);
            return Task.CompletedTask;
        }

        lock (gate)
        {
            if (activeTasks.TryGetValue(operation, out var active))
            {
                return active;
            }
            if (!force && HasCompletedValue(operation))
            {
                return Task.CompletedTask;
            }

            var generation = ++operationGenerations[operation];
            var cancellation = new CancellationTokenSource();
            cancellations[operation] = cancellation;
            latestFooterFeedback = null;
            var task = RunTransformAsync(operation, sourceText, generation, cancellation);
            activeTasks[operation] = task;
            return task;
        }
    }

    private async Task RunTransformAsync(
        ScreenshotTransformOperation operation,
        string sourceText,
        long generation,
        CancellationTokenSource cancellation)
    {
        await Task.Yield();
        try
        {
            var request = new ScreenshotTransformRequest(
                result.RunId,
                result.ScreenshotId,
                sourceText,
                operation,
                inputRevision: result.OriginalImagePath);
            await foreach (var @event in transforms.TransformAsync(request, cancellation.Token))
            {
                if (@event.Operation != operation || !IsCurrent(operation, generation, cancellation))
                {
                    continue;
                }
                if (!result.Apply(@event))
                {
                    continue;
                }
                if (@event is ScreenshotTransformCompleted completed && persistence is not null)
                {
                    bool persisted;
                    try
                    {
                        persisted = persistence.Persist(completed);
                    }
                    catch
                    {
                        persisted = false;
                    }
                    PersistenceFeedback = persisted
                        ? null
                        : L10n.Localize("ScreenshotResultHistoryUpdateFailed");
                }
                NotifyAll();
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            // CancelTransformCore publishes the deterministic terminal state.
        }
        catch
        {
            if (IsCurrent(operation, generation, cancellation))
            {
                EnsureRunning(operation);
                result.Apply(new ScreenshotTransformFailed(
                    result.RunId,
                    result.ScreenshotId,
                    operation,
                    "screenshot.transform.request_failed",
                    result.GetPartial(operation)));
                NotifyAll();
            }
        }
        finally
        {
            lock (gate)
            {
                if (cancellations.TryGetValue(operation, out var current)
                    && ReferenceEquals(current, cancellation))
                {
                    cancellations.Remove(operation);
                    activeTasks.Remove(operation);
                }
            }
            cancellation.Dispose();
            NotifyAll();
        }
    }

    private void CancelTransform(ScreenshotTransformOperation operation)
    {
        ThrowIfClosed();
        CancelTransformCore(operation);
    }

    private void CancelTransformCore(ScreenshotTransformOperation operation)
    {
        CancellationTokenSource? cancellation;
        lock (gate)
        {
            operationGenerations[operation]++;
            cancellations.TryGetValue(operation, out cancellation);
            cancellations.Remove(operation);
            activeTasks.Remove(operation);
        }
        cancellation?.Cancel();
        if (result.GetStatus(operation) == ScreenshotTransformStatus.Running)
        {
            result.Apply(new ScreenshotTransformCancelled(
                result.RunId,
                result.ScreenshotId,
                operation,
                result.GetPartial(operation)));
        }
        NotifyAll();
    }

    private bool IsCurrent(
        ScreenshotTransformOperation operation,
        long generation,
        CancellationTokenSource cancellation)
    {
        lock (gate)
        {
            return !closed
                && operationGenerations[operation] == generation
                && cancellations.TryGetValue(operation, out var current)
                && ReferenceEquals(current, cancellation);
        }
    }

    private void EnsureRunning(ScreenshotTransformOperation operation)
    {
        if (result.GetStatus(operation) != ScreenshotTransformStatus.Running)
        {
            result.Apply(new ScreenshotTransformStarted(result.RunId, result.ScreenshotId, operation));
        }
    }

    private string TransformSource(ScreenshotTransformOperation operation) => operation switch
    {
        ScreenshotTransformOperation.Refinement => result.OriginalOcrText,
        ScreenshotTransformOperation.Translation => result.RefinedText ?? result.OriginalOcrText,
        ScreenshotTransformOperation.Summary => result.TranslatedText
            ?? result.RefinedText
            ?? result.OriginalOcrText,
        _ => throw new ArgumentOutOfRangeException(nameof(operation)),
    };

    private bool HasCompletedValue(ScreenshotTransformOperation operation) => operation switch
    {
        ScreenshotTransformOperation.Refinement => !string.IsNullOrWhiteSpace(result.RefinedText),
        ScreenshotTransformOperation.Translation => !string.IsNullOrWhiteSpace(result.TranslatedText),
        ScreenshotTransformOperation.Summary => !string.IsNullOrWhiteSpace(result.SummaryText),
        _ => throw new ArgumentOutOfRangeException(nameof(operation)),
    };

    private string TransformText(ScreenshotTransformOperation operation, string? completedText)
    {
        var status = result.GetStatus(operation);
        var partial = result.GetPartial(operation);
        if ((status is ScreenshotTransformStatus.Running or ScreenshotTransformStatus.PartiallyCompleted)
            && !string.IsNullOrWhiteSpace(partial))
        {
            return partial;
        }
        return completedText ?? partial;
    }

    private string? TransformFeedback(ScreenshotTransformOperation operation)
    {
        var status = result.GetStatus(operation);
        return status switch
        {
            ScreenshotTransformStatus.Idle => null,
            ScreenshotTransformStatus.Running => L10n.Localize(operation switch
            {
                ScreenshotTransformOperation.Refinement => "ScreenshotResultRefining",
                ScreenshotTransformOperation.Translation => "ScreenshotResultTranslating",
                ScreenshotTransformOperation.Summary => "ScreenshotResultSummarizing",
                _ => throw new ArgumentOutOfRangeException(nameof(operation)),
            }),
            ScreenshotTransformStatus.Completed => L10n.Localize(operation switch
            {
                ScreenshotTransformOperation.Refinement => "ScreenshotResultRefinementComplete",
                ScreenshotTransformOperation.Translation => "ScreenshotResultTranslationComplete",
                ScreenshotTransformOperation.Summary => "ScreenshotResultSummaryComplete",
                _ => throw new ArgumentOutOfRangeException(nameof(operation)),
            }),
            ScreenshotTransformStatus.Failed => LocalizeTransformFailure(result.GetSafeMessage(operation)),
            ScreenshotTransformStatus.Cancelled => L10n.Localize(operation switch
            {
                ScreenshotTransformOperation.Refinement => "ScreenshotResultRefinementCancelled",
                ScreenshotTransformOperation.Translation => "ScreenshotResultTranslationCancelled",
                ScreenshotTransformOperation.Summary => "ScreenshotResultSummaryCancelled",
                _ => throw new ArgumentOutOfRangeException(nameof(operation)),
            }),
            ScreenshotTransformStatus.PartiallyCompleted => L10n.Localize(operation switch
            {
                ScreenshotTransformOperation.Refinement => "ScreenshotResultRefinementPartial",
                ScreenshotTransformOperation.Translation => "ScreenshotResultTranslationPartial",
                ScreenshotTransformOperation.Summary => "ScreenshotResultSummaryPartial",
                _ => throw new ArgumentOutOfRangeException(nameof(operation)),
            }),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }

    private static string LocalizeTransformFailure(string? safeCode) => L10n.Localize(safeCode switch
    {
        "screenshot.transform.provider_not_configured" => "ScreenshotResultProviderNotConfigured",
        "screenshot.transform.provider_unavailable" => "ScreenshotResultProviderUnavailable",
        "screenshot.transform.empty_result" => "ScreenshotResultEmptyTransform",
        _ => "ScreenshotResultTransformFailed",
    });

    private string OcrStatusMessage() => L10n.Localize(result.OcrStatus switch
    {
        ScreenshotOcrOutcomeStatus.Empty => "ScreenshotResultOcrEmpty",
        ScreenshotOcrOutcomeStatus.RuntimeUnavailable => "ScreenshotResultOcrRuntimeUnavailable",
        ScreenshotOcrOutcomeStatus.InputUnavailable => "ScreenshotResultOcrInputUnavailable",
        ScreenshotOcrOutcomeStatus.TimedOut => "ScreenshotResultOcrTimedOut",
        ScreenshotOcrOutcomeStatus.Failed => "ScreenshotResultOcrFailed",
        ScreenshotOcrOutcomeStatus.Cancelled => "ScreenshotResultOcrCancelled",
        ScreenshotOcrOutcomeStatus.Stale => "ScreenshotResultOcrStale",
        ScreenshotOcrOutcomeStatus.Succeeded => "ScreenshotResultNoText",
        _ => throw new ArgumentOutOfRangeException(),
    });

    private void SetMissingSourceFeedback(ScreenshotTransformOperation operation)
    {
        EnsureRunning(operation);
        result.Apply(new ScreenshotTransformFailed(
            result.RunId,
            result.ScreenshotId,
            operation,
            "screenshot.transform.empty_result",
            string.Empty));
        NotifyAll();
    }

    private void OnSpeechStateChanged(object? sender, EventArgs eventArgs) => NotifyAll();

    private void NotifyAll()
    {
        void Raise()
        {
            OnPropertyChanged(string.Empty);
            OnPropertyChanged(nameof(SelectedTab));
            OnPropertyChanged(nameof(SelectedTabIndex));
            OnPropertyChanged(nameof(CurrentText));
            OnPropertyChanged(nameof(CurrentDisplayText));
            OnPropertyChanged(nameof(OcrDisplayText));
            OnPropertyChanged(nameof(RefinementDisplayText));
            OnPropertyChanged(nameof(TranslationDisplayText));
            OnPropertyChanged(nameof(SummaryDisplayText));
            OnPropertyChanged(nameof(HasThumbnailImage));
            OnPropertyChanged(nameof(IsCurrentTextPlaceholder));
            OnPropertyChanged(nameof(CurrentImagePath));
            OnPropertyChanged(nameof(CurrentImage));
            OnPropertyChanged(nameof(CanCopyText));
            OnPropertyChanged(nameof(CanCopyImage));
            OnPropertyChanged(nameof(CanSpeak));
            OnPropertyChanged(nameof(CanRefine));
            OnPropertyChanged(nameof(CanTranslate));
            OnPropertyChanged(nameof(CanRetryCurrentTransform));
            OnPropertyChanged(nameof(IsSpeaking));
            OnPropertyChanged(nameof(RefineButtonLabel));
            OnPropertyChanged(nameof(TranslateButtonLabel));
            OnPropertyChanged(nameof(SpeakButtonLabel));
            OnPropertyChanged(nameof(RefinementActionState));
            OnPropertyChanged(nameof(TranslationActionState));
            OnPropertyChanged(nameof(SummaryActionState));
            OnPropertyChanged(nameof(RefinementFeedback));
            OnPropertyChanged(nameof(TranslationFeedback));
            OnPropertyChanged(nameof(SummaryFeedback));
            OnPropertyChanged(nameof(CurrentFeedback));
        }

        if (synchronizationContext is not null
            && !ReferenceEquals(SynchronizationContext.Current, synchronizationContext))
        {
            synchronizationContext.Post(_ => Raise(), null);
            return;
        }
        Raise();
    }

    private static ScreenshotResultActionState Map(ScreenshotTransformStatus status) => status switch
    {
        ScreenshotTransformStatus.Idle => ScreenshotResultActionState.Idle,
        ScreenshotTransformStatus.Running => ScreenshotResultActionState.Running,
        ScreenshotTransformStatus.Completed => ScreenshotResultActionState.Succeeded,
        ScreenshotTransformStatus.Failed => ScreenshotResultActionState.Failed,
        ScreenshotTransformStatus.Cancelled or ScreenshotTransformStatus.PartiallyCompleted =>
            ScreenshotResultActionState.Cancelled,
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        OnPropertyChanged(nameof(CurrentFeedback));
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private void ThrowIfClosed()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        lock (gate)
        {
            if (closed)
            {
                throw new ObjectDisposedException(nameof(ScreenshotResultViewModel));
            }
        }
    }
}
