using System.Security.Cryptography;
using System.Text;

namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotTransformRequest
{
    public ScreenshotTransformRequest(
        Guid runId,
        string screenshotId,
        string sourceText,
        ScreenshotTransformOperation operation,
        string? inputRevision = null)
    {
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceText);
        if (!Enum.IsDefined(operation))
        {
            throw new ArgumentOutOfRangeException(nameof(operation));
        }
        RunId = runId;
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        SourceText = sourceText;
        Operation = operation;
        var revision = string.IsNullOrWhiteSpace(inputRevision)
            ? "text-only"
            : inputRevision.Trim();
        CacheKey = ComputeHash(
            ScreenshotId + "\n" + operation + "\n" + revision + "\n" + sourceText);
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public string SourceText { get; }

    public ScreenshotTransformOperation Operation { get; }

    public string CacheKey { get; }

    public override string ToString() =>
        $"ScreenshotTransformRequest {{ RunId = {RunId}, ScreenshotId = {ScreenshotId}, " +
        $"Operation = {Operation}, CharacterCount = {SourceText.Length} }}";

    private static string ComputeHash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}

public enum ScreenshotTransformStatus
{
    Idle,
    Running,
    Completed,
    Failed,
    Cancelled,
    PartiallyCompleted,
}

public abstract class ScreenshotTransformEvent
{
    protected ScreenshotTransformEvent(
        Guid runId,
        string screenshotId,
        ScreenshotTransformOperation operation)
    {
        if (runId == Guid.Empty) throw new ArgumentException("A non-empty run ID is required.", nameof(runId));
        if (!Enum.IsDefined(operation)) throw new ArgumentOutOfRangeException(nameof(operation));
        RunId = runId;
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        Operation = operation;
    }

    public Guid RunId { get; }

    public string ScreenshotId { get; }

    public ScreenshotTransformOperation Operation { get; }

    public override string ToString() =>
        $"{GetType().Name} {{ RunId = {RunId}, ScreenshotId = {ScreenshotId}, Operation = {Operation} }}";
}

public sealed class ScreenshotTransformStarted(
    Guid runId,
    string screenshotId,
    ScreenshotTransformOperation operation)
    : ScreenshotTransformEvent(runId, screenshotId, operation)
{
}

public sealed class ScreenshotTransformPartial : ScreenshotTransformEvent
{
    public ScreenshotTransformPartial(
        Guid runId,
        string screenshotId,
        ScreenshotTransformOperation operation,
        string text)
        : base(runId, screenshotId, operation)
    {
        ArgumentNullException.ThrowIfNull(text);
        Text = text;
    }

    public string Text { get; }

    public override string ToString() => base.ToString()[..^2] + $", CharacterCount = {Text.Length} }}";
}

public sealed class ScreenshotTransformCompleted : ScreenshotTransformEvent
{
    public ScreenshotTransformCompleted(
        Guid runId,
        string screenshotId,
        ScreenshotTransformOperation operation,
        string text,
        bool fromCache)
        : base(runId, screenshotId, operation)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        Text = text;
        FromCache = fromCache;
    }

    public string Text { get; }

    public bool FromCache { get; }

    public override string ToString() => base.ToString()[..^2] +
        $", CharacterCount = {Text.Length}, FromCache = {FromCache} }}";
}

public sealed class ScreenshotTransformCancelled : ScreenshotTransformEvent
{
    public ScreenshotTransformCancelled(
        Guid runId,
        string screenshotId,
        ScreenshotTransformOperation operation,
        string partialText)
        : base(runId, screenshotId, operation)
    {
        ArgumentNullException.ThrowIfNull(partialText);
        PartialText = partialText;
    }

    public string PartialText { get; }

    public override string ToString() => base.ToString()[..^2] +
        $", PartialCharacterCount = {PartialText.Length} }}";
}

public sealed class ScreenshotTransformFailed : ScreenshotTransformEvent
{
    public ScreenshotTransformFailed(
        Guid runId,
        string screenshotId,
        ScreenshotTransformOperation operation,
        string safeMessage,
        string partialText)
        : base(runId, screenshotId, operation)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(safeMessage);
        ArgumentNullException.ThrowIfNull(partialText);
        SafeMessage = safeMessage;
        PartialText = partialText;
    }

    public string SafeMessage { get; }

    public string PartialText { get; }

    public override string ToString() => base.ToString()[..^2] +
        $", PartialCharacterCount = {PartialText.Length} }}";
}

public interface IScreenshotTransformStreamingService
{
    IAsyncEnumerable<ScreenshotTransformEvent> TransformAsync(
        ScreenshotTransformRequest request,
        CancellationToken cancellationToken);
}

public interface IScreenshotResultRunValidity
{
    bool IsResultCurrent(Guid runId);
}

public interface IScreenshotTransformCacheInvalidator
{
    int Invalidate(string screenshotId);
}

public interface IScreenshotTransformCache : IScreenshotTransformCacheInvalidator
{
    bool TryGet(ScreenshotTransformRequest request, out string text);

    void Store(ScreenshotTransformRequest request, string text);
}
