using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

/// <summary>
/// Process-wide stale callback gates for capture work and the published result panel.
/// A new capture replaces only the capture gate; its cancellation does not invalidate
/// transforms that are still completing in the previous result panel.
/// </summary>
public sealed class ScreenshotRunRegistry :
    IScreenshotRunValidity,
    IScreenshotResultRunValidity
{
    private readonly object gate = new();
    private Guid currentCaptureRunId;
    private Guid currentResultRunId;

    public Guid Begin()
    {
        var runId = Guid.NewGuid();
        lock (gate)
        {
            currentCaptureRunId = runId;
        }
        return runId;
    }

    public bool IsCurrent(Guid runId)
    {
        if (runId == Guid.Empty)
        {
            return false;
        }
        lock (gate)
        {
            return runId == currentCaptureRunId;
        }
    }

    public bool PublishResult(Guid runId)
    {
        lock (gate)
        {
            if (runId == Guid.Empty || currentCaptureRunId != runId)
            {
                return false;
            }
            currentResultRunId = runId;
            return true;
        }
    }

    public bool IsResultCurrent(Guid runId)
    {
        if (runId == Guid.Empty)
        {
            return false;
        }
        lock (gate)
        {
            return runId == currentResultRunId;
        }
    }

    public bool Invalidate(Guid runId)
    {
        lock (gate)
        {
            if (runId == Guid.Empty || currentCaptureRunId != runId)
            {
                return false;
            }
            currentCaptureRunId = Guid.Empty;
            return true;
        }
    }

    public void InvalidateAll()
    {
        lock (gate)
        {
            currentCaptureRunId = Guid.Empty;
            currentResultRunId = Guid.Empty;
        }
    }
}
