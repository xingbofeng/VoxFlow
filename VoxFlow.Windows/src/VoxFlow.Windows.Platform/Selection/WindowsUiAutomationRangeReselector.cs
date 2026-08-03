using System.Runtime.InteropServices;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

/// <summary>
/// Reads fresh UIA state for a frozen selection.  It is intentionally used
/// only at write time; the original capture keeps no COM objects alive.
/// </summary>
public sealed class WindowsUiAutomationSelectionRevalidationProbeProvider
    : ISelectionRevalidationProbeProvider
{
    private readonly IWin32ForegroundSelectionApi foreground;

    public WindowsUiAutomationSelectionRevalidationProbeProvider(
        IWin32ForegroundSelectionApi foreground)
    {
        this.foreground = foreground ?? throw new ArgumentNullException(nameof(foreground));
    }

    public SelectionRevalidationProbe Read(SelectionSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var currentTarget = foreground.ReadForeground();
        if (currentTarget is null)
        {
            return MissingTarget(snapshot);
        }

        if (currentTarget.WindowHandle != snapshot.Target.WindowHandle
            || currentTarget.ProcessId != snapshot.Target.ProcessId)
        {
            return FromCurrentTarget(currentTarget, isSecure: false, [], []);
        }

        try
        {
            var element = UiAutomationRangeLocator.FindElement(snapshot);
            if (element is null)
            {
                return FromCurrentTarget(currentTarget, isSecure: false, [], []);
            }

            var current = element.Current;
            if (current.IsPassword)
            {
                return FromCurrentTarget(currentTarget, isSecure: true, element.GetRuntimeId(), []);
            }

            var ranges = UiAutomationRangeLocator.FindCandidates(element, snapshot.Ranges);
            return FromCurrentTarget(
                currentTarget,
                isSecure: false,
                element.GetRuntimeId(),
                ranges);
        }
        catch (Exception exception) when (UiAutomationRangeLocator.IsRecoverable(exception))
        {
            // The caller receives ElementUnavailable rather than a UIA dump.
            return FromCurrentTarget(currentTarget, isSecure: false, [], []);
        }
    }

    private static SelectionRevalidationProbe MissingTarget(SelectionSnapshot snapshot) => new(
        TargetExists: false,
        snapshot.Target.WindowHandle,
        snapshot.Target.ProcessId,
        snapshot.Target.IntegrityLevel,
        IsSecure: false,
        [],
        []);

    private static SelectionRevalidationProbe FromCurrentTarget(
        ForegroundWindowProbe target,
        bool isSecure,
        IReadOnlyList<int> runtimeId,
        IReadOnlyList<SelectionRevalidationRange> candidates) => new(
        TargetExists: true,
        target.WindowHandle,
        target.ProcessId,
        target.IntegrityLevel,
        isSecure,
        runtimeId.ToArray(),
        candidates.ToArray());
}

/// <summary>
/// Recreates the uniquely located UIA range immediately before a write.  It
/// never falls back to a similar text occurrence, a different window, or the
/// current foreground target.
/// </summary>
public sealed class WindowsUiAutomationRangeReselector : ISelectionRangeReselector
{
    private readonly IWin32ForegroundSelectionApi foreground;

    public WindowsUiAutomationRangeReselector(IWin32ForegroundSelectionApi foreground)
    {
        this.foreground = foreground ?? throw new ArgumentNullException(nameof(foreground));
    }

