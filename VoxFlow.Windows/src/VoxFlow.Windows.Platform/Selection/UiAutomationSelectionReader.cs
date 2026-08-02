using System.Runtime.InteropServices;
using System.Windows.Automation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

public enum UiAutomationSelectionReadStatus
{
    Captured,
    NoFocusedElement,
    NoSelection,
    SecureElement,
}

public sealed record UiAutomationSelectionReadResult(
    UiAutomationSelectionReadStatus Status,
    SelectionSnapshot? Snapshot);

/// <summary>
/// A managed projection of UI Automation state.  It deliberately contains no
/// AutomationElement or TextPatternRange so callers never retain COM-backed
/// range objects beyond the trigger-time read.
/// </summary>
public sealed record UiAutomationSelectionRangeProbe(
    int DocumentOrder,
    string Text,
    IReadOnlyList<WindowBounds> Bounds,
    string? LeadingText,
    string? TrailingText);

public sealed record UiAutomationElementProbe(
    IReadOnlyList<int> RuntimeId,
    bool IsPassword,
    bool IsEditable,
    IReadOnlyList<UiAutomationSelectionRangeProbe>? SelectionRanges,
    UiAutomationElementProbe? Parent,
    string? FocusedInputText = null,
    string? VisibleText = null);

public interface IUiAutomationSelectionProbeProvider
{
    UiAutomationElementProbe? ReadFocusedElement(ForegroundTargetSnapshot target);
}

public interface IUiAutomationSelectionReader
{
    UiAutomationSelectionReadResult Read(ForegroundTargetSnapshot target);
}

public sealed class UiAutomationSelectionReader : IUiAutomationSelectionReader
{
    private readonly IUiAutomationSelectionProbeProvider provider;
    private readonly TimeProvider timeProvider;

    public UiAutomationSelectionReader(
        IUiAutomationSelectionProbeProvider provider,
        TimeProvider timeProvider)
    {
        this.provider = provider ?? throw new ArgumentNullException(nameof(provider));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public UiAutomationSelectionReadResult Read(ForegroundTargetSnapshot target)
    {
        ArgumentNullException.ThrowIfNull(target);
        var element = provider.ReadFocusedElement(target);
        if (element is null)
        {
            return new(UiAutomationSelectionReadStatus.NoFocusedElement, null);
        }

        for (; element is not null; element = element.Parent)
        {
            if (element.IsPassword)
            {
                return new(UiAutomationSelectionReadStatus.SecureElement, null);
            }

            var ranges = element.SelectionRanges?
                .Where(range => !string.IsNullOrWhiteSpace(range.Text))
                .OrderBy(range => range.DocumentOrder)
                .ToArray();
            if (ranges is null || ranges.Length == 0)
            {
                continue;
            }

            var snapshotRanges = ranges.Select(range => new SelectionRangeSnapshot(
                range.DocumentOrder,
                range.Text,
                range.Bounds,
                range.LeadingText,
                range.TrailingText)).ToArray();
            var text = string.Join("\n", snapshotRanges.Select(range => range.Text));
            return new(
                UiAutomationSelectionReadStatus.Captured,
                new SelectionSnapshot(
                    text,
                    SelectionAcquisitionSource.UiAutomation,
                    target,
                    element.RuntimeId,
                    snapshotRanges,
                    element.IsEditable
                        ? SelectionEditability.Editable
                        : SelectionEditability.ReadOnly,
                    allowsReselection: true,
                    Math.Max(
                        target.CapturedAtUnixMs,
                        timeProvider.GetUtcNow().ToUnixTimeMilliseconds())));
        }

        return new(UiAutomationSelectionReadStatus.NoSelection, null);
    }
}

/// <summary>
/// The actual STA UI Automation boundary.  It copies selection text, bounds
/// and identity immediately, then releases all UIA objects before returning.
/// </summary>
public sealed class WindowsUiAutomationSelectionProbeProvider
    : IUiAutomationSelectionProbeProvider
{
    // UIA_TextPattern2Id. WPF exposes TextPattern but not a separate managed
    // TextPattern2 wrapper on every supported runtime.
    private const int TextPattern2Id = 10024;

    public UiAutomationElementProbe? ReadFocusedElement(ForegroundTargetSnapshot target)
    {
        ArgumentNullException.ThrowIfNull(target);
        try
        {
            var focused = AutomationElement.FocusedElement;
            if (focused is null)
            {
                return null;
            }

            var chain = new List<UiAutomationElementProbe>();
            for (var current = focused; current is not null;)
            {
                chain.Add(Project(current));
                current = TreeWalker.ControlViewWalker.GetParent(current);
            }

            UiAutomationElementProbe? parent = null;
            for (var index = chain.Count - 1; index >= 0; index--)
            {
                var node = chain[index];
                parent = node with { Parent = parent };
            }

            return parent;
        }
        catch (Exception exception) when (exception is ElementNotAvailableException
            or InvalidOperationException
            or COMException)
        {
            return null;
        }
    }

    private static UiAutomationElementProbe Project(AutomationElement element)
    {
        var current = element.Current;
        var ranges = ReadSelectionRanges(element);
        return new UiAutomationElementProbe(
            element.GetRuntimeId().ToArray(),
            current.IsPassword,
            IsEditable(element),
            ranges,
            Parent: null,
            FocusedInputText: current.IsPassword ? null : ReadInputText(element),
            VisibleText: current.IsPassword ? null : ReadVisibleText(element));
    }

    private static IReadOnlyList<UiAutomationSelectionRangeProbe>? ReadSelectionRanges(
        AutomationElement element)
    {
        var pattern = element.GetCurrentPattern(TextPattern.Pattern) as TextPattern
            ?? element.GetCurrentPattern(AutomationPattern.LookupById(TextPattern2Id)) as TextPattern;
        if (pattern is null)
        {
            return null;
        }

        return pattern.GetSelection()
            .Select((range, index) => new UiAutomationSelectionRangeProbe(
                index,
                range.GetText(-1),
                ToBounds(range.GetBoundingRectangles()),
                LeadingText: null,
                TrailingText: null))
            .ToArray();
    }

    private static bool IsEditable(AutomationElement element) =>
        element.GetCurrentPattern(ValuePattern.Pattern) is ValuePattern value
        && !value.Current.IsReadOnly;

    private static string? ReadInputText(AutomationElement element)
    {
        if (element.GetCurrentPattern(ValuePattern.Pattern) is not ValuePattern value)
        {
            return null;
        }
        return BoundText(value.Current.Value);
    }

    private static string? ReadVisibleText(AutomationElement element)
    {
        var pattern = element.GetCurrentPattern(TextPattern.Pattern) as TextPattern
            ?? element.GetCurrentPattern(AutomationPattern.LookupById(TextPattern2Id)) as TextPattern;
        return pattern is null ? null : BoundText(pattern.DocumentRange.GetText(-1));
    }

    private static string? BoundText(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }
        const int maximumCharacters = 8_000;
        return text.Length <= maximumCharacters ? text : text[..maximumCharacters];
    }

    private static IReadOnlyList<WindowBounds> ToBounds(System.Windows.Rect[] rectangles)
    {
        var bounds = new List<WindowBounds>(rectangles.Length);
        foreach (var rectangle in rectangles)
        {
            if (rectangle.Width > 0 && rectangle.Height > 0)
            {
                bounds.Add(new WindowBounds(
                    rectangle.Left,
                    rectangle.Top,
                    rectangle.Width,
                    rectangle.Height));
            }
        }

        return bounds;
    }
}
