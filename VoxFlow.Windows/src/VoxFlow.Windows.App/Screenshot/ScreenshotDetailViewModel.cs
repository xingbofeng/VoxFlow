using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotDetailTextSection
{
    Ocr,
    Translation,
    Summary,
}

public sealed class ScreenshotDetailViewModel : INotifyPropertyChanged
{
    private readonly object refreshSynchronization = new();
    private readonly IScreenshotRecordRepository? records;
    private readonly IScreenshotAssetStore? assets;
    private readonly IScreenshotMediaPlatform? platform;
    private readonly TimeProvider timeProvider;
    private readonly TimeZoneInfo displayTimeZone;
    private readonly IScreenshotTransformCacheInvalidator? transformCacheInvalidator;
    private ScreenshotRecord? record;
    private BitmapSource? originalImage;
    private BitmapSource? translatedImage;
    private BitmapSource? displayedImage;
    private string? originalDisplayPath;
    private string? translatedDisplayPath;
    private string? reprocessImagePath;
    private ScreenshotAssetAvailability reprocessImageAvailability =
        ScreenshotAssetAvailability.Missing;
    private string title = string.Empty;
    private string createdAtText = string.Empty;
    private string resolutionText = string.Empty;
    private string fileSizeText = string.Empty;
    private string characterCountText = string.Empty;
    private string sourceDisplayId = string.Empty;
    private string sourceWindowTitle = string.Empty;
    private string ocrText = string.Empty;
    private string refinedText = string.Empty;
    private string translatedText = string.Empty;
    private string summaryText = string.Empty;
    private bool isFavorite;
    private bool isDeleted;
    private bool isLoading;
    private ScreenshotDetailTextSection selectedTextSection;
    private string? feedback;
    private CancellationTokenSource? activeRefreshCancellation;
    private long refreshGeneration;

    public ScreenshotDetailViewModel()
    {
        Id = string.Empty;
        timeProvider = TimeProvider.System;
        displayTimeZone = TimeZoneInfo.Local;
    }

