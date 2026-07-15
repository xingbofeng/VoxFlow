using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class UiAutomationSelectionReaderTests
{
    private static readonly ForegroundTargetSnapshot Target = new(
        0x1234,
        4242,
        "notepad.exe",
        "Draft",
        new WindowBounds(10, 20, 800, 600),
        ProcessIntegrityLevel.Medium,
        [1, 2, 3],
        100);

    [Fact]
    public void Single_nonempty_TextPattern_selection_becomes_a_ui_automation_snapshot()
    {
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(
                ranges: [Range(0, "selected text")])),
            new ControlledTimeProvider(DateTimeOffset.FromUnixTimeMilliseconds(200)));

        var result = reader.Read(Target);

        Assert.Equal(UiAutomationSelectionReadStatus.Captured, result.Status);
        var snapshot = Assert.IsType<SelectionSnapshot>(result.Snapshot);
        Assert.Equal(SelectionAcquisitionSource.UiAutomation, snapshot.Source);
        Assert.Equal("selected text", snapshot.Text);
        Assert.Equal(SelectionEditability.Editable, snapshot.Editability);
        Assert.Equal([1, 2, 3], snapshot.ElementRuntimeId);
    }

    [Fact]
    public void Multiple_nonempty_ranges_are_joined_in_document_order_and_keep_bounds()
    {
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(ranges:
            [
                Range(5, "second", new WindowBounds(20, 40, 80, 20)),
                Range(2, "first", new WindowBounds(10, 40, 40, 20)),
            ])),
            TimeProvider.System);

        var result = reader.Read(Target);

        var snapshot = Assert.IsType<SelectionSnapshot>(result.Snapshot);
        Assert.Equal("first\nsecond", snapshot.Text);
        Assert.Collection(
            snapshot.Ranges,
            first => Assert.Equal(new WindowBounds(10, 40, 40, 20), Assert.Single(first.Bounds)),
            second => Assert.Equal(new WindowBounds(20, 40, 80, 20), Assert.Single(second.Bounds)));
    }

    [Fact]
    public void Degenerate_ranges_do_not_turn_the_document_or_control_value_into_a_selection()
    {
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(ranges: [Range(0, "   ")])),
            TimeProvider.System);

        var result = reader.Read(Target);

        Assert.Equal(UiAutomationSelectionReadStatus.NoSelection, result.Status);
        Assert.Null(result.Snapshot);
    }

    [Fact]
    public void Parent_TextPattern_is_used_when_the_focused_element_has_no_selection_pattern()
    {
        var parent = Node(runtimeId: [4, 5], ranges: [Range(0, "parent selection")]);
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(runtimeId: [1, 2, 3], parent: parent)),
            TimeProvider.System);

        var result = reader.Read(Target);

        var snapshot = Assert.IsType<SelectionSnapshot>(result.Snapshot);
        Assert.Equal("parent selection", snapshot.Text);
        Assert.Equal([4, 5], snapshot.ElementRuntimeId);
    }

    [Fact]
    public void Readonly_TextPattern_selection_is_captured_but_not_marked_editable()
    {
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(
                isEditable: false,
                ranges: [Range(0, "web page selection")])),
            TimeProvider.System);

        var result = reader.Read(Target);

        var snapshot = Assert.IsType<SelectionSnapshot>(result.Snapshot);
        Assert.Equal(SelectionEditability.ReadOnly, snapshot.Editability);
        Assert.False(snapshot.IsEditable);
    }

    [Theory]
    [InlineData("Word document editor")]
    [InlineData("VS Code text editor")]
    public void Editable_document_and_code_editor_selections_keep_reselection_identity(
        string selectedText)
    {
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(
                runtimeId: [8, 9, 10],
                ranges: [Range(0, selectedText, new WindowBounds(30, 50, 220, 20))])),
            TimeProvider.System);

        var result = reader.Read(Target);

        var snapshot = Assert.IsType<SelectionSnapshot>(result.Snapshot);
        Assert.True(snapshot.IsEditable);
        Assert.True(snapshot.AllowsReselection);
        Assert.Equal([8, 9, 10], snapshot.ElementRuntimeId);
        Assert.Equal(new WindowBounds(30, 50, 220, 20), Assert.Single(snapshot.Ranges[0].Bounds));
    }

    [Fact]
    public void Password_or_secure_elements_are_never_read()
    {
        var reader = new UiAutomationSelectionReader(
            new FakeSelectionProbeProvider(Node(
                isPassword: true,
                ranges: [Range(0, "must not escape")])),
            TimeProvider.System);

        var result = reader.Read(Target);

        Assert.Equal(UiAutomationSelectionReadStatus.SecureElement, result.Status);
        Assert.Null(result.Snapshot);
    }

    private static UiAutomationElementProbe Node(
        IReadOnlyList<int>? runtimeId = null,
        IReadOnlyList<UiAutomationSelectionRangeProbe>? ranges = null,
        UiAutomationElementProbe? parent = null,
        bool isPassword = false,
        bool isEditable = true) => new(
        runtimeId ?? [1, 2, 3],
        isPassword,
        IsEditable: isEditable,
        ranges,
        parent);

    private static UiAutomationSelectionRangeProbe Range(
        int documentOrder,
        string text,
        params WindowBounds[] bounds) => new(
        documentOrder,
        text,
        bounds.Length == 0 ? [new WindowBounds(10, 40, 100, 20)] : bounds,
        LeadingText: null,
        TrailingText: null);

    private sealed class FakeSelectionProbeProvider(UiAutomationElementProbe? focused)
        : IUiAutomationSelectionProbeProvider
    {
        public UiAutomationElementProbe? ReadFocusedElement(
            ForegroundTargetSnapshot target) => focused;
    }
}
