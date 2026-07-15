using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotResultTab
{
    Original,
    Ocr,
    Refinement,
    Translation,
    Summary,
}

public enum ScreenshotResultPresentationKind
{
    None,
    Thumbnail,
    Expanded,
}

public sealed record ScreenshotResultPresentationRoute(
    ScreenshotResultPresentationKind Kind,
    ScreenshotResultTab InitialTab);

public static class ScreenshotResultPresentationPolicy
{
    public const double ThumbnailWidth = 260;
    public const double ThumbnailHeight = 150;
    public const double ExpandedWidth = 440;
    public const double ExpandedHeight = 560;
    public static readonly TimeSpan ThumbnailAutoDismissDelay = TimeSpan.FromSeconds(3);

    public static ScreenshotResultPresentationRoute For(ScreenshotCompletionKind completionKind) =>
        completionKind switch
        {
            ScreenshotCompletionKind.Complete => new(
                ScreenshotResultPresentationKind.Thumbnail,
                ScreenshotResultTab.Original),
            ScreenshotCompletionKind.TextRecognition => new(
                ScreenshotResultPresentationKind.Expanded,
                ScreenshotResultTab.Ocr),
            ScreenshotCompletionKind.Translation => new(
                ScreenshotResultPresentationKind.Expanded,
                ScreenshotResultTab.Translation),
            ScreenshotCompletionKind.Copy or ScreenshotCompletionKind.Download => new(
                ScreenshotResultPresentationKind.None,
                ScreenshotResultTab.Original),
            _ => throw new ArgumentOutOfRangeException(nameof(completionKind)),
        };
}

public static class ScreenshotResponsiveWindowLayout
{
    public static Rect BottomTrailing(
        Rect workArea,
        double preferredWidth,
        double preferredHeight,
        double margin)
    {
        var size = ClampSize(workArea, preferredWidth, preferredHeight, margin);
        return new Rect(
            Math.Max(workArea.Left, workArea.Right - size.Width - margin),
            Math.Max(workArea.Top, workArea.Bottom - size.Height - margin),
            size.Width,
            size.Height);
    }

    public static Rect Centered(
        Rect workArea,
        double preferredWidth,
        double preferredHeight,
        double margin)
    {
        var size = ClampSize(workArea, preferredWidth, preferredHeight, margin);
        return new Rect(
            workArea.Left + ((workArea.Width - size.Width) / 2),
            workArea.Top + ((workArea.Height - size.Height) / 2),
            size.Width,
            size.Height);
    }

    private static System.Windows.Size ClampSize(
        Rect workArea,
        double preferredWidth,
        double preferredHeight,
        double margin)
    {
        if (workArea.IsEmpty
            || workArea.Width <= 0
            || workArea.Height <= 0
            || !double.IsFinite(preferredWidth)
            || preferredWidth <= 0
            || !double.IsFinite(preferredHeight)
            || preferredHeight <= 0
            || !double.IsFinite(margin)
            || margin < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(workArea));
        }

        var availableWidth = Math.Max(1, workArea.Width - (margin * 2));
        var availableHeight = Math.Max(1, workArea.Height - (margin * 2));
        return new System.Windows.Size(
            Math.Min(preferredWidth, availableWidth),
            Math.Min(preferredHeight, availableHeight));
    }
}

public interface IScreenshotResultAssetResolver
{
    string ResolveAbsolutePath(string relativePath);
}

public sealed class ScreenshotAssetStoreResultResolver(IScreenshotAssetStore assets)
    : IScreenshotResultAssetResolver
{
    private readonly IScreenshotAssetStore assets = assets
        ?? throw new ArgumentNullException(nameof(assets));

    public string ResolveAbsolutePath(string relativePath) =>
        assets.ResolveAbsolutePath(relativePath);
}

public interface IScreenshotResultClipboard
{
    bool TrySetText(string text);

