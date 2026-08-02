using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.SelectionTransform;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.App.Selection;

/// <summary>
/// The real Windows entry point for direct translation/summary. It freezes the
/// foreground target before a panel exists, uses UIA-first selection capture,
/// and supplies the panel only the guarded write-back adapter.
/// </summary>
public sealed class SelectionTransformWindowController : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly Win32ForegroundSelectionTargetProvider targets;
    private readonly SelectionTextProvider selections;
    private readonly ISelectionTransformStreamingService transforms;
    private readonly WindowsClipboardGateway clipboard;
    private readonly IWin32ForegroundSelectionApi foreground;
    private readonly Action<string> reportFailure;
    private SelectionResultWindow? activeWindow;
    private int disposed;

    public SelectionTransformWindowController(
        Dispatcher dispatcher,
        ISelectionTransformStreamingService transforms,
        Action<string> reportFailure)
    {
        this.dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        this.transforms = transforms ?? throw new ArgumentNullException(nameof(transforms));
        this.reportFailure = reportFailure ?? throw new ArgumentNullException(nameof(reportFailure));
        foreground = new WindowsForegroundSelectionApi();
        targets = new Win32ForegroundSelectionTargetProvider(
            foreground,
            Process.GetCurrentProcess().Id,
            TimeProvider.System);
        clipboard = new WindowsClipboardGateway();
        var reader = new UiAutomationSelectionReader(
            new WindowsUiAutomationSelectionProbeProvider(), TimeProvider.System);
        selections = new SelectionTextProvider(
            reader,
            new SelectionClipboardTransaction(clipboard, new WindowsSelectionCopySender()),
            new Win32SelectionTargetActivation(),
            TimeProvider.System);
    }

    public async Task StartAsync(
        SelectionTransformOperation operation,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        var target = targets.Capture();
        if (target.Target is null)
        {
            reportFailure(L10n.Localize("SelectionFailureNoSelection"));
            return;
        }
        var selection = await selections.ReadAsync(target.Target, cancellationToken).ConfigureAwait(false);
        if (selection.Snapshot is null)
        {
            reportFailure(SelectionFailurePresentation.From(selection.Status));
            return;
        }

        var snapshot = selection.Snapshot;
        await dispatcher.InvokeAsync(() => Show(snapshot, operation), DispatcherPriority.Input, cancellationToken);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0)
        {
            if (dispatcher.CheckAccess())
            {
                activeWindow?.Close();
                activeWindow = null;
            }
            else if (!dispatcher.HasShutdownStarted)
            {
                _ = dispatcher.BeginInvoke(() =>
                {
                    activeWindow?.Close();
                    activeWindow = null;
                });
            }
            clipboard.Dispose();
        }
    }

    private void Show(SelectionSnapshot snapshot, SelectionTransformOperation operation)
    {
        activeWindow?.Close();
        activeWindow = null;
        var writeBack = new SelectionWriteBackService(
            new Win32SelectionTargetActivation(),
            new SelectionTargetRevalidatorAdapter(new SelectionTargetRevalidator(
                new WindowsUiAutomationSelectionRevalidationProbeProvider(foreground),
                new WindowsUiAutomationRangeReselector(foreground))),
            new QuickPasteSelectionWriteOutput(new QuickPasteService(clipboard, new WindowsPasteShortcutSender())),
            new WindowsSelectionWriteClipboard(clipboard));
        var viewModel = new SelectionResultViewModel(
            snapshot.Text,
            operation,
            transforms,
            clipboard: new WpfSelectionResultClipboard(),
            writer: new SelectionResultWriteBackAdapter(snapshot, writeBack));
        var window = new SelectionResultWindow { DataContext = viewModel };
        activeWindow = window;
        window.Closed += (_, _) =>
        {
            if (ReferenceEquals(activeWindow, window))
            {
                activeWindow = null;
            }
        };
        var workArea = SystemParameters.WorkArea;
        var display = new SelectionDisplay("primary", new WindowBounds(
            workArea.Left, workArea.Top, workArea.Width, workArea.Height), 1);
        window.ApplyPlacement(SelectionResultWindowPlacement.Calculate(
            snapshot.Target.Bounds, [display], display, display));
        window.Show();
        _ = viewModel.StartAsync();
    }

    private sealed class QuickPasteSelectionWriteOutput(IQuickPasteOutput paste)
        : ISelectionWriteOutput
    {
        public ValueTask<OutputResult> PasteAsync(string text, CancellationToken cancellationToken) =>
            paste.PasteAsync(text, cancellationToken);
    }

    private sealed class WindowsSelectionWriteClipboard(WindowsClipboardGateway clipboard)
        : ISelectionWriteClipboard
    {
        public bool TryCopy(string text)
        {
            try { _ = clipboard.WriteUnicodeText(text); return true; }
            catch (ClipboardOperationException) { return false; }
        }
    }

    private sealed class WpfSelectionResultClipboard : ISelectionResultClipboard
    {
        public bool TrySetText(string text)
        {
            try
            {
                System.Windows.Clipboard.SetText(text, System.Windows.TextDataFormat.UnicodeText);
                return true;
            }
            catch (System.Runtime.InteropServices.COMException) { return false; }
        }
    }
}