    public ScreenshotDetailViewModel(
        string id,
        IScreenshotRecordRepository records,
        IScreenshotAssetStore assets,
        IScreenshotMediaPlatform? platform = null,
        TimeProvider? timeProvider = null,
        TimeZoneInfo? displayTimeZone = null,
        IScreenshotTransformCacheInvalidator? transformCacheInvalidator = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        Id = id.Trim();
        this.records = records ?? throw new ArgumentNullException(nameof(records));
        this.assets = assets ?? throw new ArgumentNullException(nameof(assets));
        this.platform = platform ?? new WpfScreenshotMediaPlatform();
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.displayTimeZone = displayTimeZone ?? TimeZoneInfo.Local;
        this.transformCacheInvalidator = transformCacheInvalidator;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler<string>? ActionRequested;

    public event EventHandler<string>? ReprocessRequested;

    public event EventHandler? CloseRequested;

    public string Id { get; init; }

    public string Title
    {
        get => title;
        init => title = value ?? string.Empty;
    }

    public string CreatedAtText
    {
        get => createdAtText;
        init => createdAtText = value ?? string.Empty;
    }

    public string ResolutionText
    {
        get => resolutionText;
        init => resolutionText = value ?? string.Empty;
    }

    public string FileSizeText
    {
        get => fileSizeText;
        init => fileSizeText = value ?? string.Empty;
    }

    public string CharacterCountText
    {
        get => characterCountText;
        init => characterCountText = value ?? string.Empty;
    }

    public string SourceDisplayId => sourceDisplayId;

    public string SourceWindowTitle => sourceWindowTitle;

    public bool HasSourceMetadata =>
        !string.IsNullOrWhiteSpace(SourceDisplayId)
        || !string.IsNullOrWhiteSpace(SourceWindowTitle);

    public string OcrText
    {
        get => ocrText;
        init => ocrText = value ?? string.Empty;
    }

    public string RefinedText
    {
        get => refinedText;
        init => refinedText = value ?? string.Empty;
    }

    public string TranslatedText
    {
        get => translatedText;
        init => translatedText = value ?? string.Empty;
    }

    public string SummaryText
    {
        get => summaryText;
        init => summaryText = value ?? string.Empty;
    }

    public string OcrDisplayText => DisplayText(OcrText);

    public string TranslatedDisplayText => DisplayText(TranslatedText);

    public string SummaryDisplayText => DisplayText(SummaryText);

    public BitmapSource? OriginalImage
    {
        get => originalImage;
        init => originalImage = value;
    }

    public BitmapSource? TranslatedImage
    {
        get => translatedImage;
        init => translatedImage = value;
    }

    public BitmapSource? DisplayedImage
    {
        get => displayedImage ?? OriginalImage;
        private set
        {
            if (SetField(ref displayedImage, value))
            {
                NotifyImageStateChanged();
            }
        }
    }

    public bool HasImage => DisplayedImage is not null;

    public bool HasTranslatedImage => TranslatedImage is not null;

    public bool CanCopyImage => HasImage && CurrentImagePath is not null;

    public bool CanSaveAs => CanCopyImage;

    public bool CanReveal => CanCopyImage;

    public bool CanReprocess =>
        reprocessImagePath is not null
        && reprocessImageAvailability == ScreenshotAssetAvailability.Available;

    public string AssetStatusText => HasImage
        ? string.Empty
        : L10n.Localize("ScreenshotAssetMissingDetail");

    public bool IsFavorite
    {
        get => isFavorite;
        private set
        {
            if (SetField(ref isFavorite, value))
            {
                OnPropertyChanged(nameof(FavoriteStatusText));
            }
        }
    }

    public string FavoriteStatusText => IsFavorite
        ? L10n.ScreenshotFavorited
        : L10n.ScreenshotNotFavorited;

    public bool IsDeleted
    {
        get => isDeleted;
        private set => SetField(ref isDeleted, value);
    }

    public bool IsLoading
    {
        get => isLoading;
        private set => SetField(ref isLoading, value);
    }

    public ScreenshotDetailTextSection SelectedTextSection
    {
        get => selectedTextSection;
        private set
        {
            if (SetField(ref selectedTextSection, value))
            {
                OnPropertyChanged(nameof(CurrentText));
            }
        }
    }

    public string CurrentText => SelectedTextSection switch
    {
        ScreenshotDetailTextSection.Ocr => OcrText,
        ScreenshotDetailTextSection.Translation => TranslatedText,
        ScreenshotDetailTextSection.Summary => SummaryText,
        _ => throw new ArgumentOutOfRangeException(),
    };

    public string? Feedback
    {
        get => feedback;
        private set => SetField(ref feedback, value);
    }

    private string? CurrentImagePath =>
        ReferenceEquals(DisplayedImage, TranslatedImage)
            ? translatedDisplayPath
            : originalDisplayPath;

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (records is null || assets is null || platform is null)
        {
            return;
        }

        var operation = BeginRefresh(cancellationToken);
        var wasShowingTranslation = translatedImage is not null
            && ReferenceEquals(displayedImage, translatedImage);
        IsLoading = true;
        try
        {
            var result = await Task.Run(
                () => LoadRefreshResult(
                    wasShowingTranslation,
                    operation.Cancellation.Token),
                operation.Cancellation.Token).ConfigureAwait(true);
            if (!IsCurrentRefresh(operation))
            {
                return;
            }
            if (result.Record is null)
            {
                Feedback = L10n.Localize("ScreenshotRecordUnavailable");
                return;
            }

            record = result.Record;
            IsDeleted = false;
            ApplyRecord(result.Record);
            ApplyImages(result.Images!);
            Feedback = HasImage
                ? null
                : L10n.Localize("ScreenshotAssetMissingDetail");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // A newer refresh generation owns the detail projection.
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            if (IsCurrentRefresh(operation))
            {
                Feedback = L10n.Localize("ScreenshotDetailLoadFailed");
            }
        }
        finally
        {
            if (OwnsRefresh(operation))
            {
                IsLoading = false;
            }
            FinishRefresh(operation);
        }
    }