    Task<bool> TrySetImageAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Result-panel adapter for the shared screenshot clipboard transaction. The
/// source file is decoded on a worker and published by the dedicated STA gateway.
/// </summary>
public sealed class WpfScreenshotResultClipboard : IScreenshotResultClipboard
{
    private static readonly TimeSpan[] RetryDelays =
    [
        TimeSpan.Zero,
        TimeSpan.FromMilliseconds(25),
        TimeSpan.FromMilliseconds(50),
        TimeSpan.FromMilliseconds(100),
    ];
    private readonly IScreenshotImageClipboardWriter imageClipboard;

    public WpfScreenshotResultClipboard()
        : this(ReliableScreenshotImageClipboardWriter.Instance)
    {
    }

    public WpfScreenshotResultClipboard(IScreenshotImageClipboardWriter imageClipboard)
    {
        this.imageClipboard = imageClipboard
            ?? throw new ArgumentNullException(nameof(imageClipboard));
    }

    public bool TrySetText(string text)
    {
        if (string.IsNullOrWhiteSpace(text)
            || Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
        {
            return false;
        }

        return Retry(() => System.Windows.Clipboard.SetText(text));
    }

    public async Task<bool> TrySetImageAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(absoluteImagePath)
            || !Path.IsPathFullyQualified(absoluteImagePath))
        {
            return false;
        }

        try
        {
            var result = await imageClipboard.CopyImageAsync(
                absoluteImagePath,
                cancellationToken).ConfigureAwait(false);
            return result.Status == ScreenshotClipboardWriteStatus.Copied;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return false;
        }
    }

    private static bool Retry(Action operation)
    {
        foreach (var delay in RetryDelays)
        {
            if (delay > TimeSpan.Zero)
            {
                Thread.Sleep(delay);
            }
            try
            {
                operation();
                return true;
            }
            catch (ExternalException)
            {
            }
            catch
            {
                return false;
            }
        }
        return false;
    }
}

public interface IScreenshotResultTransformPersistence
{
    bool Persist(ScreenshotTransformCompleted completed);
}

public sealed class ScreenshotResultTransformPersistenceAdapter(
    ScreenshotTransformPersistenceCoordinator persistence)
    : IScreenshotResultTransformPersistence
{
    private readonly ScreenshotTransformPersistenceCoordinator persistence = persistence
        ?? throw new ArgumentNullException(nameof(persistence));

    public bool Persist(ScreenshotTransformCompleted completed) =>
        persistence.Persist(completed);
}

public interface IScreenshotResultAutoDismissToken : IDisposable
{
    void Cancel();
}

public interface IScreenshotResultAutoDismissScheduler
{
    IScreenshotResultAutoDismissToken Schedule(TimeSpan delay, Action action);
}

public sealed class DispatcherScreenshotResultAutoDismissScheduler(Dispatcher dispatcher)
    : IScreenshotResultAutoDismissScheduler
{
    private readonly Dispatcher dispatcher = dispatcher
        ?? throw new ArgumentNullException(nameof(dispatcher));

    public IScreenshotResultAutoDismissToken Schedule(TimeSpan delay, Action action)
    {
        if (delay <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(delay));
        ArgumentNullException.ThrowIfNull(action);
        var timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher)
        {
            Interval = delay,
        };
        EventHandler? tick = null;
        tick = (_, _) =>
        {
            timer.Stop();
            timer.Tick -= tick;
            action();
        };
        timer.Tick += tick;
        timer.Start();
        return new DispatcherAutoDismissToken(timer, tick);
    }

    private sealed class DispatcherAutoDismissToken(
        DispatcherTimer timer,
        EventHandler handler) : IScreenshotResultAutoDismissToken
    {
        private DispatcherTimer? timer = timer;
        private EventHandler? handler = handler;

        public void Cancel()
        {
            var currentTimer = Interlocked.Exchange(ref timer, null);
            var currentHandler = Interlocked.Exchange(ref handler, null);
            if (currentTimer is null)
            {
                return;
            }
            currentTimer.Stop();
            if (currentHandler is not null)
            {
                currentTimer.Tick -= currentHandler;
            }
        }

        public void Dispose() => Cancel();
    }
}