    public SelectionTargetRevalidationStatus Reselect(SelectionSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var currentTarget = foreground.ReadForeground();
        if (currentTarget is null)
        {
            return SelectionTargetRevalidationStatus.TargetClosed;
        }
        if (currentTarget.WindowHandle != snapshot.Target.WindowHandle
            || currentTarget.ProcessId != snapshot.Target.ProcessId)
        {
            return SelectionTargetRevalidationStatus.TargetChanged;
        }
        if (currentTarget.IntegrityLevel > snapshot.Target.IntegrityLevel)
        {
            return SelectionTargetRevalidationStatus.HigherIntegrityBlocked;
        }
        if (currentTarget.IntegrityLevel != snapshot.Target.IntegrityLevel)
        {
            return SelectionTargetRevalidationStatus.IntegrityLevelChanged;
        }

        try
        {
            var element = UiAutomationRangeLocator.FindElement(snapshot);
            if (element is null || element.Current.IsPassword)
            {
                return element is null
                    ? SelectionTargetRevalidationStatus.ElementUnavailable
                    : SelectionTargetRevalidationStatus.SecureTarget;
            }
            if (!UiAutomationRangeLocator.IsEditable(element))
            {
                return SelectionTargetRevalidationStatus.NotEditable;
            }

            var ranges = UiAutomationRangeLocator.FindUniqueRanges(element, snapshot.Ranges);
            if (ranges.Status != SelectionTargetRevalidationStatus.Ready)
            {
                return ranges.Status;
            }

            ranges.Ranges[0].Select();
            foreach (var range in ranges.Ranges.Skip(1))
            {
                range.AddToSelection();
            }

            return SelectionTargetRevalidationStatus.Ready;
        }
        catch (COMException)
        {
            return SelectionTargetRevalidationStatus.UipiBlocked;
        }
        catch (Exception exception) when (UiAutomationRangeLocator.IsRecoverable(exception))
        {
            return SelectionTargetRevalidationStatus.ElementUnavailable;
        }
    }
}

internal static class UiAutomationRangeLocator
{
    private const int TextPattern2Id = 10024;
    private const int SearchLimit = 256;

    public static bool IsRecoverable(Exception exception) => exception is ElementNotAvailableException
        or InvalidOperationException
        or COMException;

    public static AutomationElement? FindElement(SelectionSnapshot snapshot)
    {
        var root = AutomationElement.FromHandle((nint)snapshot.Target.WindowHandle);
        if (root is null)
        {
            return null;
        }

        if (root.GetRuntimeId().SequenceEqual(snapshot.ElementRuntimeId))
        {
            return root;
        }

        foreach (AutomationElement candidate in root.FindAll(
                     TreeScope.Descendants,
                     Condition.TrueCondition))
        {
            if (candidate.GetRuntimeId().SequenceEqual(snapshot.ElementRuntimeId))
            {
                return candidate;
            }
        }

        return null;
    }

    public static bool IsEditable(AutomationElement element) =>
        element.GetCurrentPattern(ValuePattern.Pattern) is ValuePattern value
        && !value.Current.IsReadOnly;

    public static IReadOnlyList<SelectionRevalidationRange> FindCandidates(
        AutomationElement element,
        IReadOnlyList<SelectionRangeSnapshot> snapshots)
    {
        var pattern = GetTextPattern(element);
        if (pattern is null)
        {
            return [];
        }

        var candidates = new List<SelectionRevalidationRange>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var snapshot in snapshots)
        {
            foreach (var range in FindTextRanges(pattern, snapshot.Text))
            {
                var candidate = ToCandidate(range);
                var identity = CandidateIdentity(candidate);
                if (seen.Add(identity))
                {
                    candidates.Add(candidate);
                }
            }
        }

