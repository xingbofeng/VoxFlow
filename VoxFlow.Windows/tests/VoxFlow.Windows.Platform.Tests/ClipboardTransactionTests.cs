using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class ClipboardTransactionTests
{
    [Fact]
    public async Task Quick_paste_preserves_the_opaque_full_snapshot_and_restores_it_after_200ms()
    {
        var snapshot = new FakeClipboardSnapshot(
            new Dictionary<string, object>
            {
                ["UnicodeText"] = "before",
                ["HTML Format"] = "<b>before</b>",
                ["application/x-voxflow-test"] = new byte[] { 1, 2, 3 },
            });
        var events = new List<string>();
        var clipboard = new FakeClipboardGateway(snapshot, events: events);
        var pasteKeys = new CapturingPasteShortcutSender(events);
        var delay = new CapturingOutputDelay();
        var service = new QuickPasteService(clipboard, pasteKeys, delay);

        var result = await service.PasteAsync("你好 VoxFlow 👋", CancellationToken.None);

        Assert.Equal(OutputResultKind.Inserted, result.Kind);
        Assert.Equal("你好 VoxFlow 👋", clipboard.WrittenText);
        Assert.Equal(1, pasteKeys.SendCount);
        Assert.Equal(TimeSpan.FromMilliseconds(200), delay.TotalDelay);
        Assert.Same(snapshot, clipboard.RestoredSnapshot);
        Assert.Equal(["capture", "write", "paste", "restore"], events);
    }

    [Fact]
    public async Task External_clipboard_change_during_wait_is_never_overwritten_by_restore()
    {
        var snapshot = new FakeClipboardSnapshot(new Dictionary<string, object>());
        var clipboard = new FakeClipboardGateway(snapshot);
        var pasteKeys = new CapturingPasteShortcutSender();
        var delay = new CapturingOutputDelay(elapsed =>
        {
            if (elapsed >= TimeSpan.FromMilliseconds(60))
            {
                clipboard.SimulateExternalWrite();
            }
        });
        var service = new QuickPasteService(clipboard, pasteKeys, delay);

        var result = await service.PasteAsync("transcript", CancellationToken.None);

        Assert.Equal(OutputResultKind.Inserted, result.Kind);
        Assert.Equal(1, pasteKeys.SendCount);
        Assert.Null(clipboard.RestoredSnapshot);
        Assert.InRange(delay.TotalDelay, TimeSpan.FromMilliseconds(60), TimeSpan.FromMilliseconds(199));
    }

    [Fact]
    public async Task External_write_between_our_set_and_sequence_receipt_is_not_claimed_or_restored()
    {
        var snapshot = new FakeClipboardSnapshot(
            new Dictionary<string, object> { ["UnicodeText"] = "before" });
        var clipboard = new FakeClipboardGateway(
            snapshot,
            externalWriteDuringWrite: true);
        var service = new QuickPasteService(
            clipboard,
            new CapturingPasteShortcutSender(),
            new CapturingOutputDelay());

        var result = await service.PasteAsync("temporary", CancellationToken.None);

        Assert.Equal(OutputResultKind.Inserted, result.Kind);
        Assert.Null(clipboard.RestoredSnapshot);
        Assert.Equal(TimeSpan.FromMilliseconds(20), clipboard.OwnershipCheckElapsed);
    }

    [Fact]
    public async Task Clipboard_write_failure_returns_copy_failed_and_never_sends_ctrl_v()
    {
        var clipboard = new FakeClipboardGateway(
            new FakeClipboardSnapshot(new Dictionary<string, object>()),
            failWrite: true);
        var pasteKeys = new CapturingPasteShortcutSender();
        var service = new QuickPasteService(
            clipboard,
            pasteKeys,
            new CapturingOutputDelay());

        var result = await service.PasteAsync("transcript", CancellationToken.None);

        Assert.Equal(OutputResultKind.CopyFailed, result.Kind);
        Assert.Equal(VoxFlowErrorCode.ClipboardFailure, result.ErrorCode);
        Assert.Equal(0, pasteKeys.SendCount);
        Assert.Null(clipboard.RestoredSnapshot);
    }

    [Fact]
    public async Task Clipboard_snapshot_failure_is_classified_without_destroying_current_contents()
    {
        var clipboard = new FakeClipboardGateway(
            new FakeClipboardSnapshot(new Dictionary<string, object>()),
            failCapture: true);
        var pasteKeys = new CapturingPasteShortcutSender();
        var service = new QuickPasteService(
            clipboard,
            pasteKeys,
            new CapturingOutputDelay());

        var result = await service.PasteAsync("transcript", CancellationToken.None);

        Assert.Equal(OutputResultKind.CopyFailed, result.Kind);
        Assert.Null(clipboard.WrittenText);
        Assert.Equal(0, pasteKeys.SendCount);
    }

    [Fact]
    public async Task Cancellation_during_restore_window_restores_only_our_owned_clipboard()
    {
        using var cancellation = new CancellationTokenSource();
        var snapshot = new FakeClipboardSnapshot(
            new Dictionary<string, object> { ["UnicodeText"] = "before" });
        var clipboard = new FakeClipboardGateway(snapshot);
        var pasteKeys = new CapturingPasteShortcutSender();
        var delay = new CapturingOutputDelay(_ => cancellation.Cancel());
        var service = new QuickPasteService(clipboard, pasteKeys, delay);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await service.PasteAsync("temporary transcript", cancellation.Token));

        Assert.Equal(1, pasteKeys.SendCount);
        Assert.Same(snapshot, clipboard.RestoredSnapshot);
    }

    private sealed class FakeClipboardSnapshot(
        IReadOnlyDictionary<string, object> formats) : IClipboardSnapshot
    {
        public IReadOnlyDictionary<string, object> Formats { get; } = formats;

        public void Dispose()
        {
        }
    }

    private sealed class FakeClipboardGateway : IClipboardGateway
    {
        private readonly IClipboardSnapshot snapshot;
        private readonly bool failCapture;
        private readonly bool failWrite;
        private readonly bool externalWriteDuringWrite;
        private readonly IList<string> events;
        private uint sequenceNumber = 100;
        private bool ownsMarker;

        public FakeClipboardGateway(
            IClipboardSnapshot snapshot,
            bool failCapture = false,
            bool failWrite = false,
            bool externalWriteDuringWrite = false,
            IList<string>? events = null)
        {
            this.snapshot = snapshot;
            this.failCapture = failCapture;
            this.failWrite = failWrite;
            this.externalWriteDuringWrite = externalWriteDuringWrite;
            this.events = events ?? [];
        }

        public string? WrittenText { get; private set; }

        public IClipboardSnapshot? RestoredSnapshot { get; private set; }

        public TimeSpan OwnershipCheckElapsed { get; private set; }

        public IClipboardSnapshot CaptureSnapshot()
        {
            events.Add("capture");
            if (failCapture)
            {
                throw new ClipboardOperationException("Clipboard is unavailable.");
            }

            return snapshot;
        }

        public ClipboardWriteReceipt WriteUnicodeText(string text)
        {
            events.Add("write");
            if (failWrite)
            {
                throw new ClipboardOperationException("Clipboard is unavailable.");
            }

            WrittenText = text;
            sequenceNumber++;
            ownsMarker = true;
            if (externalWriteDuringWrite)
            {
                sequenceNumber++;
                ownsMarker = false;
            }

            return new ClipboardWriteReceipt(sequenceNumber, "fake-marker");
        }

        public bool IsCurrent(ClipboardWriteReceipt receipt)
        {
            OwnershipCheckElapsed += TimeSpan.FromMilliseconds(20);
            return ownsMarker && receipt.SequenceNumber == sequenceNumber;
        }

        public void Restore(IClipboardSnapshot value)
        {
            events.Add("restore");
            RestoredSnapshot = value;
            sequenceNumber++;
        }

        public void SimulateExternalWrite()
        {
            sequenceNumber++;
            ownsMarker = false;
        }
    }

    private sealed class CapturingPasteShortcutSender(
        IList<string>? events = null) : IPasteShortcutSender
    {
        public int SendCount { get; private set; }

        public bool SendCtrlV()
        {
            SendCount++;
            events?.Add("paste");
            return true;
        }
    }

    private sealed class CapturingOutputDelay(
        Action<TimeSpan>? afterDelay = null) : IOutputDelay
    {
        public TimeSpan TotalDelay { get; private set; }

        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            TotalDelay += delay;
            afterDelay?.Invoke(TotalDelay);
            return ValueTask.CompletedTask;
        }
    }
}