    public async Task ExecuteAsync(
        string action,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(action);
        ActionRequested?.Invoke(this, action);
        if (records is null || platform is null || record is null)
        {
            return;
        }

        try
        {
            switch (action)
            {
                case ScreenshotMediaActions.CopyImage:
                    if (!CanCopyImage)
                    {
                        Feedback = L10n.Localize("ScreenshotAssetUnavailableAction");
                        return;
                    }
                    await platform.CopyImageAsync(
                        CurrentImagePath!,
                        cancellationToken).ConfigureAwait(true);
                    Feedback = L10n.Localize("ScreenshotCopyImageSucceeded");
                    break;
                case ScreenshotMediaActions.CopyText:
                    if (string.IsNullOrWhiteSpace(CurrentText))
                    {
                        Feedback = L10n.Localize("ScreenshotTextUnavailable");
                        return;
                    }
                    await platform.CopyTextAsync(
                        CurrentText,
                        cancellationToken).ConfigureAwait(true);
                    Feedback = L10n.Localize("ScreenshotCopyTextSucceeded");
                    break;
                case ScreenshotMediaActions.SaveAs:
                    if (!CanSaveAs)
                    {
                        Feedback = L10n.Localize("ScreenshotAssetUnavailableAction");
                        return;
                    }
                    if (await platform.SaveImageAsAsync(
                            CurrentImagePath!,
                            CreateSuggestedFileName(),
                            cancellationToken).ConfigureAwait(true))
                    {
                        Feedback = L10n.Localize("ScreenshotSaveSucceeded");
                    }
                    break;
                case ScreenshotMediaActions.Reveal:
                    if (!CanReveal)
                    {
                        Feedback = L10n.Localize("ScreenshotAssetUnavailableAction");
                        return;
                    }
                    await platform.RevealInExplorerAsync(
                        CurrentImagePath!,
                        cancellationToken).ConfigureAwait(true);
                    Feedback = L10n.Localize("ScreenshotRevealSucceeded");
                    break;
                case ScreenshotMediaActions.Reprocess:
                    if (!CanReprocess)
                    {
                        Feedback = L10n.Localize("ScreenshotReprocessUnavailable");
                        return;
                    }
                    transformCacheInvalidator?.Invalidate(Id);
                    ReprocessRequested?.Invoke(this, Id);
                    Feedback = L10n.Localize("ScreenshotReprocessRequested");
                    break;
                case ScreenshotMediaActions.Favorite:
                    if (!records.SetFavorite(
                            Id,
                            !IsFavorite,
                            timeProvider.GetUtcNow()))
                    {
                        Feedback = L10n.Localize("ScreenshotRecordUnavailable");
                        return;
                    }
                    IsFavorite = !IsFavorite;
                    Feedback = IsFavorite
                        ? L10n.Localize("ScreenshotFavoriteAdded")
                        : L10n.Localize("ScreenshotFavoriteRemoved");
                    break;
                case ScreenshotMediaActions.Delete:
                    if (!await platform.ConfirmDeleteAsync(
                            L10n.Localize("ScreenshotDeleteConfirmationTitle"),
                            Format("ScreenshotDeleteConfirmationMessage", CreatedAtText),
                            cancellationToken).ConfigureAwait(true))
                    {
                        return;
                    }
                    if (!records.SoftDelete(Id, timeProvider.GetUtcNow()))
                    {
                        Feedback = L10n.Localize("ScreenshotRecordUnavailable");
                        return;
                    }
                    transformCacheInvalidator?.Invalidate(Id);
                    IsDeleted = true;
                    Feedback = L10n.Localize("ScreenshotDeleteSucceeded");
                    CloseRequested?.Invoke(this, EventArgs.Empty);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(action));
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            Feedback = L10n.Localize("ScreenshotActionFailed");
        }
    }

    public void Execute(string action) => _ = ExecuteAsync(action);

    public void ShowOriginal()
    {
        DisplayedImage = OriginalImage;
        NotifyImageStateChanged();
    }

    public void ShowTranslation()
    {
        DisplayedImage = TranslatedImage ?? OriginalImage;
        NotifyImageStateChanged();
    }

    public void SelectTextSection(ScreenshotDetailTextSection section)
    {
        if (!Enum.IsDefined(section))
        {
            throw new ArgumentOutOfRangeException(nameof(section));
        }
        SelectedTextSection = section;
    }

    public Task NotifyRecordUpdatedAsync(
        string screenshotId,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(screenshotId);
        return string.Equals(screenshotId, Id, StringComparison.Ordinal)
            ? RefreshAsync(cancellationToken)
            : Task.CompletedTask;
    }

