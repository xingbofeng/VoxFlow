namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotOcrOrchestrator : IScreenshotOcrService
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(25);

    private readonly IScreenshotOcrEngine engine;
    private readonly IScreenshotRunValidity runValidity;
    private readonly TimeSpan timeout;

    public ScreenshotOcrOrchestrator(
        IScreenshotOcrEngine engine,
        IScreenshotRunValidity runValidity,
        TimeSpan? timeout = null)
    {
        this.engine = engine ?? throw new ArgumentNullException(nameof(engine));
        this.runValidity = runValidity ?? throw new ArgumentNullException(nameof(runValidity));
        this.timeout = timeout ?? DefaultTimeout;
        if (this.timeout <= TimeSpan.Zero || this.timeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }
    }

    public async Task<ScreenshotOcrOutcome> RecognizeAsync(
        ScreenshotOcrRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!runValidity.IsCurrent(request.RunId))
        {
            return Outcome(request, ScreenshotOcrOutcomeStatus.Stale);
        }
        if (cancellationToken.IsCancellationRequested)
        {
            return Outcome(request, ScreenshotOcrOutcomeStatus.Cancelled);
        }

        using var deadline = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            deadline.Token);
        try
        {
            var result = await engine.RecognizeAsync(
                new ScreenshotOcrEngineRequest(request.OcrImagePath, request.CurrentLanguage),
                linked.Token).ConfigureAwait(false);
            if (!runValidity.IsCurrent(request.RunId))
            {
                return Outcome(request, ScreenshotOcrOutcomeStatus.Stale);
            }

            return result.Status switch
            {
                ScreenshotOcrEngineStatus.Succeeded => new ScreenshotOcrOutcome(
                    request.RunId,
                    request.ScreenshotId,
                    request.OriginalImagePath,
                    ScreenshotOcrOutcomeStatus.Succeeded,
                    result.Text,
                    result.Lines),
                ScreenshotOcrEngineStatus.RuntimeUnavailable =>
                    Outcome(request, ScreenshotOcrOutcomeStatus.RuntimeUnavailable),
                ScreenshotOcrEngineStatus.InputUnavailable =>
                    Outcome(request, ScreenshotOcrOutcomeStatus.InputUnavailable),
                ScreenshotOcrEngineStatus.Empty =>
                    Outcome(request, ScreenshotOcrOutcomeStatus.Empty),
                ScreenshotOcrEngineStatus.TimedOut =>
                    Outcome(request, ScreenshotOcrOutcomeStatus.TimedOut),
                _ => Outcome(request, ScreenshotOcrOutcomeStatus.Failed),
            };
        }
        catch (OperationCanceledException) when (!runValidity.IsCurrent(request.RunId))
        {
            return Outcome(request, ScreenshotOcrOutcomeStatus.Stale);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return Outcome(request, ScreenshotOcrOutcomeStatus.Cancelled);
        }
        catch (OperationCanceledException) when (deadline.IsCancellationRequested)
        {
            return Outcome(request, ScreenshotOcrOutcomeStatus.TimedOut);
        }
        catch
        {
            return runValidity.IsCurrent(request.RunId)
                ? Outcome(request, ScreenshotOcrOutcomeStatus.Failed)
                : Outcome(request, ScreenshotOcrOutcomeStatus.Stale);
        }
    }

    private static ScreenshotOcrOutcome Outcome(
        ScreenshotOcrRequest request,
        ScreenshotOcrOutcomeStatus status) => new(
            request.RunId,
            request.ScreenshotId,
            request.OriginalImagePath,
            status);
}
