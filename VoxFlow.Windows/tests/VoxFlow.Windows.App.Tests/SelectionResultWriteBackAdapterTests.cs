using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.App.Tests;

public sealed class SelectionResultWriteBackAdapterTests
{
    [Fact]
    public async Task Adapter_reports_false_when_safe_write_path_uses_copy_fallback()
    {
        var clipboard = new CapturingClipboard();
        var service = new SelectionWriteBackService(
            new Activation(), new NotEditableRevalidator(), new Output(), clipboard);
        var adapter = new SelectionResultWriteBackAdapter(Snapshot(), service);

        Assert.False(await adapter.ReplaceAsync("result", CancellationToken.None));
        Assert.Equal("result", clipboard.Text);
    }

    [Fact]
    public async Task Adapter_throws_when_neither_write_nor_safe_copy_succeeds()
    {
        var service = new SelectionWriteBackService(
            new Activation(),
            new NotEditableRevalidator(),
            new Output(),
            new FailingClipboard());
        var adapter = new SelectionResultWriteBackAdapter(Snapshot(), service);

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            adapter.ReplaceAsync("result", CancellationToken.None));
    }

    private static SelectionSnapshot Snapshot() => new(
        "source", SelectionAcquisitionSource.UiAutomation,
        new ForegroundTargetSnapshot(1, 2, "notepad.exe", "draft", new WindowBounds(0, 0, 1, 1), ProcessIntegrityLevel.Medium, [1], 1),
        [1], [new SelectionRangeSnapshot(0, "source", [new WindowBounds(0, 0, 1, 1)], null, null)],
        SelectionEditability.Editable, true, 1);

    private sealed class Activation : ISelectionTargetActivation
    {
        public bool Activate(ForegroundTargetSnapshot target) => true;
        public bool IsStillTarget(ForegroundTargetSnapshot target) => true;
    }
    private sealed class NotEditableRevalidator : ISelectionWriteRevalidator
    {
        public SelectionTargetRevalidationResult RevalidateAndReselect(SelectionSnapshot snapshot) => new(SelectionTargetRevalidationStatus.NotEditable);
    }
    private sealed class Output : ISelectionWriteOutput
    {
        public ValueTask<OutputResult> PasteAsync(string text, CancellationToken cancellationToken) => ValueTask.FromResult(new OutputResult(OutputResultKind.Inserted));
    }
    private sealed class CapturingClipboard : ISelectionWriteClipboard
    {
        public string? Text { get; private set; }
        public bool TryCopy(string text) { Text = text; return true; }
    }

    private sealed class FailingClipboard : ISelectionWriteClipboard
    {
        public bool TryCopy(string text) => false;
    }
}
