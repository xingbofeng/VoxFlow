using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain.Screenshots;

public enum ScreenshotSessionPhase
{
    Created,
    Freezing,
    Selecting,
    Annotating,
    Processing,
    Completed,
    Cancelled,
    Failed,
}

public enum ScreenshotCompletionKind
{
    Complete,
    TextRecognition,
    Translation,
    Copy,
    Download,
}

public sealed record ScreenshotResult
{
    [JsonConstructor]
    public ScreenshotResult(
        Guid screenshotId,
        Guid runId,
        ScreenshotCompletionKind completionKind,
        PixelSize imageSize)
    {
        if (screenshotId == Guid.Empty)
        {
            throw new ArgumentException("A screenshot identifier is required.", nameof(screenshotId));
        }
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A run identifier is required.", nameof(runId));
        }
        if (!Enum.IsDefined(completionKind))
        {
            throw new ArgumentOutOfRangeException(nameof(completionKind));
        }

        ScreenshotId = screenshotId;
        RunId = runId;
        CompletionKind = completionKind;
        ImageSize = imageSize;
    }

    public Guid ScreenshotId { get; }

    public Guid RunId { get; }

    public ScreenshotCompletionKind CompletionKind { get; }

    public PixelSize ImageSize { get; }
}

public sealed class ScreenshotSessionState
{
    private ScreenshotSessionState(
        Guid runId,
        ScreenshotSessionPhase phase,
        ScreenshotResult? result,
        string? failureCode)
    {
        RunId = runId;
        Phase = phase;
        Result = result;
        FailureCode = failureCode;
    }

    public Guid RunId { get; }

    public ScreenshotSessionPhase Phase { get; }

    public ScreenshotResult? Result { get; }

    public string? FailureCode { get; }

    public bool IsTerminal => Phase is
        ScreenshotSessionPhase.Completed
        or ScreenshotSessionPhase.Cancelled
        or ScreenshotSessionPhase.Failed;

    public static ScreenshotSessionState Create(Guid runId)
    {
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A non-empty run identifier is required.", nameof(runId));
        }

        return new ScreenshotSessionState(
            runId,
            ScreenshotSessionPhase.Created,
            result: null,
            failureCode: null);
    }

    public ScreenshotSessionState StartFreezing() =>
        Transition(ScreenshotSessionPhase.Created, ScreenshotSessionPhase.Freezing);

    public ScreenshotSessionState BeginSelection() =>
        Transition(ScreenshotSessionPhase.Freezing, ScreenshotSessionPhase.Selecting);

    public ScreenshotSessionState BeginAnnotation() =>
        Transition(ScreenshotSessionPhase.Selecting, ScreenshotSessionPhase.Annotating);

    public ScreenshotSessionState BeginProcessing()
    {
        if (Phase is not (ScreenshotSessionPhase.Selecting or ScreenshotSessionPhase.Annotating))
        {
            throw InvalidTransition(ScreenshotSessionPhase.Processing);
        }

        return New(ScreenshotSessionPhase.Processing);
    }

    public ScreenshotSessionState Complete(ScreenshotResult result)
    {
        ArgumentNullException.ThrowIfNull(result);
        if (Phase != ScreenshotSessionPhase.Processing)
        {
            throw InvalidTransition(ScreenshotSessionPhase.Completed);
        }
        if (result.RunId != RunId)
        {
            throw new ArgumentException("The result belongs to another screenshot run.", nameof(result));
        }

        return new ScreenshotSessionState(
            RunId,
            ScreenshotSessionPhase.Completed,
            result,
            failureCode: null);
    }

    public ScreenshotSessionState Cancel()
    {
        EnsureActive();
        return New(ScreenshotSessionPhase.Cancelled);
    }

    public ScreenshotSessionState Fail(string failureCode)
    {
        EnsureActive();
        ArgumentException.ThrowIfNullOrWhiteSpace(failureCode);
        if (failureCode.Contains('\r', StringComparison.Ordinal)
            || failureCode.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException("A failure code must be a single line.", nameof(failureCode));
        }

        return new ScreenshotSessionState(
            RunId,
            ScreenshotSessionPhase.Failed,
            result: null,
            failureCode.Trim());
    }

    public bool TryApply(
        Guid callbackRunId,
        Func<ScreenshotSessionState, ScreenshotSessionState> transition,
        out ScreenshotSessionState next)
    {
        ArgumentNullException.ThrowIfNull(transition);
        if (callbackRunId == Guid.Empty || callbackRunId != RunId || IsTerminal)
        {
            next = this;
            return false;
        }

        next = transition(this)
            ?? throw new InvalidOperationException("A screenshot transition cannot return null.");
        if (next.RunId != RunId)
        {
            throw new InvalidOperationException("A screenshot transition cannot change its run identifier.");
        }
        return true;
    }

    private ScreenshotSessionState Transition(
        ScreenshotSessionPhase expected,
        ScreenshotSessionPhase next)
    {
        if (Phase != expected)
        {
            throw InvalidTransition(next);
        }
        return New(next);
    }

    private ScreenshotSessionState New(ScreenshotSessionPhase phase) => new(
        RunId,
        phase,
        result: null,
        failureCode: null);

    private void EnsureActive()
    {
        if (IsTerminal)
        {
            throw InvalidTransition(Phase);
        }
    }

    private InvalidOperationException InvalidTransition(ScreenshotSessionPhase next) => new(
        $"Screenshot run {RunId:N} cannot transition from {Phase} to {next}.");
}
