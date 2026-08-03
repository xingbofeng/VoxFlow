using System.Collections.ObjectModel;
using System.ComponentModel;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain.Screenshots;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotToolbarAction
{
    Select,
    Pen,
    Ellipse,
    Rectangle,
    Arrow,
    DotMarker,
    NumberedMarker,
    Text,
    Mosaic,
    TextRecognition,
    Translate,
    Color,
    LineWidth,
    FontSize,
    Copy,
    Paste,
    Duplicate,
    Undo,
    Redo,
    Download,
    Cancel,
    Complete,
}

public sealed class ScreenshotToolbarItemViewModel : INotifyPropertyChanged
{
    private bool isActive;
    private bool isEnabled = true;
    private AnnotationColor currentColor = AnnotationStyle.Default.Color;
    private double currentLineWidth = AnnotationStyle.Default.LineWidth;
    private string currentFontSizeLabel = string.Empty;
    private string? currentValueLabel;

    public event PropertyChangedEventHandler? PropertyChanged;

    public required ScreenshotToolbarAction Action { get; init; }

    public required string Glyph { get; init; }

    public required string Label { get; init; }

    public bool IsActive
    {
        get => isActive;
        set
        {
            if (isActive == value)
            {
                return;
            }
            isActive = value;
            RaisePropertyChanged(nameof(IsActive));
            RaisePropertyChanged(nameof(AutomationItemStatus));
        }
    }

    public bool IsEnabled
    {
        get => isEnabled;
        set
        {
            if (isEnabled == value)
            {
                return;
            }
            isEnabled = value;
            RaisePropertyChanged(nameof(IsEnabled));
        }
    }

    public bool IsPrimary => Action == ScreenshotToolbarAction.Complete;

    public bool IsDestructive => Action == ScreenshotToolbarAction.Cancel;

    public string AutomationId => $"screenshot.toolbar.{Action.ToString().ToLowerInvariant()}";

    public string AutomationItemStatus => IsActive
        ? L10n.Localize("ScreenshotToolbarSelectedStatus")
        : string.Empty;

    public string HelpText => currentValueLabel is null
        ? Label
        : string.Format(
            System.Globalization.CultureInfo.CurrentCulture,
            L10n.Localize("ScreenshotToolbarCurrentValueFormat"),
            Label,
            currentValueLabel);

    public bool IsStyleIndicator => Action is ScreenshotToolbarAction.Color
        or ScreenshotToolbarAction.LineWidth
        or ScreenshotToolbarAction.FontSize;

    public bool IsColorIndicator => Action == ScreenshotToolbarAction.Color;

    public bool IsLineWidthIndicator => Action == ScreenshotToolbarAction.LineWidth;

    public bool IsFontSizeIndicator => Action == ScreenshotToolbarAction.FontSize;

    public System.Windows.Media.Brush CurrentColorBrush =>
        ScreenshotDrawingPrimitives.Brush(currentColor);

    public double CurrentLineWidth => currentLineWidth;

    public string CurrentFontSizeLabel => currentFontSizeLabel;

    internal void UpdateStyleState(
        AnnotationColor color,
        double lineWidth,
        string fontSizeLabel,
        string? accessibleValueLabel)
    {
        currentColor = color;
        currentLineWidth = lineWidth;
        currentFontSizeLabel = fontSizeLabel;
        currentValueLabel = accessibleValueLabel;
        RaisePropertyChanged(nameof(CurrentColorBrush));
        RaisePropertyChanged(nameof(CurrentLineWidth));
        RaisePropertyChanged(nameof(CurrentFontSizeLabel));
        RaisePropertyChanged(nameof(HelpText));
    }

