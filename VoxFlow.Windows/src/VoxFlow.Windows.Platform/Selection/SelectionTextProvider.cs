using System.Runtime.InteropServices;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

public enum SelectionTextReadStatus
{
    Captured,
    NoSelection,
    SecureElement,
    TargetChanged,
    TerminalNotSupported,
    ClipboardBusy,
    CopySendFailed,
}

public sealed record SelectionTextReadResult(
    SelectionTextReadStatus Status,
    SelectionSnapshot? Snapshot);

public interface ISelectionTargetActivation
{
    bool Activate(ForegroundTargetSnapshot target);

    bool IsStillTarget(ForegroundTargetSnapshot target);
}

/// <summary>
/// Selects a source in the only allowed order: UI Automation first, then a
/// bounded Ctrl+C transaction against the frozen original target. It never
/// interprets pre-existing clipboard data as selected text.
/// </summary>
public sealed class SelectionTextProvider
{
    private readonly IUiAutomationSelectionReader uiAutomation;
    private readonly ISelectionClipboardTransaction clipboard;
    private readonly ISelectionTargetActivation activation;
    private readonly TimeProvider timeProvider;

    public SelectionTextProvider(
        IUiAutomationSelectionReader uiAutomation,
        ISelectionClipboardTransaction clipboard,
        ISelectionTargetActivation activation,
        TimeProvider timeProvider)
    {
        this.uiAutomation = uiAutomation ?? throw new ArgumentNullException(nameof(uiAutomation));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.activation = activation ?? throw new ArgumentNullException(nameof(activation));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public async ValueTask<SelectionTextReadResult> ReadAsync(
        ForegroundTargetSnapshot target,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(target);
        var uiResult = uiAutomation.Read(target);
        if (uiResult.Status == UiAutomationSelectionReadStatus.Captured)
        {
            return new(SelectionTextReadStatus.Captured, uiResult.Snapshot);
        }
        if (uiResult.Status == UiAutomationSelectionReadStatus.SecureElement)
        {
            return new(SelectionTextReadStatus.SecureElement, null);
        }
        if (IsTerminal(target.ProcessName))
        {
            return new(SelectionTextReadStatus.TerminalNotSupported, null);
        }
        if (!activation.Activate(target) || !activation.IsStillTarget(target))
        {
            return new(SelectionTextReadStatus.TargetChanged, null);
        }

        var copied = await clipboard.CopyAsync(cancellationToken).ConfigureAwait(false);
        if (copied.Status != SelectionClipboardReadStatus.Captured || copied.Text is null)
        {
            return new(Map(copied.Status), null);
        }

        return new(
            SelectionTextReadStatus.Captured,
            new SelectionSnapshot(
                copied.Text,
                SelectionAcquisitionSource.ShortcutCopy,
                target,
                target.FocusedElementRuntimeId,
                [],
                SelectionEditability.Unknown,
                allowsReselection: false,
                Math.Max(
                    target.CapturedAtUnixMs,
                    timeProvider.GetUtcNow().ToUnixTimeMilliseconds())));
    }

    private static SelectionTextReadStatus Map(SelectionClipboardReadStatus status) => status switch
    {
        SelectionClipboardReadStatus.ClipboardBusy => SelectionTextReadStatus.ClipboardBusy,
        SelectionClipboardReadStatus.CopySendFailed => SelectionTextReadStatus.CopySendFailed,
        _ => SelectionTextReadStatus.NoSelection,
    };

    private static bool IsTerminal(string processName) => processName.Trim().ToLowerInvariant() is
        "windowsterminal.exe" or "cmd.exe" or "powershell.exe" or "pwsh.exe" or "conhost.exe";
}

public sealed class Win32SelectionTargetActivation : ISelectionTargetActivation
{
    public bool Activate(ForegroundTargetSnapshot target)
    {
        ArgumentNullException.ThrowIfNull(target);
        return SetForegroundWindowNative((nint)target.WindowHandle);
    }

    public bool IsStillTarget(ForegroundTargetSnapshot target)
    {
        ArgumentNullException.ThrowIfNull(target);
        var current = GetForegroundWindowNative();
        if (current != (nint)target.WindowHandle)
        {
            return false;
        }

        _ = GetWindowThreadProcessIdNative(current, out var processId);
        return processId == target.ProcessId;
    }

    [DllImport("user32.dll", EntryPoint = "SetForegroundWindow", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindowNative(nint windowHandle);

    [DllImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    private static extern nint GetForegroundWindowNative();

    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId", SetLastError = true)]
    private static extern uint GetWindowThreadProcessIdNative(nint windowHandle, out int processId);
}
