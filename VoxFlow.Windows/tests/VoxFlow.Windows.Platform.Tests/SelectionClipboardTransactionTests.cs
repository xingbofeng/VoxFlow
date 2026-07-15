using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class SelectionClipboardTransactionTests
{
    [Fact]
    public async Task Copy_with_a_new_nonempty_unicode_text_restores_the_full_snapshot_when_unchanged()
    {
        var snapshot = new FakeSnapshot();
        var clipboard = new FakeSelectionClipboardGateway(snapshot)
        {
            CopiedText = "selected text",
        };
        var transaction = new SelectionClipboardTransaction(
            clipboard,
            new FakeCopySender(clipboard),
            new ImmediateSelectionClipboardDelay());

        var result = await transaction.CopyAsync(CancellationToken.None);

        Assert.Equal(SelectionClipboardReadStatus.Captured, result.Status);
        Assert.Equal("selected text", result.Text);
        Assert.Same(snapshot, clipboard.Restored);
    }

    [Fact]
    public async Task Existing_clipboard_text_is_never_treated_as_a_selection_when_sequence_does_not_change()
    {
        var clipboard = new FakeSelectionClipboardGateway(new FakeSnapshot())
        {
            CopiedText = "old clipboard text",
            ChangesSequenceOnCopy = false,
        };
        var transaction = new SelectionClipboardTransaction(
            clipboard,
            new FakeCopySender(clipboard),
            new ImmediateSelectionClipboardDelay());

        var result = await transaction.CopyAsync(CancellationToken.None);

        Assert.Equal(SelectionClipboardReadStatus.NoSequenceChange, result.Status);
        Assert.Null(result.Text);
        Assert.Null(clipboard.Restored);
    }

    [Fact]
    public async Task External_write_after_copy_wins_and_is_not_overwritten_by_restore()
    {
        var clipboard = new FakeSelectionClipboardGateway(new FakeSnapshot())
        {
            CopiedText = "selected text",
            ExternalWriteAfterRead = true,
        };
        var transaction = new SelectionClipboardTransaction(
            clipboard,
            new FakeCopySender(clipboard),
            new ImmediateSelectionClipboardDelay());

        var result = await transaction.CopyAsync(CancellationToken.None);

        Assert.Equal(SelectionClipboardReadStatus.Captured, result.Status);
        Assert.Null(clipboard.Restored);
    }

    [Fact]
    public async Task Clipboard_busy_during_snapshot_returns_a_specific_failure_without_sending_copy()
    {
        var clipboard = new FakeSelectionClipboardGateway(new FakeSnapshot())
        {
            ThrowOnCapture = true,
        };
        var sender = new FakeCopySender(clipboard);
        var transaction = new SelectionClipboardTransaction(
            clipboard,
            sender,
            new ImmediateSelectionClipboardDelay());

        var result = await transaction.CopyAsync(CancellationToken.None);

        Assert.Equal(SelectionClipboardReadStatus.ClipboardBusy, result.Status);
        Assert.Equal(0, sender.SendCount);
    }

    private sealed class FakeSnapshot : IClipboardSnapshot
    {
        public void Dispose()
        {
        }
    }

    private sealed class FakeSelectionClipboardGateway(IClipboardSnapshot snapshot)
        : ISelectionClipboardGateway
    {
        private uint sequence = 100;

        public string? CopiedText { get; set; }
        public bool ChangesSequenceOnCopy { get; set; } = true;
        public bool ExternalWriteAfterRead { get; set; }
        public bool ThrowOnCapture { get; set; }
        public IClipboardSnapshot? Restored { get; private set; }

        public IClipboardSnapshot CaptureSnapshot()
        {
            if (ThrowOnCapture)
            {
                throw new ClipboardOperationException("busy");
            }

            return snapshot;
        }

        public uint GetSequenceNumber() => sequence;

        public string? ReadUnicodeText()
        {
            OnRead();
            return CopiedText;
        }

        public void Restore(IClipboardSnapshot value) => Restored = value;

        public void OnCopy()
        {
            if (ChangesSequenceOnCopy)
            {
                sequence++;
            }
        }

        public void OnRead()
        {
            if (ExternalWriteAfterRead)
            {
                sequence++;
            }
        }
    }

    private sealed class FakeCopySender(FakeSelectionClipboardGateway clipboard)
        : ISelectionCopySender
    {
        public int SendCount { get; private set; }

        public bool SendCtrlC()
        {
            SendCount++;
            clipboard.OnCopy();
            return true;
        }
    }

    private sealed class ImmediateSelectionClipboardDelay : ISelectionClipboardDelay
    {
        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }
}
