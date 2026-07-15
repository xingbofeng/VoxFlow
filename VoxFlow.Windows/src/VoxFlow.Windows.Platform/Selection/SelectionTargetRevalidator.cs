using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

public sealed record SelectionRevalidationRange(
    string Text,
    IReadOnlyList<WindowBounds> Bounds,
    string? LeadingText,
    string? TrailingText);

public sealed record SelectionRevalidationProbe(
    bool TargetExists,
    long WindowHandle,
    int ProcessId,
    ProcessIntegrityLevel IntegrityLevel,
    bool IsSecure,
    IReadOnlyList<int> ElementRuntimeId,
    IReadOnlyList<SelectionRevalidationRange> Candidates);

public interface ISelectionRevalidationProbeProvider
{
    SelectionRevalidationProbe Read(SelectionSnapshot snapshot);
}

/// <summary>
/// Re-selects a range only after <see cref="SelectionTargetRevalidator"/>
/// has proved that it still uniquely identifies the frozen target.  An
/// implementation must repeat its own UIA lookup: COM range objects captured
/// at the hotkey boundary are deliberately never retained.
/// </summary>
public interface ISelectionRangeReselector
{
    SelectionTargetRevalidationStatus Reselect(SelectionSnapshot snapshot);
}

/// <summary>
/// Decides whether a previously captured selection can be safely reselected.
/// The caller must use copy fallback for every non-ready result; this class
/// intentionally never chooses a best-effort similar range.
/// </summary>
public sealed class SelectionTargetRevalidator
{
    private readonly ISelectionRevalidationProbeProvider provider;
    private readonly ISelectionRangeReselector? reselector;

    public SelectionTargetRevalidator(
        ISelectionRevalidationProbeProvider provider,
        ISelectionRangeReselector? reselector = null)
    {
        this.provider = provider ?? throw new ArgumentNullException(nameof(provider));
        this.reselector = reselector;
    }

    public SelectionTargetRevalidationResult Revalidate(SelectionSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (!snapshot.AllowsReselection || !snapshot.IsEditable)
        {
            return Result(SelectionTargetRevalidationStatus.NotEditable);
        }

        var probe = provider.Read(snapshot);
        if (!probe.TargetExists)
        {
            return Result(SelectionTargetRevalidationStatus.TargetClosed);
        }
        if (probe.WindowHandle != snapshot.Target.WindowHandle
            || probe.ProcessId != snapshot.Target.ProcessId)
        {
            return Result(SelectionTargetRevalidationStatus.TargetChanged);
        }
        if (probe.IsSecure)
        {
            return Result(SelectionTargetRevalidationStatus.SecureTarget);
        }
        if (probe.IntegrityLevel > snapshot.Target.IntegrityLevel)
        {
            return Result(SelectionTargetRevalidationStatus.HigherIntegrityBlocked);
        }
        if (probe.IntegrityLevel != snapshot.Target.IntegrityLevel)
        {
            return Result(SelectionTargetRevalidationStatus.IntegrityLevelChanged);
        }

        if (!probe.ElementRuntimeId.SequenceEqual(snapshot.ElementRuntimeId))
        {
            return Result(SelectionTargetRevalidationStatus.ElementUnavailable);
        }

        var matchingCandidateIndexes = snapshot.Ranges.Select(range => probe.Candidates
            .Select((candidate, index) => (candidate, index))
            .Where(item => Matches(range, item.candidate))
            .Select(item => item.index)
            .ToArray()).ToArray();
        if (matchingCandidateIndexes.Any(matches => matches.Length == 0))
        {
            if (snapshot.Ranges.Any(range => probe.Candidates.Any(candidate =>
                MatchesLocation(range, candidate))))
            {
                return Result(SelectionTargetRevalidationStatus.SelectionTextChanged);
            }

            return Result(SelectionTargetRevalidationStatus.SelectionMissing);
        }
        if (matchingCandidateIndexes.Any(matches => matches.Length != 1)
            || matchingCandidateIndexes.Select(matches => matches[0]).Distinct().Count()
                != snapshot.Ranges.Count)
        {
            return Result(SelectionTargetRevalidationStatus.AmbiguousSelection);
        }

        return Result(SelectionTargetRevalidationStatus.Ready);
    }

    /// <summary>
    /// Verifies and then immediately recreates the original UIA selection.
    /// A non-ready result is deliberately terminal: callers must use their
    /// clipboard recovery path rather than pasting into whatever became
    /// foreground while a result panel was open.
    /// </summary>
    public SelectionTargetRevalidationResult RevalidateAndReselect(
        SelectionSnapshot snapshot)
    {
        var result = Revalidate(snapshot);
        if (!result.CanWrite || reselector is null)
        {
            return result;
        }

        return Result(reselector.Reselect(snapshot));
    }

    private static bool Matches(
        SelectionRangeSnapshot snapshot,
        SelectionRevalidationRange candidate) =>
        string.Equals(snapshot.Text, candidate.Text, StringComparison.Ordinal)
        && OptionalTextEquals(snapshot.LeadingText, candidate.LeadingText)
        && OptionalTextEquals(snapshot.TrailingText, candidate.TrailingText)
        && snapshot.Bounds.Count == candidate.Bounds.Count
        && snapshot.Bounds.Zip(candidate.Bounds, BoundsEqual).All(equal => equal);

    private static bool OptionalTextEquals(string? left, string? right) =>
        left is null || string.Equals(left, right, StringComparison.Ordinal);

    private static bool MatchesLocation(
        SelectionRangeSnapshot snapshot,
        SelectionRevalidationRange candidate) =>
        OptionalTextEquals(snapshot.LeadingText, candidate.LeadingText)
        && OptionalTextEquals(snapshot.TrailingText, candidate.TrailingText)
        && snapshot.Bounds.Count == candidate.Bounds.Count
        && snapshot.Bounds.Zip(candidate.Bounds, BoundsEqual).All(equal => equal);

    private static bool BoundsEqual(WindowBounds left, WindowBounds right) =>
        Math.Abs(left.Left - right.Left) <= 1
        && Math.Abs(left.Top - right.Top) <= 1
        && Math.Abs(left.Width - right.Width) <= 1
        && Math.Abs(left.Height - right.Height) <= 1;

    private static SelectionTargetRevalidationResult Result(
        SelectionTargetRevalidationStatus status) => new(status);
}