        return candidates;
    }

    public static (SelectionTargetRevalidationStatus Status, IReadOnlyList<TextPatternRange> Ranges)
        FindUniqueRanges(
            AutomationElement element,
            IReadOnlyList<SelectionRangeSnapshot> snapshots)
    {
        var pattern = GetTextPattern(element);
        if (pattern is null)
        {
            return (SelectionTargetRevalidationStatus.ElementUnavailable, []);
        }

        var selected = new List<TextPatternRange>(snapshots.Count);
        var selectedIdentities = new HashSet<string>(StringComparer.Ordinal);
        foreach (var snapshot in snapshots)
        {
            var matches = FindTextRanges(pattern, snapshot.Text)
                .Where(range => Matches(snapshot, ToCandidate(range)))
                .ToArray();
            if (matches.Length == 0)
            {
                var textChanged = FindTextRanges(pattern, snapshot.Text)
                    .Any(range => MatchesLocation(snapshot, ToCandidate(range)));
                return (textChanged
                    ? SelectionTargetRevalidationStatus.SelectionTextChanged
                    : SelectionTargetRevalidationStatus.SelectionMissing, []);
            }
            if (matches.Length != 1)
            {
                return (SelectionTargetRevalidationStatus.AmbiguousSelection, []);
            }

            var candidateIdentity = CandidateIdentity(ToCandidate(matches[0]));
            if (!selectedIdentities.Add(candidateIdentity))
            {
                return (SelectionTargetRevalidationStatus.AmbiguousSelection, []);
            }

            selected.Add(matches[0]);
        }

        return (SelectionTargetRevalidationStatus.Ready, selected);
    }

    private static TextPattern? GetTextPattern(AutomationElement element) =>
        element.GetCurrentPattern(TextPattern.Pattern) as TextPattern
        ?? element.GetCurrentPattern(AutomationPattern.LookupById(TextPattern2Id)) as TextPattern;

    private static IEnumerable<TextPatternRange> FindTextRanges(TextPattern pattern, string text)
    {
        var search = pattern.DocumentRange.Clone();
        for (var count = 0; count < SearchLimit; count++)
        {
            var match = search.FindText(text, backward: false, ignoreCase: false);
            if (match is null)
            {
                yield break;
            }

            yield return match;
            var next = match.Clone();
            next.MoveEndpointByRange(
                TextPatternRangeEndpoint.Start,
                match,
                TextPatternRangeEndpoint.End);
            if (next.Compare(search))
            {
                yield break;
            }

            search = next;
        }
    }

    private static SelectionRevalidationRange ToCandidate(TextPatternRange range) => new(
        range.GetText(-1),
        ToBounds(range.GetBoundingRectangles()),
        LeadingText: null,
        TrailingText: null);

    private static IReadOnlyList<WindowBounds> ToBounds(System.Windows.Rect[] rectangles) => rectangles
        .Where(rectangle => rectangle.Width > 0 && rectangle.Height > 0)
        .Select(rectangle => new WindowBounds(
            rectangle.Left,
            rectangle.Top,
            rectangle.Width,
            rectangle.Height))
        .ToArray();

    private static bool Matches(SelectionRangeSnapshot snapshot, SelectionRevalidationRange candidate) =>
        string.Equals(snapshot.Text, candidate.Text, StringComparison.Ordinal)
        && OptionalTextEquals(snapshot.LeadingText, candidate.LeadingText)
        && OptionalTextEquals(snapshot.TrailingText, candidate.TrailingText)
        && BoundsMatch(snapshot.Bounds, candidate.Bounds);

    private static bool MatchesLocation(SelectionRangeSnapshot snapshot, SelectionRevalidationRange candidate) =>
        OptionalTextEquals(snapshot.LeadingText, candidate.LeadingText)
        && OptionalTextEquals(snapshot.TrailingText, candidate.TrailingText)
        && BoundsMatch(snapshot.Bounds, candidate.Bounds);

    private static bool OptionalTextEquals(string? left, string? right) =>
        left is null || string.Equals(left, right, StringComparison.Ordinal);

    private static bool BoundsMatch(IReadOnlyList<WindowBounds> left, IReadOnlyList<WindowBounds> right) =>
        left.Count == right.Count
        && left.Zip(right, (a, b) =>
            Math.Abs(a.Left - b.Left) <= 1
            && Math.Abs(a.Top - b.Top) <= 1
            && Math.Abs(a.Width - b.Width) <= 1
            && Math.Abs(a.Height - b.Height) <= 1).All(match => match);

    private static string CandidateIdentity(SelectionRevalidationRange candidate) => string.Join(
        '|',
        candidate.Text,
        string.Join(';', candidate.Bounds.Select(bound => FormattableString.Invariant(
            $"{bound.Left},{bound.Top},{bound.Width},{bound.Height}"))));
}
