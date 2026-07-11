using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public sealed record WindowBounds
{
    [JsonConstructor]
    public WindowBounds(double left, double top, double width, double height)
    {
        if (!double.IsFinite(left) ||
            !double.IsFinite(top) ||
            !double.IsFinite(width) ||
            !double.IsFinite(height) ||
            width <= 0 ||
            height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(width),
                "Window bounds must be finite with a positive width and height.");
        }

        Left = left;
        Top = top;
        Width = width;
        Height = height;
    }

    public double Left { get; }

    public double Top { get; }

    public double Width { get; }

    public double Height { get; }
}

public sealed record UiState
{
    [JsonConstructor]
    public UiState(
        string? monitorId,
        WindowBounds? mainWindowBounds,
        bool isSidebarCollapsed)
    {
        if (monitorId is not null && string.IsNullOrWhiteSpace(monitorId))
        {
            throw new ArgumentException(
                "A monitor identifier must be null or non-blank.",
                nameof(monitorId));
        }

        MonitorId = monitorId;
        MainWindowBounds = mainWindowBounds;
        IsSidebarCollapsed = isSidebarCollapsed;
    }

    public string? MonitorId { get; }

    public WindowBounds? MainWindowBounds { get; }

    public bool IsSidebarCollapsed { get; }
}
