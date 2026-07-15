using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class ForegroundTargetComparisonTests
{
    private static readonly ForegroundTargetIdentity Original = new(
        processId: 101,
        processPath: @"C:\Apps\Editor\editor.exe",
        windowHandle: new nint(0x1001),
        windowTitle: "Document A");

    [Fact]
    public void Same_process_path_pid_and_window_remain_safe_for_output()
    {
        var current = Original with { WindowTitle = "Document A — edited" };

        Assert.Equal(
            ForegroundTargetComparison.SameTarget,
            ForegroundTargetComparer.Compare(
                Original,
                current,
                ForegroundTargetLiveness.Exists));
    }

    [Fact]
    public void Original_process_disappearing_is_not_misclassified_as_target_changed()
    {
        var unrelatedCurrent = new ForegroundTargetIdentity(
            202,
            @"C:\Apps\Browser\browser.exe",
            new nint(0x2002),
            "New tab");

        Assert.Equal(
            ForegroundTargetComparison.OriginalNoLongerExists,
            ForegroundTargetComparer.Compare(
                Original,
                unrelatedCurrent,
                ForegroundTargetLiveness.Missing));
    }

    [Theory]
    [InlineData(202, @"C:\Apps\Editor\editor.exe")]
    [InlineData(101, @"C:\Apps\Other\other.exe")]
    public void Process_identity_change_is_target_changed(int pid, string path)
    {
        var current = Original with
        {
            ProcessId = pid,
            ProcessPath = path,
        };

        Assert.Equal(
            ForegroundTargetComparison.TargetChanged,
            ForegroundTargetComparer.Compare(
                Original,
                current,
                ForegroundTargetLiveness.Exists));
    }

    [Fact]
    public void Same_application_but_different_nonzero_hwnd_is_target_changed()
    {
        var current = Original with
        {
            WindowHandle = new nint(0x1002),
            WindowTitle = "Document B",
        };

        Assert.Equal(
            ForegroundTargetComparison.TargetChanged,
            ForegroundTargetComparer.Compare(
                Original,
                current,
                ForegroundTargetLiveness.Exists));
    }

    [Fact]
    public void Current_target_unavailable_is_explicit_and_never_treated_as_same()
    {
        Assert.Equal(
            ForegroundTargetComparison.CurrentUnavailable,
            ForegroundTargetComparer.Compare(
                Original,
                current: null,
                ForegroundTargetLiveness.Exists));
    }

    [Fact]
    public void Path_comparison_is_windows_case_insensitive_and_title_is_diagnostic_only()
    {
        var current = Original with
        {
            ProcessPath = @"c:\apps\EDITOR\EDITOR.EXE",
            WindowTitle = "Renamed document",
        };

        Assert.Equal(
            ForegroundTargetComparison.SameTarget,
            ForegroundTargetComparer.Compare(
                Original,
                current,
                ForegroundTargetLiveness.Exists));
    }

    [Fact]
    public void Unknown_original_liveness_is_never_allowed_to_inject()
    {
        var current = new ForegroundTargetIdentity(
            202,
            @"C:\Apps\Browser\browser.exe",
            new nint(0x2002),
            "New tab");

        var comparison = ForegroundTargetComparer.Compare(
            Original,
            current,
            ForegroundTargetLiveness.Unknown);
        var decision = TargetAwareOutputPolicy.Decide(comparison);

        Assert.Equal(ForegroundTargetComparison.OriginalLivenessUnknown, comparison);
        Assert.Equal(TargetAwareOutputAction.Copy, decision.Action);
        Assert.Equal(OutputResultKind.TargetChanged, decision.Result?.Kind);
    }
}
