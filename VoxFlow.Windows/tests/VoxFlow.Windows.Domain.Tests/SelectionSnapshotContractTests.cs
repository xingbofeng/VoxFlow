using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class SelectionSnapshotContractTests
{
    [Fact]
    public void Selection_snapshot_round_trips_all_safe_relocation_fields()
    {
        var snapshot = CreateSnapshot();

        var json = JsonSerializer.Serialize(snapshot, DomainJson.Options);
        var restored = Assert.IsType<SelectionSnapshot>(
            JsonSerializer.Deserialize<SelectionSnapshot>(json, DomainJson.Options));

        Assert.Equal(snapshot.Text, restored.Text);
        Assert.Equal(SelectionAcquisitionSource.UiAutomation, restored.Source);
        Assert.Equal(0x1001, restored.Target.WindowHandle);
        Assert.Equal(4242, restored.Target.ProcessId);
        Assert.Equal("WINWORD.EXE", restored.Target.ProcessName);
        Assert.Equal("Quarterly plan.docx", restored.Target.WindowTitle);
        Assert.Equal(ProcessIntegrityLevel.Medium, restored.Target.IntegrityLevel);
        Assert.Equal([42, 7, 3], restored.Target.FocusedElementRuntimeId);
        Assert.Equal([42, 7, 9], restored.ElementRuntimeId);
        Assert.Equal(SelectionEditability.Editable, restored.Editability);
        Assert.True(restored.IsEditable);
        Assert.True(restored.AllowsReselection);
        Assert.Equal(2, restored.Ranges.Count);
        Assert.Equal("Q3 revenue: ¥12M", restored.Ranges[0].Text);
        Assert.Equal("Owner: Lin", restored.Ranges[1].Text);
        Assert.Equal("Prefix ", restored.Ranges[0].LeadingText);
        Assert.Equal(" suffix", restored.Ranges[1].TrailingText);
        Assert.Equal(1_720_000_000_100, restored.CapturedAtUnixMs);

        Assert.Contains("\"source\":\"uiAutomation\"", json, StringComparison.Ordinal);
        Assert.Contains("\"editability\":\"editable\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("isEditable", json, StringComparison.Ordinal);
    }

    [Fact]
    public void Snapshot_defensively_copies_runtime_ids_ranges_and_bounds()
    {
        var targetRuntimeId = new[] { 42, 1 };
        var elementRuntimeId = new[] { 42, 2 };
        var rangeBounds = new[] { new WindowBounds(10, 20, 30, 40) };
        var ranges = new[]
        {
            new SelectionRangeSnapshot(
                documentOrder: 0,
                text: "selected",
                bounds: rangeBounds,
                leadingText: null,
                trailingText: null),
        };
        var target = new ForegroundTargetSnapshot(
            windowHandle: 0x2002,
            processId: 84,
            processName: "notepad.exe",
            windowTitle: "Untitled",
            bounds: new WindowBounds(0, 0, 800, 600),
            integrityLevel: ProcessIntegrityLevel.Medium,
            focusedElementRuntimeId: targetRuntimeId,
            capturedAtUnixMs: 100);
        var snapshot = new SelectionSnapshot(
            text: "selected",
            source: SelectionAcquisitionSource.UiAutomation,
            target: target,
            elementRuntimeId: elementRuntimeId,
            ranges: ranges,
            editability: SelectionEditability.Editable,
            allowsReselection: true,
            capturedAtUnixMs: 101);

        targetRuntimeId[0] = -1;
        elementRuntimeId[0] = -1;
        rangeBounds[0] = new WindowBounds(100, 100, 1, 1);
        ranges[0] = new SelectionRangeSnapshot(
            0,
            "mutated",
            [],
            null,
            null);

        Assert.Equal(42, snapshot.Target.FocusedElementRuntimeId[0]);
        Assert.Equal(42, snapshot.ElementRuntimeId[0]);
        Assert.Equal(10, snapshot.Ranges[0].Bounds[0].Left);
        Assert.Equal("selected", snapshot.Ranges[0].Text);
    }

    [Fact]
    public void Shortcut_copy_snapshot_can_omit_uia_identity_and_ranges()
    {
        var target = new ForegroundTargetSnapshot(
            windowHandle: 0x3003,
            processId: 126,
            processName: "chrome.exe",
            windowTitle: "VoxFlow",
            bounds: new WindowBounds(50, 60, 1280, 720),
            integrityLevel: ProcessIntegrityLevel.Medium,
            focusedElementRuntimeId: [],
            capturedAtUnixMs: 200);

        var snapshot = new SelectionSnapshot(
            text: "copied selection",
            source: SelectionAcquisitionSource.ShortcutCopy,
            target: target,
            elementRuntimeId: [],
            ranges: [],
            editability: SelectionEditability.Unknown,
            allowsReselection: false,
            capturedAtUnixMs: 201);

        Assert.Empty(snapshot.ElementRuntimeId);
        Assert.Empty(snapshot.Ranges);
        Assert.False(snapshot.IsEditable);
    }

    [Fact]
    public void Uia_snapshot_requires_element_identity_and_a_non_empty_range()
    {
        var target = CreateTarget();

        Assert.Throws<ArgumentException>(() => new SelectionSnapshot(
            text: "selected",
            source: SelectionAcquisitionSource.UiAutomation,
            target: target,
            elementRuntimeId: [],
            ranges: [],
            editability: SelectionEditability.ReadOnly,
            allowsReselection: false,
            capturedAtUnixMs: target.CapturedAtUnixMs));
    }

    [Fact]
    public void Target_revalidation_result_has_stable_status_and_copy_fallback_semantics()
    {
        var ready = new SelectionTargetRevalidationResult(
            SelectionTargetRevalidationStatus.Ready);
        var ambiguous = new SelectionTargetRevalidationResult(
            SelectionTargetRevalidationStatus.AmbiguousSelection);

        Assert.True(ready.CanWrite);
        Assert.False(ready.ShouldCopyInstead);
        Assert.False(ambiguous.CanWrite);
        Assert.True(ambiguous.ShouldCopyInstead);
        Assert.Equal(
            "{\"status\":\"ambiguousSelection\"}",
            JsonSerializer.Serialize(ambiguous, DomainJson.Options));
    }

    private static SelectionSnapshot CreateSnapshot()
    {
        var target = CreateTarget();
        return new SelectionSnapshot(
            text: "Q3 revenue: ¥12M\nOwner: Lin",
            source: SelectionAcquisitionSource.UiAutomation,
            target: target,
            elementRuntimeId: [42, 7, 9],
            ranges:
            [
                new SelectionRangeSnapshot(
                    documentOrder: 0,
                    text: "Q3 revenue: ¥12M",
                    bounds: [new WindowBounds(100, 200, 280, 24)],
                    leadingText: "Prefix ",
                    trailingText: null),
                new SelectionRangeSnapshot(
                    documentOrder: 1,
                    text: "Owner: Lin",
                    bounds: [new WindowBounds(100, 230, 160, 24)],
                    leadingText: null,
                    trailingText: " suffix"),
            ],
            editability: SelectionEditability.Editable,
            allowsReselection: true,
            capturedAtUnixMs: 1_720_000_000_100);
    }

    private static ForegroundTargetSnapshot CreateTarget() => new(
        windowHandle: 0x1001,
        processId: 4242,
        processName: "WINWORD.EXE",
        windowTitle: "Quarterly plan.docx",
        bounds: new WindowBounds(80, 120, 1440, 900),
        integrityLevel: ProcessIntegrityLevel.Medium,
        focusedElementRuntimeId: [42, 7, 3],
        capturedAtUnixMs: 1_720_000_000_000);
}