    private void RaisePropertyChanged(string propertyName) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public static class ScreenshotToolbarCatalog
{
    public const double ItemSize = 28;
    public const double ItemSpacing = 4;
    public const double ContentPadding = 8;
    public const double Height = 44;
    public const double PopoverOptionSize = 28;
    public const double PopoverOptionSpacing = 8;
    public const double PopoverPadding = 8;
    public const double PopoverCornerRadius = 9;

    public static ScreenshotToolbarLayout LayoutFor(
        int itemCount,
        int availablePhysicalWidth,
        double dpiX,
        double dpiY)
    {
        if (itemCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(itemCount));
        }
        if (availablePhysicalWidth <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(availablePhysicalWidth));
        }
        if (!double.IsFinite(dpiX) || dpiX <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dpiX));
        }
        if (!double.IsFinite(dpiY) || dpiY <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dpiY));
        }

        var availableDipWidth = availablePhysicalWidth * 96D / dpiX;
        var maximumColumns = Math.Max(
            1,
            (int)Math.Floor(
                (availableDipWidth - (ContentPadding * 2) + ItemSpacing)
                / (ItemSize + ItemSpacing)));
        var columns = Math.Min(itemCount, maximumColumns);
        var rows = checked((itemCount + columns - 1) / columns);
        var desiredDipWidth = WidthFor(columns);
        var desiredDipHeight = (ContentPadding * 2)
            + (rows * ItemSize)
            + ((rows - 1) * ItemSpacing);
        var physicalWidth = Math.Min(
            availablePhysicalWidth,
            Math.Max(1, checked((int)Math.Round(desiredDipWidth * dpiX / 96D))));
        var physicalHeight = Math.Max(
            1,
            checked((int)Math.Round(desiredDipHeight * dpiY / 96D)));
        return new ScreenshotToolbarLayout(
            desiredDipWidth,
            desiredDipHeight,
            physicalWidth,
            physicalHeight,
            columns,
            rows);
    }

    public static IReadOnlyList<ScreenshotToolbarItemViewModel> Create() =>
        new ReadOnlyCollection<ScreenshotToolbarItemViewModel>(
        [
            Item(ScreenshotToolbarAction.Select, "⌖", "ScreenshotToolSelect"),
            Item(ScreenshotToolbarAction.Pen, "✎", "ScreenshotToolPen"),
            Item(ScreenshotToolbarAction.Ellipse, "○", "ScreenshotToolEllipse"),
            Item(ScreenshotToolbarAction.Rectangle, "□", "ScreenshotToolRectangle"),
            Item(ScreenshotToolbarAction.Arrow, "↗", "ScreenshotToolArrow"),
            Item(ScreenshotToolbarAction.DotMarker, "●", "ScreenshotToolDotMarker"),
            Item(ScreenshotToolbarAction.NumberedMarker, "①", "ScreenshotToolNumberedMarker"),
            Item(ScreenshotToolbarAction.Text, "T", "ScreenshotToolText"),
            Item(ScreenshotToolbarAction.Mosaic, "▦", "ScreenshotToolMosaic"),
            Item(ScreenshotToolbarAction.TextRecognition, "OCR", "ScreenshotToolTextRecognition"),
            Item(ScreenshotToolbarAction.Translate, "A↔", "ScreenshotToolTranslate"),
            Item(ScreenshotToolbarAction.Color, "◉", "ScreenshotToolColor"),
            Item(ScreenshotToolbarAction.LineWidth, "≡", "ScreenshotToolLineWidth"),
            Item(ScreenshotToolbarAction.FontSize, "A", "ScreenshotToolFontSize"),
            Item(ScreenshotToolbarAction.Copy, "▣", "ScreenshotToolCopy"),
            Item(ScreenshotToolbarAction.Paste, "▤", "ScreenshotToolPaste"),
            Item(ScreenshotToolbarAction.Duplicate, "⧉", "ScreenshotToolDuplicate"),
            Item(ScreenshotToolbarAction.Undo, "↶", "ScreenshotToolUndo"),
            Item(ScreenshotToolbarAction.Redo, "↷", "ScreenshotToolRedo"),
            Item(ScreenshotToolbarAction.Download, "⇩", "ScreenshotToolDownload"),
            Item(ScreenshotToolbarAction.Cancel, "×", "ScreenshotToolCancel"),
            Item(ScreenshotToolbarAction.Complete, "✓", "ScreenshotToolComplete"),
        ]);

    public static double WidthFor(int itemCount)
    {
        if (itemCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(itemCount));
        }
        return (ContentPadding * 2)
            + (itemCount * ItemSize)
            + ((itemCount - 1) * ItemSpacing);
    }

    public static ScreenshotTool? ToTool(ScreenshotToolbarAction action) => action switch
    {
        ScreenshotToolbarAction.Select => ScreenshotTool.Select,
        ScreenshotToolbarAction.Pen => ScreenshotTool.Pen,
        ScreenshotToolbarAction.Ellipse => ScreenshotTool.Ellipse,
        ScreenshotToolbarAction.Rectangle => ScreenshotTool.Rectangle,
        ScreenshotToolbarAction.Arrow => ScreenshotTool.Arrow,
        ScreenshotToolbarAction.DotMarker => ScreenshotTool.DotMarker,
        ScreenshotToolbarAction.NumberedMarker => ScreenshotTool.NumberedMarker,
        ScreenshotToolbarAction.Text => ScreenshotTool.Text,
        ScreenshotToolbarAction.Mosaic => ScreenshotTool.Mosaic,
        ScreenshotToolbarAction.TextRecognition => ScreenshotTool.TextRecognition,
        ScreenshotToolbarAction.Translate => ScreenshotTool.Translate,
        _ => null,
    };

    private static ScreenshotToolbarItemViewModel Item(
        ScreenshotToolbarAction action,
        string glyph,
        string resourceKey) => new()
    {
        Action = action,
        Glyph = glyph,
        Label = L10n.Localize(resourceKey),
        IsActive = action == ScreenshotToolbarAction.Select,
    };
}

public sealed record ScreenshotToolbarLayout(
    double DipWidth,
    double DipHeight,
    int PhysicalWidth,
    int PhysicalHeight,
    int Columns,
    int Rows);
