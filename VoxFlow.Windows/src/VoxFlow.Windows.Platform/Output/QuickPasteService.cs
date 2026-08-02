using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Output;

public interface IClipboardSnapshot : IDisposable
{
}

public sealed record ClipboardWriteReceipt
{
    public ClipboardWriteReceipt(uint sequenceNumber, string ownershipMarker)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(ownershipMarker);
        SequenceNumber = sequenceNumber;
        OwnershipMarker = ownershipMarker;
    }

    public uint SequenceNumber { get; }

    public string OwnershipMarker { get; }
}

public interface IClipboardGateway
{
    IClipboardSnapshot CaptureSnapshot();

    ClipboardWriteReceipt WriteUnicodeText(string text);

    bool IsCurrent(ClipboardWriteReceipt receipt);

    void Restore(IClipboardSnapshot snapshot);
}

public interface IPasteShortcutSender
{
    bool SendCtrlV();
}

public interface IOutputDelay
{
    ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken);
}

public interface IQuickPasteOutput
{
    ValueTask<OutputResult> PasteAsync(
        string text,
        CancellationToken cancellationToken);
}

public sealed class ClipboardOperationException : Exception
{
    public ClipboardOperationException(string message)
        : base(message)
    {
    }

    public ClipboardOperationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public sealed class QuickPasteService : IQuickPasteOutput
{
    private static readonly TimeSpan RestoreWindow = TimeSpan.FromMilliseconds(200);
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(20);

    private readonly IClipboardGateway clipboard;
    private readonly IPasteShortcutSender pasteShortcutSender;
    private readonly IOutputDelay delay;

    public QuickPasteService(
        IClipboardGateway clipboard,
        IPasteShortcutSender pasteShortcutSender,
        IOutputDelay? delay = null)
    {
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.pasteShortcutSender = pasteShortcutSender
            ?? throw new ArgumentNullException(nameof(pasteShortcutSender));
        this.delay = delay ?? SystemOutputDelay.Instance;
    }

    public async ValueTask<OutputResult> PasteAsync(
        string text,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        cancellationToken.ThrowIfCancellationRequested();

        IClipboardSnapshot snapshot;
        try
        {
            snapshot = clipboard.CaptureSnapshot();
        }
        catch (ClipboardOperationException)
        {
            return new OutputResult(
                OutputResultKind.CopyFailed,
                VoxFlowErrorCode.ClipboardFailure);
        }

        using (snapshot)
        {
            ClipboardWriteReceipt receipt;
            try
            {
                receipt = clipboard.WriteUnicodeText(text);
            }
            catch (ClipboardOperationException)
            {
                return new OutputResult(
                    OutputResultKind.CopyFailed,
                    VoxFlowErrorCode.ClipboardFailure);
            }

            if (!pasteShortcutSender.SendCtrlV())
            {
                TryRestoreOwnedClipboard(snapshot, receipt);
                return new OutputResult(
                    OutputResultKind.InjectionFailed,
                    VoxFlowErrorCode.InputInjectionFailure);
            }

            try
            {
                var elapsed = TimeSpan.Zero;
                while (elapsed < RestoreWindow)
                {
                    var nextDelay = RestoreWindow - elapsed < PollInterval
                        ? RestoreWindow - elapsed
                        : PollInterval;
                    await delay.DelayAsync(nextDelay, cancellationToken).ConfigureAwait(false);
                    elapsed += nextDelay;

                    if (!clipboard.IsCurrent(receipt))
                    {
                        return new OutputResult(OutputResultKind.Inserted);
                    }
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                TryRestoreOwnedClipboard(snapshot, receipt);
                throw;
            }

            TryRestoreOwnedClipboard(snapshot, receipt);
            return new OutputResult(OutputResultKind.Inserted);
        }
    }

    private void TryRestoreOwnedClipboard(
        IClipboardSnapshot snapshot,
        ClipboardWriteReceipt receipt)
    {
        if (!clipboard.IsCurrent(receipt))
        {
            return;
        }

        try
        {
            clipboard.Restore(snapshot);
        }
        catch (ClipboardOperationException)
        {
            // The paste already completed. A competing clipboard owner wins safely.
        }
    }

    private sealed class SystemOutputDelay : IOutputDelay
    {
        public static SystemOutputDelay Instance { get; } = new();

        public ValueTask DelayAsync(
            TimeSpan delay,
            CancellationToken cancellationToken) =>
            new(Task.Delay(delay, cancellationToken));
    }
}
