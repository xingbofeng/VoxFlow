using VoxFlow.Windows.Application.History;

namespace VoxFlow.Windows.App.Home;

public enum HomeTextSourceFilter
{
    All,
    Qwen,
    TencentCloud,
    AliyunDashScope,
    Volcengine,
}

public sealed record HomeTextSourceFilterOption(
    HomeTextSourceFilter Value,
    string Label);

public sealed record HomeDashboardStatistics(
    int TotalDictations,
    int TodayDictations,
    int TotalCharacters,
    long TotalDurationMilliseconds)
{
    public static HomeDashboardStatistics Empty { get; } = new(0, 0, 0, 0);
}

public sealed record HomeActivityDay(
    DateOnly Date,
    int Count)
{
    public double Opacity => Count switch
    {
        <= 0 => 0.10,
        1 => 0.32,
        2 => 0.50,
        3 => 0.68,
        _ => 0.88,
    };
}

public sealed record HomeActivityWeek(IReadOnlyList<HomeActivityDay> Days);

public sealed record HomeHistoryItem(
    HistoryEntry Entry,
    bool IsSelected)
{
    public string Id => Entry.Id;

    public string FinalText => Entry.FinalText;

    public DateTimeOffset CreatedAtUtc => Entry.CreatedAtUtc;
}

internal static class HomeTextSource
{
    public static bool TryClassify(
        HistoryEntry entry,
        out HomeTextSourceFilter source)
    {
        if (entry.Metadata.AsrProvider is { } provider)
        {
            source = provider switch
            {
                Domain.AsrProviderId.Qwen => HomeTextSourceFilter.Qwen,
                Domain.AsrProviderId.TencentCloud => HomeTextSourceFilter.TencentCloud,
                Domain.AsrProviderId.AliyunDashScope => HomeTextSourceFilter.AliyunDashScope,
                Domain.AsrProviderId.Volcengine => HomeTextSourceFilter.Volcengine,
                _ => HomeTextSourceFilter.All,
            };
            return source != HomeTextSourceFilter.All;
        }

        var normalized = entry.Source.Trim().ToLowerInvariant();
        if (normalized.StartsWith("qwen", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.Qwen;
            return true;
        }

        if (normalized.StartsWith("tencent", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.TencentCloud;
            return true;
        }

        if (normalized.StartsWith("aliyun", StringComparison.Ordinal)
            || normalized.StartsWith("dashscope", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.AliyunDashScope;
            return true;
        }

        if (normalized.StartsWith("volcengine", StringComparison.Ordinal)
            || normalized.StartsWith("doubao", StringComparison.Ordinal))
        {
            source = HomeTextSourceFilter.Volcengine;
            return true;
        }

        source = HomeTextSourceFilter.All;
        return false;
    }
}
