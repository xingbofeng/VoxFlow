namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotCompletionRequest
{
    public ScreenshotCompletionRequest(
        Guid runId,
        string screenshotId,
        ScreenshotAssetWriteRequest assets,
        int widthPixels,
        int heightPixels,
        DateTimeOffset createdAtUtc,
        string? currentLanguage,
        string? sourceDisplayId = null,
        string? sourceWindowTitle = null,
        string? initialTranslatedText = null)
    {
        if (runId == Guid.Empty) throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        ArgumentNullException.ThrowIfNull(assets);
        var id = ScreenshotValueValidation.RequireId(screenshotId);
        if (!string.Equals(id, assets.ScreenshotId, StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "The asset request must use the same screenshot ID.",
                nameof(assets));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(widthPixels);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(heightPixels);
        ScreenshotValueValidation.RequireUtc(createdAtUtc, nameof(createdAtUtc));
        RunId = runId;
        ScreenshotId = id;
        Assets = assets;
        WidthPixels = widthPixels;
        HeightPixels = heightPixels;
        CreatedAtUtc = createdAtUtc;
        CurrentLanguage = string.IsNullOrWhiteSpace(currentLanguage)
            ? null
            : currentLanguage.Trim();
        SourceDisplayId = ScreenshotValueValidation.OptionalText(sourceDisplayId);
        SourceWindowTitle = ScreenshotValueValidation.OptionalText(sourceWindowTitle);
        InitialTranslatedText = ScreenshotValueValidation.OptionalText(initialTranslatedText);
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public ScreenshotAssetWriteRequest Assets { get; }

    public int WidthPixels { get; }

    public int HeightPixels { get; }

    public DateTimeOffset CreatedAtUtc { get; }

    public string? CurrentLanguage { get; }

    public string? SourceDisplayId { get; }

    public string? SourceWindowTitle { get; }

    public string? InitialTranslatedText { get; }

    public override string ToString() =>
        $"ScreenshotCompletionRequest {{ RunId = {RunId}, ScreenshotId = {ScreenshotId}, " +
        $"Size = {WidthPixels}x{HeightPixels} }}";
}

public enum ScreenshotCompletionStatus
{
    Succeeded,
    Cancelled,
    Stale,
    AssetFailed,
    PersistenceFailed,
}

public sealed class ScreenshotCompletionResult
{
    public ScreenshotCompletionResult(
        Guid runId,
        string screenshotId,
        ScreenshotCompletionStatus status,
        ScreenshotRecord? record = null,
        ScreenshotOcrOutcome? ocrOutcome = null,
        string? safeErrorCode = null)
    {
        if (runId == Guid.Empty) throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        if (!Enum.IsDefined(status)) throw new ArgumentOutOfRangeException(nameof(status));
        if (status == ScreenshotCompletionStatus.Succeeded && record is null)
        {
            throw new ArgumentException("Successful completion requires a record.", nameof(record));
        }
        if (status != ScreenshotCompletionStatus.Succeeded && record is not null)
        {
            throw new ArgumentException("Failed completion cannot publish a record.", nameof(record));
        }
        RunId = runId;
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        Status = status;
        Record = record;
        OcrOutcome = ocrOutcome;
        SafeErrorCode = ScreenshotValueValidation.OptionalText(safeErrorCode);
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public ScreenshotCompletionStatus Status { get; }

    public ScreenshotRecord? Record { get; }

    public ScreenshotOcrOutcome? OcrOutcome { get; }

    public string? SafeErrorCode { get; }

    public override string ToString() =>
        $"ScreenshotCompletionResult {{ RunId = {RunId}, ScreenshotId = {ScreenshotId}, " +
        $"Status = {Status}, OcrStatus = {OcrOutcome?.Status} }}";
}

public interface IScreenshotCompletionService
{
    Task<ScreenshotCompletionResult> CompleteAsync(
        ScreenshotCompletionRequest request,
        CancellationToken cancellationToken);
}

public sealed class ScreenshotCompletionService : IScreenshotCompletionService
{
    private readonly IScreenshotAssetStore assets;
    private readonly IScreenshotOcrService ocr;
    private readonly IScreenshotRecordRepository records;
    private readonly IScreenshotRunValidity runValidity;

    public ScreenshotCompletionService(
        IScreenshotAssetStore assets,
        IScreenshotOcrService ocr,
        IScreenshotRecordRepository records,
        IScreenshotRunValidity runValidity)
    {
        this.assets = assets ?? throw new ArgumentNullException(nameof(assets));
        this.ocr = ocr ?? throw new ArgumentNullException(nameof(ocr));
        this.records = records ?? throw new ArgumentNullException(nameof(records));
        this.runValidity = runValidity ?? throw new ArgumentNullException(nameof(runValidity));
    }

    public async Task<ScreenshotCompletionResult> CompleteAsync(
        ScreenshotCompletionRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!runValidity.IsCurrent(request.RunId))
        {
            return Result(request, ScreenshotCompletionStatus.Stale);
        }
        if (cancellationToken.IsCancellationRequested)
        {
            return Result(request, ScreenshotCompletionStatus.Cancelled);
        }

        ScreenshotAssetSet storedAssets;
        try
        {
            storedAssets = await assets.SaveAsync(request.Assets, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return Result(request, ScreenshotCompletionStatus.Cancelled);
        }
        catch
        {
            return Result(
                request,
                ScreenshotCompletionStatus.AssetFailed,
                safeErrorCode: "screenshot.persistence.asset_failed");
        }

        if (!runValidity.IsCurrent(request.RunId))
        {
            await CompensateAsync(storedAssets).ConfigureAwait(false);
            return Result(request, ScreenshotCompletionStatus.Stale);
        }

        ScreenshotOcrOutcome ocrOutcome;
        try
        {
            ocrOutcome = await ocr.RecognizeAsync(
                new ScreenshotOcrRequest(
                    request.RunId,
                    request.ScreenshotId,
                    storedAssets.OriginalImagePath,
                    assets.ResolveAbsolutePath(storedAssets.RenderedImagePath),
                    request.CurrentLanguage),
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await CompensateAsync(storedAssets).ConfigureAwait(false);
            return Result(request, ScreenshotCompletionStatus.Cancelled);
        }
        catch
        {
            ocrOutcome = new ScreenshotOcrOutcome(
                request.RunId,
                request.ScreenshotId,
                storedAssets.OriginalImagePath,
                ScreenshotOcrOutcomeStatus.Failed);
        }

        if (ocrOutcome.Status is ScreenshotOcrOutcomeStatus.Cancelled
            or ScreenshotOcrOutcomeStatus.Stale)
        {
            await CompensateAsync(storedAssets).ConfigureAwait(false);
            return Result(
                request,
                ocrOutcome.Status == ScreenshotOcrOutcomeStatus.Stale
                    ? ScreenshotCompletionStatus.Stale
                    : ScreenshotCompletionStatus.Cancelled,
                ocrOutcome);
        }
        if (!runValidity.IsCurrent(request.RunId))
        {
            await CompensateAsync(storedAssets).ConfigureAwait(false);
            return Result(request, ScreenshotCompletionStatus.Stale, ocrOutcome);
        }

        var record = new ScreenshotRecord(
            request.ScreenshotId,
            storedAssets.OriginalImagePath,
            storedAssets.RenderedImagePath,
            storedAssets.ThumbnailPath,
            request.WidthPixels,
            request.HeightPixels,
            storedAssets.RenderedFileSizeBytes,
            ocrOutcome.Status == ScreenshotOcrOutcomeStatus.Succeeded
                ? ocrOutcome.Text
                : string.Empty,
            request.CreatedAtUtc,
            translatedImagePath: storedAssets.TranslatedImagePath,
            translatedText: request.InitialTranslatedText,
            sourceDisplayId: request.SourceDisplayId,
            sourceWindowTitle: request.SourceWindowTitle);
        try
        {
            records.Add(record);
        }
        catch
        {
            await CompensateAsync(storedAssets).ConfigureAwait(false);
            return Result(
                request,
                ScreenshotCompletionStatus.PersistenceFailed,
                ocrOutcome,
                "screenshot.persistence.record_failed");
        }

        return new ScreenshotCompletionResult(
            request.RunId,
            request.ScreenshotId,
            ScreenshotCompletionStatus.Succeeded,
            record,
            ocrOutcome);
    }

    private async Task CompensateAsync(ScreenshotAssetSet storedAssets)
    {
        try
        {
            await assets.DeleteAsync(storedAssets, CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // A later orphan cleanup retries compensation; never mask the original outcome.
        }
    }

    private static ScreenshotCompletionResult Result(
        ScreenshotCompletionRequest request,
        ScreenshotCompletionStatus status,
        ScreenshotOcrOutcome? ocrOutcome = null,
        string? safeErrorCode = null) => new(
            request.RunId,
            request.ScreenshotId,
            status,
            ocrOutcome: ocrOutcome,
            safeErrorCode: safeErrorCode);
}

public sealed class ScreenshotRecordUpdatedEventArgs(string screenshotId) : EventArgs
{
    public string ScreenshotId { get; } = ScreenshotValueValidation.RequireId(screenshotId);
}

public sealed class ScreenshotTransformPersistenceCoordinator
{
    private readonly IScreenshotRecordRepository records;
    private readonly TimeProvider timeProvider;
    private readonly IScreenshotResultRunValidity resultRunValidity;

    public ScreenshotTransformPersistenceCoordinator(
        IScreenshotRecordRepository records,
        TimeProvider timeProvider,
        IScreenshotResultRunValidity resultRunValidity)
    {
        this.records = records ?? throw new ArgumentNullException(nameof(records));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        this.resultRunValidity = resultRunValidity
            ?? throw new ArgumentNullException(nameof(resultRunValidity));
    }

    public event EventHandler<ScreenshotRecordUpdatedEventArgs>? RecordUpdated;

    public bool Persist(
        ScreenshotTransformCompleted completed,
        string? translatedImagePath = null)
    {
        ArgumentNullException.ThrowIfNull(completed);
        if (!resultRunValidity.IsResultCurrent(completed.RunId))
        {
            return false;
        }
        bool updated;
        try
        {
            updated = records.UpdateTransform(
                completed.ScreenshotId,
                completed.Operation,
                completed.Text,
                timeProvider.GetUtcNow(),
                translatedImagePath);
        }
        catch
        {
            return false;
        }
        if (!updated)
        {
            return false;
        }

        RecordUpdated?.Invoke(
            this,
            new ScreenshotRecordUpdatedEventArgs(completed.ScreenshotId));
        return true;
    }
}
