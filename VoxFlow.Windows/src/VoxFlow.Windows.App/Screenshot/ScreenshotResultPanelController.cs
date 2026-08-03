using System.Windows;
using System.Windows.Threading;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Screenshot;

public interface IScreenshotResultPanelHost : IDisposable
{
    void Present(
        ScreenshotResultViewModel viewModel,
        ScreenshotCompletionKind completionKind);

    void CloseActive();
}

/// <summary>
/// Owns the thumbnail-to-expanded transition for one result. Application
/// composition supplies the view model; this controller owns only WPF window
/// lifetime and deterministic dismissal.
/// </summary>
public sealed class ScreenshotResultPanelController : IScreenshotResultPanelHost
{
    private readonly Func<Dispatcher, IScreenshotResultAutoDismissScheduler> schedulerFactory;
    private Window? activeWindow;
    private ScreenshotResultViewModel? activeViewModel;
    private bool disposed;

    public ScreenshotResultPanelController(
        Func<Dispatcher, IScreenshotResultAutoDismissScheduler>? schedulerFactory = null)
    {
        this.schedulerFactory = schedulerFactory
            ?? (dispatcher => new DispatcherScreenshotResultAutoDismissScheduler(dispatcher));
    }

    public bool IsVisible => activeWindow?.IsVisible == true;

    public void Present(
        ScreenshotResultViewModel viewModel,
        ScreenshotCompletionKind completionKind)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(viewModel);
        CloseActive();

        var route = ScreenshotResultPresentationPolicy.For(completionKind);
        if (route.Kind == ScreenshotResultPresentationKind.None)
        {
            viewModel.Dispose();
            return;
        }

        activeViewModel = viewModel;
        viewModel.SelectTab(route.InitialTab);
        if (route.Kind == ScreenshotResultPresentationKind.Thumbnail)
        {
            ShowThumbnail(viewModel);
        }
        else
        {
            ShowExpanded(viewModel);
        }
    }

    public void CloseActive()
    {
        var window = activeWindow;
        var viewModel = activeViewModel;
        activeWindow = null;
        activeViewModel = null;
        if (window is not null)
        {
            window.Close();
        }
        viewModel?.Dispose();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        CloseActive();
    }

    private void ShowThumbnail(ScreenshotResultViewModel viewModel)
    {
        var thumbnail = new ScreenshotResultThumbnailWindow(
            schedulerFactory(Dispatcher.CurrentDispatcher))
        {
            DataContext = viewModel,
        };
        PlaceBottomTrailing(thumbnail, 28);
        thumbnail.ExpandRequested += (_, _) =>
        {
            if (!ReferenceEquals(activeWindow, thumbnail))
            {
                return;
            }
            activeWindow = null;
            thumbnail.Close();
            ShowExpanded(viewModel);
        };
        thumbnail.Closed += (_, _) =>
        {
            if (!ReferenceEquals(activeWindow, thumbnail))
            {
                return;
            }
            activeWindow = null;
            activeViewModel = null;
            viewModel.Dispose();
        };
        activeWindow = thumbnail;
        thumbnail.Show();
    }

    private void ShowExpanded(ScreenshotResultViewModel viewModel)
    {
        var expanded = new ScreenshotResultWindow
        {
            DataContext = viewModel,
        };
        expanded.ApplyResponsiveBounds(SystemParameters.WorkArea);
        expanded.Closed += (_, _) =>
        {
            if (!ReferenceEquals(activeWindow, expanded))
            {
                return;
            }
            activeWindow = null;
            activeViewModel = null;
            viewModel.Dispose();
        };
        activeWindow = expanded;
        expanded.Show();
    }

    private static void PlaceBottomTrailing(Window window, double margin)
    {
        var workArea = SystemParameters.WorkArea;
        window.Left = Math.Max(workArea.Left, workArea.Right - window.Width - margin);
        window.Top = Math.Max(workArea.Top, workArea.Bottom - window.Height - margin);
    }
}
