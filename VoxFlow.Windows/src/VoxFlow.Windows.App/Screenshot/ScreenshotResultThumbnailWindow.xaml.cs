using System.Windows;
using System.Windows.Input;

namespace VoxFlow.Windows.App.Screenshot;

public partial class ScreenshotResultThumbnailWindow : Window
{
    private readonly IScreenshotResultAutoDismissScheduler scheduler;
    private IScreenshotResultAutoDismissToken? autoDismiss;

    public ScreenshotResultThumbnailWindow()
        : this(new DispatcherScreenshotResultAutoDismissScheduler(
            System.Windows.Threading.Dispatcher.CurrentDispatcher))
    {
    }

    public ScreenshotResultThumbnailWindow(IScreenshotResultAutoDismissScheduler scheduler)
    {
        this.scheduler = scheduler ?? throw new ArgumentNullException(nameof(scheduler));
        InitializeComponent();
        Closed += OnClosed;
    }

    public event EventHandler? ExpandRequested;

    public void BeginAutoDismiss()
    {
        autoDismiss?.Cancel();
        autoDismiss?.Dispose();
        autoDismiss = scheduler.Schedule(
            ScreenshotResultPresentationPolicy.ThumbnailAutoDismissDelay,
            Close);
    }

    public void OpenResult()
    {
        CancelAutoDismiss();
        ExpandRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnContentRendered(object? sender, EventArgs eventArgs) => BeginAutoDismiss();

    private void OnOpen(object sender, RoutedEventArgs eventArgs) => OpenResult();

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (eventArgs.Key != Key.Escape)
        {
            return;
        }
        eventArgs.Handled = true;
        Close();
    }

    private void OnClosed(object? sender, EventArgs eventArgs) => CancelAutoDismiss();

    private void CancelAutoDismiss()
    {
        autoDismiss?.Cancel();
        autoDismiss?.Dispose();
        autoDismiss = null;
    }
}