    private void ApplyRecord(ScreenshotRecord current)
    {
        var localCreated = TimeZoneInfo.ConvertTime(
            current.CreatedAtUtc,
            displayTimeZone);
        title = string.IsNullOrWhiteSpace(current.SourceWindowTitle)
            ? L10n.ScreenshotDetailTitle
            : current.SourceWindowTitle;
        createdAtText = localCreated.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
        resolutionText = $"{current.WidthPixels} × {current.HeightPixels}";
        fileSizeText = FormatFileSize(current.FileSizeBytes);
        characterCountText = current.CharacterCount.ToString(
            "N0",
            CultureInfo.CurrentUICulture);
        sourceDisplayId = current.SourceDisplayId ?? string.Empty;
        sourceWindowTitle = current.SourceWindowTitle ?? string.Empty;
        ocrText = current.OcrText;
        refinedText = current.RefinedText ?? string.Empty;
        translatedText = current.TranslatedText ?? string.Empty;
        summaryText = current.SummaryText ?? string.Empty;
        IsFavorite = current.IsFavorite;

        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(CreatedAtText));
        OnPropertyChanged(nameof(ResolutionText));
        OnPropertyChanged(nameof(FileSizeText));
        OnPropertyChanged(nameof(CharacterCountText));
        OnPropertyChanged(nameof(SourceDisplayId));
        OnPropertyChanged(nameof(SourceWindowTitle));
        OnPropertyChanged(nameof(HasSourceMetadata));
        OnPropertyChanged(nameof(OcrText));
        OnPropertyChanged(nameof(RefinedText));
        OnPropertyChanged(nameof(TranslatedText));
        OnPropertyChanged(nameof(SummaryText));
        OnPropertyChanged(nameof(OcrDisplayText));
        OnPropertyChanged(nameof(TranslatedDisplayText));
        OnPropertyChanged(nameof(SummaryDisplayText));
        OnPropertyChanged(nameof(CurrentText));
    }

    private DetailRefreshResult LoadRefreshResult(
        bool wasShowingTranslation,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var current = records!.Get(Id);
        cancellationToken.ThrowIfCancellationRequested();
        return current is null
            ? new DetailRefreshResult(null, null)
            : new DetailRefreshResult(
                current,
                LoadImages(current, wasShowingTranslation, cancellationToken));
    }

    private DetailImageLoadResult LoadImages(
        ScreenshotRecord current,
        bool wasShowingTranslation,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var capturePath = assets!.ResolveAbsolutePath(current.OriginalImagePath);
        var renderedPath = assets.ResolveAbsolutePath(current.RenderedImagePath);
        var renderedAvailability = SafeGetAvailability(renderedPath);
        cancellationToken.ThrowIfCancellationRequested();
        var rendered = SafeLoad(renderedPath, cancellationToken);
        var originalCapture = rendered.Image is null
            ? SafeLoad(capturePath, cancellationToken)
            : null;
        var loadedOriginalImage = rendered.Image ?? originalCapture?.Image;
        var loadedOriginalDisplayPath = rendered.Image is not null
            ? renderedPath
            : originalCapture?.Image is not null
                ? capturePath
                : null;

        cancellationToken.ThrowIfCancellationRequested();
        var loadedTranslatedDisplayPath = current.TranslatedImagePath is null
            ? null
            : assets.ResolveAbsolutePath(current.TranslatedImagePath);
        var loadedTranslatedImage = loadedTranslatedDisplayPath is null
            ? null
            : SafeLoad(loadedTranslatedDisplayPath, cancellationToken).Image;
        cancellationToken.ThrowIfCancellationRequested();
        return new DetailImageLoadResult(
            renderedPath,
            renderedAvailability,
            loadedOriginalDisplayPath,
            loadedTranslatedDisplayPath,
            loadedOriginalImage,
            loadedTranslatedImage,
            wasShowingTranslation && loadedTranslatedImage is not null);
    }

    private void ApplyImages(DetailImageLoadResult images)
    {
        reprocessImagePath = images.ReprocessImagePath;
        reprocessImageAvailability = images.ReprocessImageAvailability;
        originalDisplayPath = images.OriginalDisplayPath;
        translatedDisplayPath = images.TranslatedDisplayPath;
        originalImage = images.OriginalImage;
        translatedImage = images.TranslatedImage;
        displayedImage = images.ShowTranslation
            ? translatedImage
            : originalImage;
        OnPropertyChanged(nameof(OriginalImage));
        OnPropertyChanged(nameof(TranslatedImage));
        NotifyImageStateChanged();
    }

    private ScreenshotImageLoadResult SafeLoad(
        string path,
        CancellationToken cancellationToken)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = platform!.LoadImage(path);
            if (result.Image is { IsFrozen: false } image)
            {
                image.Freeze();
            }
            cancellationToken.ThrowIfCancellationRequested();
            return result.Image is { IsFrozen: true }
                ? result
                : new ScreenshotImageLoadResult(
                    null,
                    ScreenshotAssetAvailability.Unreadable);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return new ScreenshotImageLoadResult(
                null,
                ScreenshotAssetAvailability.Unreadable);
        }
    }

    private ScreenshotAssetAvailability SafeGetAvailability(string path)
    {
        try
        {
            return platform!.GetAssetAvailability(path);
        }
        catch
        {
            return ScreenshotAssetAvailability.Unreadable;
        }
    }

    private RefreshOperation BeginRefresh(CancellationToken cancellationToken)
    {
        var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        lock (refreshSynchronization)
        {
            activeRefreshCancellation?.Cancel();
            activeRefreshCancellation = linked;
            return new RefreshOperation(++refreshGeneration, linked);
        }
    }

    private bool IsCurrentRefresh(RefreshOperation operation) =>
        OwnsRefresh(operation)
        && !operation.Cancellation.IsCancellationRequested;

    private bool OwnsRefresh(RefreshOperation operation)
    {
        lock (refreshSynchronization)
        {
            return refreshGeneration == operation.Generation
                && ReferenceEquals(activeRefreshCancellation, operation.Cancellation);
        }
    }

    private void FinishRefresh(RefreshOperation operation)
    {
        lock (refreshSynchronization)
        {
            if (ReferenceEquals(activeRefreshCancellation, operation.Cancellation))
            {
                activeRefreshCancellation = null;
            }
        }
        operation.Cancellation.Dispose();
    }

    private void NotifyImageStateChanged()
    {
        OnPropertyChanged(nameof(DisplayedImage));
        OnPropertyChanged(nameof(HasImage));
        OnPropertyChanged(nameof(HasTranslatedImage));
        OnPropertyChanged(nameof(CanCopyImage));
        OnPropertyChanged(nameof(CanSaveAs));
        OnPropertyChanged(nameof(CanReveal));
        OnPropertyChanged(nameof(CanReprocess));
        OnPropertyChanged(nameof(AssetStatusText));
    }

    private string CreateSuggestedFileName()
    {
        var localCreated = record is null
            ? TimeZoneInfo.ConvertTime(timeProvider.GetUtcNow(), displayTimeZone)
            : TimeZoneInfo.ConvertTime(record.CreatedAtUtc, displayTimeZone);
        return $"VoxFlow-Screenshot-{localCreated:yyyyMMdd-HHmmss}-{Id}.png";
    }

    private static string DisplayText(string value) =>
        string.IsNullOrWhiteSpace(value)
            ? L10n.Localize("ScreenshotTextUnavailable")
            : value;

    private static string FormatFileSize(long bytes)
    {
        var culture = CultureInfo.CurrentUICulture;
        if (bytes < 1024)
        {
            return string.Format(culture, "{0:N0} B", bytes);
        }
        if (bytes < 1024 * 1024)
        {
            return string.Format(culture, "{0:0.#} KB", bytes / 1024D);
        }
        return string.Format(culture, "{0:0.#} MB", bytes / (1024D * 1024D));
    }

    private static string Format(string key, params object[] values) =>
        string.Format(
            CultureInfo.CurrentUICulture,
            L10n.Localize(key),
            values);

    private bool SetField<T>(
        ref T field,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private sealed record DetailRefreshResult(
        ScreenshotRecord? Record,
        DetailImageLoadResult? Images);

    private sealed record DetailImageLoadResult(
        string ReprocessImagePath,
        ScreenshotAssetAvailability ReprocessImageAvailability,
        string? OriginalDisplayPath,
        string? TranslatedDisplayPath,
        BitmapSource? OriginalImage,
        BitmapSource? TranslatedImage,
        bool ShowTranslation);

    private sealed record RefreshOperation(
        long Generation,
        CancellationTokenSource Cancellation);
}
