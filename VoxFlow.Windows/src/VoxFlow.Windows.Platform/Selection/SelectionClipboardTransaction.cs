using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Selection;

public enum SelectionClipboardReadStatus
{
    Captured,
    NoSequenceChange,
    EmptyText,
    ClipboardBusy,
    CopySendFailed,
}

public sealed record SelectionClipboardReadResult(
    SelectionClipboardReadStatus Status,
    string? Text);

public interface ISelectionClipboardGateway
{
    IClipboardSnapshot CaptureSnapshot();

    uint GetSequenceNumber();

    string? ReadUnicodeText();

    void Restore(IClipboardSnapshot snapshot);
}

public interface ISelectionCopySender
{
    bool SendCtrlC();
}

public interface ISelectionClipboardDelay
{
    ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken);
}

public interface ISelectionClipboardTransaction
{
    ValueTask<SelectionClipboardReadResult> CopyAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Owns the short Ctrl+C clipboard window used only after UI Automation failed
/// to prove a selection.  The pre-copy clipboard is restored only when its
/// sequence still identifies the data produced by this transaction.
/// </summary>
public sealed class SelectionClipboardTransaction : ISelectionClipboardTransaction
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(20);
    private const int PollCount = 6; // 120 ms: inside the required 80-150 ms window.

    private readonly ISelectionClipboardGateway clipboard;
    private readonly ISelectionCopySender copySender;
    private readonly ISelectionClipboardDelay delay;

    public SelectionClipboardTransaction(
        ISelectionClipboardGateway clipboard,
        ISelectionCopySender copySender,
        ISelectionClipboardDelay? delay = null)
    {
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.copySender = copySender ?? throw new ArgumentNullException(nameof(copySender));
        this.delay = delay ?? SystemSelectionClipboardDelay.Instance;
    }

    public async ValueTask<SelectionClipboardReadResult> CopyAsync(
        CancellationToken cancellationToken)
    {
        IClipboardSnapshot snapshot;
        uint before;
        try
        {
            snapshot = clipboard.CaptureSnapshot();
            before = clipboard.GetSequenceNumber();
        }
        catch (ClipboardOperationException)
        {
            return new(SelectionClipboardReadStatus.ClipboardBusy, null);
        }

        using (snapshot)
        {
            if (!copySender.SendCtrlC())
            {
                return new(SelectionClipboardReadStatus.CopySendFailed, null);
            }

            uint copiedSequence = 0;
            try
            {
                for (var attempt = 0; attempt < PollCount; attempt++)
                {
                    await delay.DelayAsync(PollInterval, cancellationToken).ConfigureAwait(false);
                    var sequence = clipboard.GetSequenceNumber();
                    if (sequence == before)
                    {
                        continue;
                    }

                    copiedSequence = sequence;
                    var text = clipboard.ReadUnicodeText();
                    var afterRead = clipboard.GetSequenceNumber();
                    if (afterRead != copiedSequence)
                    {
                        // The text was obtained while this transaction owned the
                        // clipboard. A later external writer wins ownership, but
                        // must not invalidate the already-proven selection.
                        return string.IsNullOrWhiteSpace(text)
                            ? new(SelectionClipboardReadStatus.EmptyText, null)
                            : new(SelectionClipboardReadStatus.Captured, text);
                    }

                    return string.IsNullOrWhiteSpace(text)
                        ? new(SelectionClipboardReadStatus.EmptyText, null)
                        : new(SelectionClipboardReadStatus.Captured, text);
                }

                return new(SelectionClipboardReadStatus.NoSequenceChange, null);
            }
            catch (ClipboardOperationException)
            {
                return new(SelectionClipboardReadStatus.ClipboardBusy, null);
            }
            finally
            {
                if (copiedSequence != 0 && TryOwnsSequence(copiedSequence))
                {
                    TryRestore(snapshot);
                }
            }
        }
    }

    private bool TryOwnsSequence(uint sequence)
    {
        try
        {
            return clipboard.GetSequenceNumber() == sequence;
        }
        catch (ClipboardOperationException)
        {
            return false;
        }
    }

    private void TryRestore(IClipboardSnapshot snapshot)
    {
        try
        {
            clipboard.Restore(snapshot);
        }
        catch (ClipboardOperationException)
        {
            // A competing clipboard owner wins.  Never overwrite their data.
        }
    }

    private sealed class SystemSelectionClipboardDelay : ISelectionClipboardDelay
    {
        public static SystemSelectionClipboardDelay Instance { get; } = new();

        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken) =>
            new(Task.Delay(delay, cancellationToken));
    }
}
