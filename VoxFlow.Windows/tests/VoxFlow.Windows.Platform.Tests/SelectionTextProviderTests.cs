using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class SelectionTextProviderTests
{
    private static readonly ForegroundTargetSnapshot Target = new(
        0x1234, 4242, "notepad.exe", "Draft",
        new WindowBounds(0, 0, 800, 600), ProcessIntegrityLevel.Medium,
        [1], 100);

    [Fact]
    public async Task Ui_automation_selection_wins_without_sending_ctrl_c()
    {
        var copy = new CapturingCopySender();
        var provider = Provider(
            UiResult(UiAutomationSelectionReadStatus.Captured, "uia text"),
            copy);

        var result = await provider.ReadAsync(Target, CancellationToken.None);

        Assert.Equal(SelectionTextReadStatus.Captured, result.Status);
        Assert.Equal("uia text", result.Snapshot?.Text);
        Assert.Equal(0, copy.SendCount);
    }

    [Fact]
    public async Task Ctrl_c_fallback_requires_original_target_activation_and_revalidation()
    {
        var copy = new CapturingCopySender();
        var activation = new FakeActivation(canActivate: true, isStillTarget: false);
        var provider = Provider(
            UiResult(UiAutomationSelectionReadStatus.NoSelection, null),
            copy,
            activation);

        var result = await provider.ReadAsync(Target, CancellationToken.None);

        Assert.Equal(SelectionTextReadStatus.TargetChanged, result.Status);
        Assert.Equal(1, activation.ActivateCalls);
        Assert.Equal(0, copy.SendCount);
    }

    [Fact]
    public async Task Terminal_without_a_proven_selection_never_receives_ctrl_c()
    {
        var copy = new CapturingCopySender();
        var terminal = new ForegroundTargetSnapshot(
            Target.WindowHandle,
            Target.ProcessId,
            "WindowsTerminal.exe",
            Target.WindowTitle,
            Target.Bounds,
            Target.IntegrityLevel,
            Target.FocusedElementRuntimeId,
            Target.CapturedAtUnixMs);
        var provider = Provider(
            UiResult(UiAutomationSelectionReadStatus.NoSelection, null),
            copy);

        var result = await provider.ReadAsync(terminal, CancellationToken.None);

        Assert.Equal(SelectionTextReadStatus.TerminalNotSupported, result.Status);
        Assert.Equal(0, copy.SendCount);
    }

    [Fact]
    public async Task Successful_ctrl_c_fallback_creates_a_non_reselectable_snapshot()
    {
        var copy = new CapturingCopySender();
        var provider = Provider(
            UiResult(UiAutomationSelectionReadStatus.NoSelection, null),
            copy,
            transaction: new FakeClipboardTransaction("copied selection", copy));

        var result = await provider.ReadAsync(Target, CancellationToken.None);

        var snapshot = Assert.IsType<SelectionSnapshot>(result.Snapshot);
        Assert.Equal(SelectionAcquisitionSource.ShortcutCopy, snapshot.Source);
        Assert.False(snapshot.AllowsReselection);
        Assert.Equal(SelectionEditability.Unknown, snapshot.Editability);
        Assert.Equal(1, copy.SendCount);
    }

    private static SelectionTextProvider Provider(
        UiAutomationSelectionReadResult ui,
        CapturingCopySender copy,
        FakeActivation? activation = null,
        ISelectionClipboardTransaction? transaction = null) => new(
        new FakeUiReader(ui),
        transaction ?? new FakeClipboardTransaction("copied selection", copy),
        activation ?? new FakeActivation(canActivate: true, isStillTarget: true),
        TimeProvider.System);

    private static UiAutomationSelectionReadResult UiResult(
        UiAutomationSelectionReadStatus status,
        string? text) => text is null
            ? new(status, null)
            : new(status, new SelectionSnapshot(
                text,
                SelectionAcquisitionSource.UiAutomation,
                Target,
                [1],
                [new SelectionRangeSnapshot(0, text, [new WindowBounds(1, 2, 3, 4)], null, null)],
                SelectionEditability.Editable,
                true,
                101));

    private sealed class FakeUiReader(UiAutomationSelectionReadResult result)
        : IUiAutomationSelectionReader
    {
        public UiAutomationSelectionReadResult Read(ForegroundTargetSnapshot target) => result;
    }

    private sealed class CapturingCopySender : ISelectionCopySender
    {
        public int SendCount { get; private set; }
        public bool SendCtrlC()
        {
            SendCount++;
            return true;
        }
    }

    private sealed class FakeActivation(bool canActivate, bool isStillTarget)
        : ISelectionTargetActivation
    {
        public int ActivateCalls { get; private set; }
        public bool Activate(ForegroundTargetSnapshot target)
        {
            ActivateCalls++;
            return canActivate;
        }

        public bool IsStillTarget(ForegroundTargetSnapshot target) => isStillTarget;
    }

    private sealed class FakeClipboardTransaction(string? text, CapturingCopySender copy)
        : ISelectionClipboardTransaction
    {
        public ValueTask<SelectionClipboardReadResult> CopyAsync(CancellationToken cancellationToken)
        {
            _ = copy.SendCtrlC();
            return ValueTask.FromResult(new SelectionClipboardReadResult(
                string.IsNullOrWhiteSpace(text)
                    ? SelectionClipboardReadStatus.EmptyText
                    : SelectionClipboardReadStatus.Captured,
                text));
        }
    }
}
