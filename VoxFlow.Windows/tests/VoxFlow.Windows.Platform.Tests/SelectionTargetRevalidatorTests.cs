using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class SelectionTargetRevalidatorTests
{
    [Fact]
    public void Matching_runtime_id_text_and_bounds_are_ready_for_reselection()
    {
        var snapshot = Snapshot();
        var validator = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            candidates: [Candidate("chosen text")])));

        var result = validator.Revalidate(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.Ready, result.Status);
    }

    [Fact]
    public void Same_text_in_multiple_ranges_is_ambiguous_and_must_copy_instead()
    {
        var snapshot = Snapshot();
        var validator = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            candidates:
            [
                Candidate("chosen text", left: 10),
                Candidate("chosen text", left: 10),
            ])));

        var result = validator.Revalidate(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.AmbiguousSelection, result.Status);
        Assert.True(result.ShouldCopyInstead);
    }

    [Fact]
    public void Changed_window_or_higher_integrity_are_never_reselected()
    {
        var snapshot = Snapshot();
        var changed = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            windowHandle: 0x9999,
            candidates: [Candidate("chosen text")]))).Revalidate(snapshot);
        var elevated = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            integrity: ProcessIntegrityLevel.High,
            candidates: [Candidate("chosen text")]))).Revalidate(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.TargetChanged, changed.Status);
        Assert.Equal(SelectionTargetRevalidationStatus.HigherIntegrityBlocked, elevated.Status);
    }

    [Fact]
    public void Secure_or_missing_selection_is_never_writable()
    {
        var snapshot = Snapshot();
        var secure = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            isSecure: true,
            candidates: [Candidate("chosen text")]))).Revalidate(snapshot);
        var missing = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            candidates: []))).Revalidate(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.SecureTarget, secure.Status);
        Assert.Equal(SelectionTargetRevalidationStatus.SelectionMissing, missing.Status);
    }

    [Fact]
    public void Text_changed_at_the_original_range_is_not_silently_reselected()
    {
        var snapshot = Snapshot();
        var validator = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            candidates: [Candidate("edited text")])));

        var result = validator.Revalidate(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.SelectionTextChanged, result.Status);
        Assert.True(result.ShouldCopyInstead);
    }

    [Fact]
    public void Ready_snapshot_is_reselected_only_after_unique_revalidation()
    {
        var snapshot = Snapshot();
        var reselector = new FakeReselector(SelectionTargetRevalidationStatus.Ready);
        var validator = new SelectionTargetRevalidator(
            new FakeProbeProvider(Probe(snapshot, candidates: [Candidate("chosen text")])),
            reselector);

        var result = validator.RevalidateAndReselect(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.Ready, result.Status);
        Assert.Equal(1, reselector.CallCount);
    }

    [Fact]
    public void Ambiguous_snapshot_never_calls_the_range_reselector()
    {
        var snapshot = Snapshot();
        var reselector = new FakeReselector(SelectionTargetRevalidationStatus.Ready);
        var validator = new SelectionTargetRevalidator(
            new FakeProbeProvider(Probe(snapshot, candidates:
            [
                Candidate("chosen text"),
                Candidate("chosen text"),
            ])),
            reselector);

        var result = validator.RevalidateAndReselect(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.AmbiguousSelection, result.Status);
        Assert.Equal(0, reselector.CallCount);
    }

    [Fact]
    public void Runtime_id_change_is_not_reselected()
    {
        var snapshot = Snapshot();
        var validator = new SelectionTargetRevalidator(new FakeProbeProvider(Probe(
            snapshot,
            candidates: [Candidate("chosen text")]) with { ElementRuntimeId = [9, 9] }));

        var result = validator.Revalidate(snapshot);

        Assert.Equal(SelectionTargetRevalidationStatus.ElementUnavailable, result.Status);
    }

    private static SelectionSnapshot Snapshot() => new(
        "chosen text",
        SelectionAcquisitionSource.UiAutomation,
        new ForegroundTargetSnapshot(
            0x1234, 4242, "notepad.exe", "Draft",
            new WindowBounds(0, 0, 800, 600), ProcessIntegrityLevel.Medium,
            [1, 2, 3], 100),
        [1, 2, 3],
        [new SelectionRangeSnapshot(
            0,
            "chosen text",
            [new WindowBounds(10, 40, 80, 20)],
            "leading",
            "trailing")],
        SelectionEditability.Editable,
        allowsReselection: true,
        101);

    private static SelectionRevalidationProbe Probe(
        SelectionSnapshot snapshot,
        long? windowHandle = null,
        ProcessIntegrityLevel? integrity = null,
        bool isSecure = false,
        IReadOnlyList<SelectionRevalidationRange>? candidates = null) => new(
        TargetExists: true,
        WindowHandle: windowHandle ?? snapshot.Target.WindowHandle,
        ProcessId: snapshot.Target.ProcessId,
        IntegrityLevel: integrity ?? snapshot.Target.IntegrityLevel,
        IsSecure: isSecure,
        ElementRuntimeId: snapshot.ElementRuntimeId,
        Candidates: candidates ?? []);

    private static SelectionRevalidationRange Candidate(string text, double left = 10) => new(
        text,
        [new WindowBounds(left, 40, 80, 20)],
        "leading",
        "trailing");

    private sealed class FakeProbeProvider(SelectionRevalidationProbe probe)
        : ISelectionRevalidationProbeProvider
    {
        public SelectionRevalidationProbe Read(SelectionSnapshot snapshot) => probe;
    }

    private sealed class FakeReselector(SelectionTargetRevalidationStatus result)
        : ISelectionRangeReselector
    {
        public int CallCount { get; private set; }

        public SelectionTargetRevalidationStatus Reselect(SelectionSnapshot snapshot)
        {
            CallCount++;
            return result;
        }
    }
}
