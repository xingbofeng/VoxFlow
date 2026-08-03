using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class SelectionWriteBackServiceTests
{
    [Fact]
    public async Task Verified_editable_selection_is_reselected_then_replaced_without_enter()
    {
        var target = Snapshot();
        var activation = new FakeActivation();
        var output = new CapturingOutput(OutputResultKind.Inserted);
        var clipboard = new CapturingClipboard();
        var service = new SelectionWriteBackService(
            activation,
            new ReadyRevalidator(),
            output,
            clipboard);

        var result = await service.ReplaceAsync(target, "translated", CancellationToken.None);

        Assert.True(result.WrittenToOriginal);
        Assert.False(result.CopiedFallback);
        Assert.Equal("translated", output.Text);
        Assert.Null(clipboard.Text);
        Assert.True(activation.Activated);
    }

    [Fact]
    public async Task Readonly_changed_ambiguous_uipi_or_paste_failure_copy_unprefixed_displayed_text()
    {
        foreach (var status in new[]
                 {
                     SelectionTargetRevalidationStatus.NotEditable,
                     SelectionTargetRevalidationStatus.TargetChanged,
                     SelectionTargetRevalidationStatus.AmbiguousSelection,
                     SelectionTargetRevalidationStatus.UipiBlocked,
                 })
        {
            var clipboard = new CapturingClipboard();
            var service = new SelectionWriteBackService(
                new FakeActivation(),
                new FixedRevalidator(status),
                new CapturingOutput(OutputResultKind.Inserted),
                clipboard);

            var result = await service.InsertAfterAsync(Snapshot(), "displayed", CancellationToken.None);

            Assert.False(result.WrittenToOriginal);
            Assert.True(result.CopiedFallback);
            Assert.Equal("displayed", clipboard.Text);
        }

        var failedClipboard = new CapturingClipboard();
        var failed = new SelectionWriteBackService(
            new FakeActivation(),
            new ReadyRevalidator(),
            new CapturingOutput(OutputResultKind.InjectionFailed),
            failedClipboard);
        var failedResult = await failed.ReplaceAsync(Snapshot(), "displayed", CancellationToken.None);
        Assert.True(failedResult.CopiedFallback);
        Assert.Equal("displayed", failedClipboard.Text);
    }

    private static SelectionSnapshot Snapshot() => new(
        "source", SelectionAcquisitionSource.UiAutomation,
        new ForegroundTargetSnapshot(1, 2, "notepad.exe", "draft", new WindowBounds(0, 0, 10, 10), ProcessIntegrityLevel.Medium, [1], 1),
        [1], [new SelectionRangeSnapshot(0, "source", [new WindowBounds(0, 0, 1, 1)], null, null)],
        SelectionEditability.Editable, true, 2);

    private sealed class FakeActivation : ISelectionTargetActivation
    {
        public bool Activated { get; private set; }
        public bool Activate(ForegroundTargetSnapshot target) => Activated = true;
        public bool IsStillTarget(ForegroundTargetSnapshot target) => true;
    }

    private sealed class ReadyRevalidator : ISelectionWriteRevalidator
    {
        public SelectionTargetRevalidationResult RevalidateAndReselect(SelectionSnapshot snapshot) => new(SelectionTargetRevalidationStatus.Ready);
    }

    private sealed class FixedRevalidator(SelectionTargetRevalidationStatus status) : ISelectionWriteRevalidator
    {
        public SelectionTargetRevalidationResult RevalidateAndReselect(SelectionSnapshot snapshot) => new(status);
    }

    private sealed class CapturingOutput(OutputResultKind kind) : ISelectionWriteOutput
    {
        public string? Text { get; private set; }
        public ValueTask<OutputResult> PasteAsync(string text, CancellationToken cancellationToken)
        {
            Text = text;
            return ValueTask.FromResult(new OutputResult(kind, kind == OutputResultKind.InjectionFailed ? VoxFlowErrorCode.InputInjectionFailure : null));
        }
    }

    private sealed class CapturingClipboard : ISelectionWriteClipboard
    {
        public string? Text { get; private set; }
        public bool TryCopy(string text) { Text = text; return true; }
    }
}
