namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotResultState
{
    private readonly Dictionary<ScreenshotTransformOperation, OperationState> operations =
        Enum.GetValues<ScreenshotTransformOperation>()
            .ToDictionary(operation => operation, _ => new OperationState());

    public ScreenshotResultState(
        Guid runId,
        string screenshotId,
        string originalImagePath,
        string originalOcrText,
        IReadOnlyList<ScreenshotOcrLine> ocrLines,
        ScreenshotOcrOutcomeStatus ocrStatus = ScreenshotOcrOutcomeStatus.Succeeded)
    {
        if (runId == Guid.Empty) throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        ArgumentNullException.ThrowIfNull(originalOcrText);
        ArgumentNullException.ThrowIfNull(ocrLines);
        if (!Enum.IsDefined(ocrStatus)) throw new ArgumentOutOfRangeException(nameof(ocrStatus));
        RunId = runId;
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        OriginalImagePath = ScreenshotValueValidation.RequireManagedPath(
            originalImagePath,
            nameof(originalImagePath));
        OriginalOcrText = originalOcrText;
        OcrLines = Array.AsReadOnly(ocrLines.ToArray());
        OcrStatus = ocrStatus;
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public string OriginalImagePath { get; }

    public string OriginalOcrText { get; }

    public IReadOnlyList<ScreenshotOcrLine> OcrLines { get; }

    public ScreenshotOcrOutcomeStatus OcrStatus { get; }

    public string? RefinedText { get; private set; }

    public string? TranslatedText { get; private set; }

    public string? SummaryText { get; private set; }

    public bool Apply(ScreenshotTransformEvent @event)
    {
        ArgumentNullException.ThrowIfNull(@event);
        if (@event.RunId != RunId
            || !string.Equals(@event.ScreenshotId, ScreenshotId, StringComparison.Ordinal))
        {
            return false;
        }

        var state = operations[@event.Operation];
        switch (@event)
        {
            case ScreenshotTransformStarted:
                state.Status = ScreenshotTransformStatus.Running;
                state.PartialText = string.Empty;
                state.SafeMessage = null;
                break;
            case ScreenshotTransformPartial partial:
                if (state.Status != ScreenshotTransformStatus.Running) return false;
                state.PartialText = partial.Text;
                break;
            case ScreenshotTransformCompleted completed:
                if (state.Status != ScreenshotTransformStatus.Running) return false;
                SetCompletedValue(completed.Operation, completed.Text);
                state.Status = ScreenshotTransformStatus.Completed;
                state.PartialText = string.Empty;
                state.SafeMessage = null;
                break;
            case ScreenshotTransformFailed failed:
                if (state.Status != ScreenshotTransformStatus.Running) return false;
                state.Status = ScreenshotTransformStatus.Failed;
                state.PartialText = failed.PartialText;
                state.SafeMessage = failed.SafeMessage;
                break;
            case ScreenshotTransformCancelled cancelled:
                if (state.Status != ScreenshotTransformStatus.Running) return false;
                state.Status = string.IsNullOrWhiteSpace(cancelled.PartialText)
                    ? ScreenshotTransformStatus.Cancelled
                    : ScreenshotTransformStatus.PartiallyCompleted;
                state.PartialText = cancelled.PartialText;
                break;
            default:
                return false;
        }
        return true;
    }

    public ScreenshotTransformStatus GetStatus(ScreenshotTransformOperation operation) =>
        operations[RequireOperation(operation)].Status;

    public string GetPartial(ScreenshotTransformOperation operation) =>
        operations[RequireOperation(operation)].PartialText;

    public string? GetSafeMessage(ScreenshotTransformOperation operation) =>
        operations[RequireOperation(operation)].SafeMessage;

    public override string ToString() =>
        $"ScreenshotResultState {{ RunId = {RunId}, ScreenshotId = {ScreenshotId}, " +
        $"OcrCharacterCount = {OriginalOcrText.Length} }}";

    private void SetCompletedValue(ScreenshotTransformOperation operation, string text)
    {
        switch (operation)
        {
            case ScreenshotTransformOperation.Refinement:
                RefinedText = text;
                break;
            case ScreenshotTransformOperation.Translation:
                TranslatedText = text;
                break;
            case ScreenshotTransformOperation.Summary:
                SummaryText = text;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(operation));
        }
    }

    private static ScreenshotTransformOperation RequireOperation(
        ScreenshotTransformOperation operation) => Enum.IsDefined(operation)
            ? operation
            : throw new ArgumentOutOfRangeException(nameof(operation));

    private sealed class OperationState
    {
        public ScreenshotTransformStatus Status { get; set; } = ScreenshotTransformStatus.Idle;

        public string PartialText { get; set; } = string.Empty;

        public string? SafeMessage { get; set; }
    }
}
