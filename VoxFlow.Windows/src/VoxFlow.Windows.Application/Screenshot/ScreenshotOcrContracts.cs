namespace VoxFlow.Windows.Application.Screenshot;

public readonly record struct ScreenshotPixelBounds
{
    public ScreenshotPixelBounds(int x, int y, int width, int height)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(x);
        ArgumentOutOfRangeException.ThrowIfNegative(y);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(width);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(height);
        X = x;
        Y = y;
        Width = width;
        Height = height;
    }

    public int X { get; }

    public int Y { get; }

    public int Width { get; }

    public int Height { get; }
}

public sealed class ScreenshotOcrLine
{
    public ScreenshotOcrLine(
        string text,
        double confidence,
        ScreenshotPixelBounds bounds)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        if (!double.IsFinite(confidence) || confidence is < 0 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(confidence));
        }
        Text = text.Trim();
        Confidence = confidence;
        Bounds = bounds;
    }

    public string Text { get; }

    public double Confidence { get; }

    public ScreenshotPixelBounds Bounds { get; }

    public override string ToString() =>
        $"ScreenshotOcrLine {{ CharacterCount = {Text.Length}, Confidence = {Confidence:0.##}, " +
        $"Bounds = {Bounds.Width}x{Bounds.Height} }}";
}

public enum ScreenshotOcrEngineStatus
{
    Succeeded,
    RuntimeUnavailable,
    InputUnavailable,
    Empty,
    TimedOut,
    Failed,
}

public sealed class ScreenshotOcrEngineRequest
{
    public ScreenshotOcrEngineRequest(string imagePath, string? currentLanguage)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(imagePath);
        if (!Path.IsPathFullyQualified(imagePath))
        {
            throw new ArgumentException("An absolute OCR image path is required.", nameof(imagePath));
        }
        ImagePath = Path.GetFullPath(imagePath);
        CurrentLanguage = string.IsNullOrWhiteSpace(currentLanguage)
            ? null
            : currentLanguage.Trim();
    }

    public string ImagePath { get; }

    public string? CurrentLanguage { get; }

    public override string ToString() =>
        $"ScreenshotOcrEngineRequest {{ HasLanguage = {CurrentLanguage is not null} }}";
}

public sealed class ScreenshotOcrEngineResult
{
    public ScreenshotOcrEngineResult(
        ScreenshotOcrEngineStatus status,
        string? text = null,
        IReadOnlyList<ScreenshotOcrLine>? lines = null)
    {
        if (!Enum.IsDefined(status))
        {
            throw new ArgumentOutOfRangeException(nameof(status));
        }
        var resolvedLines = lines?.ToArray() ?? [];
        if (status == ScreenshotOcrEngineStatus.Succeeded
            && string.IsNullOrWhiteSpace(text))
        {
            throw new ArgumentException("Successful OCR requires text.", nameof(text));
        }
        if (status != ScreenshotOcrEngineStatus.Succeeded
            && (!string.IsNullOrEmpty(text) || resolvedLines.Length != 0))
        {
            throw new ArgumentException("Unsuccessful OCR cannot expose partial content.", nameof(text));
        }

        Status = status;
        Text = text?.Trim() ?? string.Empty;
        Lines = Array.AsReadOnly(resolvedLines);
    }

    public ScreenshotOcrEngineStatus Status { get; }

    public string Text { get; }

    public IReadOnlyList<ScreenshotOcrLine> Lines { get; }

    public override string ToString() =>
        $"ScreenshotOcrEngineResult {{ Status = {Status}, CharacterCount = {Text.Length}, " +
        $"LineCount = {Lines.Count} }}";
}

public interface IScreenshotOcrEngine
{
    Task<ScreenshotOcrEngineResult> RecognizeAsync(
        ScreenshotOcrEngineRequest request,
        CancellationToken cancellationToken);
}

public interface IScreenshotOcrService
{
    Task<ScreenshotOcrOutcome> RecognizeAsync(
        ScreenshotOcrRequest request,
        CancellationToken cancellationToken);
}

public interface IScreenshotRunValidity
{
    bool IsCurrent(Guid runId);
}

public sealed class ScreenshotOcrRequest
{
    public ScreenshotOcrRequest(
        Guid runId,
        string screenshotId,
        string originalImagePath,
        string ocrImagePath,
        string? currentLanguage)
    {
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        }
        RunId = runId;
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        OriginalImagePath = ScreenshotValueValidation.RequireManagedPath(
            originalImagePath,
            nameof(originalImagePath));
        ArgumentException.ThrowIfNullOrWhiteSpace(ocrImagePath);
        if (!Path.IsPathFullyQualified(ocrImagePath))
        {
            throw new ArgumentException("An absolute OCR image path is required.", nameof(ocrImagePath));
        }
        OcrImagePath = Path.GetFullPath(ocrImagePath);
        CurrentLanguage = string.IsNullOrWhiteSpace(currentLanguage)
            ? null
            : currentLanguage.Trim();
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public string OriginalImagePath { get; }

    public string OcrImagePath { get; }

    public string? CurrentLanguage { get; }

    public override string ToString() =>
        $"ScreenshotOcrRequest {{ RunId = {RunId}, ScreenshotId = {ScreenshotId} }}";
}

public enum ScreenshotOcrOutcomeStatus
{
    Succeeded,
    RuntimeUnavailable,
    InputUnavailable,
    Empty,
    TimedOut,
    Failed,
    Cancelled,
    Stale,
}

public sealed class ScreenshotOcrOutcome
{
    public ScreenshotOcrOutcome(
        Guid runId,
        string screenshotId,
        string originalImagePath,
        ScreenshotOcrOutcomeStatus status,
        string? text = null,
        IReadOnlyList<ScreenshotOcrLine>? lines = null)
    {
        if (runId == Guid.Empty) throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        if (!Enum.IsDefined(status)) throw new ArgumentOutOfRangeException(nameof(status));
        RunId = runId;
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        OriginalImagePath = ScreenshotValueValidation.RequireManagedPath(
            originalImagePath,
            nameof(originalImagePath));
        var resolvedLines = lines?.ToArray() ?? [];
        if (status == ScreenshotOcrOutcomeStatus.Succeeded
            && string.IsNullOrWhiteSpace(text))
        {
            throw new ArgumentException("Successful OCR requires text.", nameof(text));
        }
        if (status != ScreenshotOcrOutcomeStatus.Succeeded
            && (!string.IsNullOrEmpty(text) || resolvedLines.Length != 0))
        {
            throw new ArgumentException("A terminal OCR failure cannot expose text.", nameof(text));
        }
        Status = status;
        Text = text?.Trim() ?? string.Empty;
        Lines = Array.AsReadOnly(resolvedLines);
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public string OriginalImagePath { get; }

    public ScreenshotOcrOutcomeStatus Status { get; }

    public string Text { get; }

    public IReadOnlyList<ScreenshotOcrLine> Lines { get; }

    public override string ToString() =>
        $"ScreenshotOcrOutcome {{ RunId = {RunId}, ScreenshotId = {ScreenshotId}, " +
        $"Status = {Status}, CharacterCount = {Text.Length}, LineCount = {Lines.Count} }}";
}
