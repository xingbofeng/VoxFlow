namespace VoxFlow.Windows.Testing;

public sealed class ControlledTimeProvider : TimeProvider
{
    private readonly object _lock = new();
    private readonly HashSet<ControlledTimer> _timers = [];
    private DateTimeOffset _utcNow;
    private long _timestamp;

    public ControlledTimeProvider(DateTimeOffset initialUtcNow)
    {
        _utcNow = initialUtcNow.ToUniversalTime();
    }

    public override long TimestampFrequency => TimeSpan.TicksPerSecond;

    public override DateTimeOffset GetUtcNow()
    {
        lock (_lock)
        {
            return _utcNow;
        }
    }

    public override long GetTimestamp()
    {
        lock (_lock)
        {
            return _timestamp;
        }
    }

    public override ITimer CreateTimer(
        TimerCallback callback,
        object? state,
        TimeSpan dueTime,
        TimeSpan period)
    {
        ArgumentNullException.ThrowIfNull(callback);
        ValidateTimerInterval(dueTime, nameof(dueTime));
        ValidateTimerInterval(period, nameof(period));

        lock (_lock)
        {
            var timer = new ControlledTimer(this, callback, state, period);
            timer.Schedule(_timestamp, dueTime);
            _timers.Add(timer);
            return timer;
        }
    }

    public void Advance(TimeSpan amount)
    {
        if (amount < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(amount), "Time cannot move backwards.");
        }

        lock (_lock)
        {
            _utcNow = _utcNow.Add(amount);
            _timestamp = checked(_timestamp + amount.Ticks);
        }

        while (TryTakeDueTimer(out var timer))
        {
            timer.Invoke();
        }
    }

    private bool TryTakeDueTimer(out ControlledTimer timer)
    {
        lock (_lock)
        {
            timer = _timers
                .Where(candidate => candidate.IsDue(_timestamp))
                .OrderBy(candidate => candidate.NextDueTimestamp)
                .FirstOrDefault()!;

            if (timer is null)
            {
                return false;
            }

            timer.RescheduleAfterCallback(_timestamp);
            return true;
        }
    }

    private bool ChangeTimer(
        ControlledTimer timer,
        TimeSpan dueTime,
        TimeSpan period)
    {
        ValidateTimerInterval(dueTime, nameof(dueTime));
        ValidateTimerInterval(period, nameof(period));

        lock (_lock)
        {
            if (timer.IsDisposed)
            {
                return false;
            }

            timer.Period = period;
            timer.Schedule(_timestamp, dueTime);
            return true;
        }
    }

    private void DisposeTimer(ControlledTimer timer)
    {
        lock (_lock)
        {
            timer.IsDisposed = true;
            _timers.Remove(timer);
        }
    }

    private static void ValidateTimerInterval(TimeSpan value, string parameterName)
    {
        if (value < TimeSpan.Zero && value != Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static long AddSaturated(long timestamp, TimeSpan interval)
    {
        if (interval == Timeout.InfiniteTimeSpan)
        {
            return long.MaxValue;
        }

        try
        {
            return checked(timestamp + interval.Ticks);
        }
        catch (OverflowException)
        {
            return long.MaxValue;
        }
    }

    private sealed class ControlledTimer(
        ControlledTimeProvider owner,
        TimerCallback callback,
        object? state,
        TimeSpan period) : ITimer
    {
        public bool IsDisposed { get; set; }

        public long NextDueTimestamp { get; private set; } = long.MaxValue;

        public TimeSpan Period { get; set; } = period;

        public bool IsDue(long timestamp) =>
            !IsDisposed && NextDueTimestamp <= timestamp;

        public void Schedule(long timestamp, TimeSpan dueTime)
        {
            NextDueTimestamp = AddSaturated(timestamp, dueTime);
        }

        public void RescheduleAfterCallback(long timestamp)
        {
            NextDueTimestamp = Period > TimeSpan.Zero
                ? AddSaturated(timestamp, Period)
                : long.MaxValue;
        }

        public void Invoke() => callback(state);

        public bool Change(TimeSpan dueTime, TimeSpan periodValue) =>
            owner.ChangeTimer(this, dueTime, periodValue);

        public void Dispose() => owner.DisposeTimer(this);

        public ValueTask DisposeAsync()
        {
            Dispose();
            return ValueTask.CompletedTask;
        }
    }
}
