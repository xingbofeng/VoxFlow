using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WindowsAgentContextReaderTests
{
    [Fact]
    public async Task Selected_input_and_visible_text_are_projected_without_com_objects()
    {
        var target = Target();
        var reader = new WindowsAgentContextReader(new FakeProbe(Node(
            selection: [new UiAutomationSelectionRangeProbe(0, "selected", [], null, null)],
            input: "focused input",
            visible: "visible text")));

        var result = await reader.ReadAsync(target, CancellationToken.None);

        Assert.Equal("selected", result.Selection?.Text);
        Assert.Equal("focused input", result.FocusedInputText);
        Assert.Equal("visible text", result.VisibleText);
        Assert.False(result.IsSecure);
    }

    [Fact]
    public async Task Password_chain_is_reported_as_secure_without_text()
    {
        var reader = new WindowsAgentContextReader(new FakeProbe(Node(
            selection: [new UiAutomationSelectionRangeProbe(0, "secret", [], null, null)],
            input: "secret",
            visible: "secret",
            password: true)));

        var result = await reader.ReadAsync(Target(), CancellationToken.None);

        Assert.True(result.IsSecure);
        Assert.Null(result.Selection);
        Assert.Null(result.FocusedInputText);
        Assert.Null(result.VisibleText);
    }

    private static ForegroundTargetSnapshot Target() => new(
        1, 2, "notepad.exe", "Draft", new WindowBounds(0, 0, 100, 100),
        ProcessIntegrityLevel.Medium, [1], 1);

    private static UiAutomationElementProbe Node(
        IReadOnlyList<UiAutomationSelectionRangeProbe>? selection,
        string? input,
        string? visible,
        bool password = false) => new(
        [1], password, IsEditable: true, selection, Parent: null,
        FocusedInputText: input, VisibleText: visible);

    private sealed class FakeProbe(UiAutomationElementProbe probe)
        : IUiAutomationSelectionProbeProvider
    {
        public UiAutomationElementProbe? ReadFocusedElement(
            ForegroundTargetSnapshot target) => probe;
    }
}
