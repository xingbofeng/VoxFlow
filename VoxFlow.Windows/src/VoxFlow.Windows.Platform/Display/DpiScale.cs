namespace VoxFlow.Windows.Platform.Display;

public readonly record struct DpiScale
{
    private DpiScale(double factor)
    {
        Factor = factor;
    }

    public double Factor { get; }

    public static DpiScale FromPercent(int percent)
    {
        if (percent is < 50 or > 500)
        {
            throw new ArgumentOutOfRangeException(
                nameof(percent),
                percent,
                "A Windows DPI scale must be between 50% and 500%.");
        }

        return new DpiScale(percent / 100D);
    }

    public double ToDevicePixels(double logicalPixels) => logicalPixels * Factor;

    public double ToLogicalPixels(double devicePixels) => devicePixels / Factor;
}
