namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotTransformCache : IScreenshotTransformCache
{
    public const int DefaultCapacity = 128;

    public static readonly TimeSpan DefaultTimeToLive = TimeSpan.FromMinutes(30);

    private readonly object synchronization = new();
    private readonly Dictionary<string, CacheEntry> entries =
        new(StringComparer.Ordinal);
    private readonly LinkedList<string> recency = [];
    private readonly int capacity;
    private readonly TimeSpan timeToLive;
    private readonly TimeProvider timeProvider;

    public ScreenshotTransformCache(
        int capacity = DefaultCapacity,
        TimeSpan? timeToLive = null,
        TimeProvider? timeProvider = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(capacity);
        var configuredTimeToLive = timeToLive ?? DefaultTimeToLive;
        if (configuredTimeToLive <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(
                nameof(timeToLive),
                "The cache time-to-live must be positive.");
        }
        this.capacity = capacity;
        this.timeToLive = configuredTimeToLive;
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public bool TryGet(ScreenshotTransformRequest request, out string text)
    {
        ArgumentNullException.ThrowIfNull(request);
        lock (synchronization)
        {
            var now = timeProvider.GetUtcNow();
            if (entries.TryGetValue(request.CacheKey, out var entry))
            {
                if (entry.ExpiresAtUtc <= now)
                {
                    RemoveEntry(request.CacheKey);
                }
                else
                {
                    recency.Remove(entry.RecencyNode);
                    recency.AddLast(entry.RecencyNode);
                    text = entry.Text;
                    return true;
                }
            }
        }
        text = string.Empty;
        return false;
    }

    public void Store(ScreenshotTransformRequest request, string text)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        lock (synchronization)
        {
            var now = timeProvider.GetUtcNow();
            RemoveExpiredEntries(now);
            RemoveEntry(request.CacheKey);
            var recencyNode = recency.AddLast(request.CacheKey);
            entries.Add(
                request.CacheKey,
                new CacheEntry(
                    request.ScreenshotId,
                    text,
                    GetExpiration(now),
                    recencyNode));
            while (entries.Count > capacity)
            {
                RemoveEntry(recency.First!.Value);
            }
        }
    }

    public int Invalidate(string screenshotId)
    {
        var id = ScreenshotValueValidation.RequireId(screenshotId);
        lock (synchronization)
        {
            var now = timeProvider.GetUtcNow();
            RemoveExpiredEntries(now);
            var keys = entries
                .Where(pair => string.Equals(
                    pair.Value.ScreenshotId,
                    id,
                    StringComparison.Ordinal))
                .Select(pair => pair.Key)
                .ToArray();
            foreach (var key in keys)
            {
                RemoveEntry(key);
            }
            return keys.Length;
        }
    }

    private DateTimeOffset GetExpiration(DateTimeOffset now)
    {
        try
        {
            return now.Add(timeToLive);
        }
        catch (ArgumentOutOfRangeException)
        {
            return DateTimeOffset.MaxValue;
        }
    }

    private void RemoveExpiredEntries(DateTimeOffset now)
    {
        var expiredKeys = entries
            .Where(pair => pair.Value.ExpiresAtUtc <= now)
            .Select(pair => pair.Key)
            .ToArray();
        foreach (var key in expiredKeys)
        {
            RemoveEntry(key);
        }
    }

    private void RemoveEntry(string cacheKey)
    {
        if (!entries.Remove(cacheKey, out var entry))
        {
            return;
        }
        recency.Remove(entry.RecencyNode);
    }

    private sealed record CacheEntry(
        string ScreenshotId,
        string Text,
        DateTimeOffset ExpiresAtUtc,
        LinkedListNode<string> RecencyNode);
}
