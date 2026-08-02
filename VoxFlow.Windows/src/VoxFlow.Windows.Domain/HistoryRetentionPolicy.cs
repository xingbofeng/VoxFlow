using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum HistoryRetentionMode
{
    [JsonStringEnumMemberName("disabled")]
    Disabled,

    [JsonStringEnumMemberName("retainForDays")]
    RetainForDays,

    [JsonStringEnumMemberName("forever")]
    Forever,
}

public sealed record HistoryRetentionPolicy
{
    [JsonConstructor]
    public HistoryRetentionPolicy(HistoryRetentionMode mode, int? days)
    {
        if (mode == HistoryRetentionMode.RetainForDays)
        {
            if (days is null or <= 0)
            {
                throw new ArgumentException(
                    "A day-based history policy requires a positive duration.",
                    nameof(days));
            }
        }
        else if (days is not null)
        {
            throw new ArgumentException(
                "Only a day-based history policy can carry a duration.",
                nameof(days));
        }

        Mode = mode;
        Days = days;
    }

    public static HistoryRetentionPolicy Disabled { get; } =
        new(HistoryRetentionMode.Disabled, null);

    public static HistoryRetentionPolicy Default { get; } = ForDays(30);

    public static HistoryRetentionPolicy Forever { get; } =
        new(HistoryRetentionMode.Forever, null);

    public HistoryRetentionMode Mode { get; }

    public int? Days { get; }

    public static HistoryRetentionPolicy ForDays(int days)
    {
        if (days <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(days), "Days must be positive.");
        }

        return new HistoryRetentionPolicy(HistoryRetentionMode.RetainForDays, days);
    }
}
