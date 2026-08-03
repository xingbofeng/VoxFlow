using System.Threading;

namespace VoxFlow.Windows.App.State;

/// <summary>
/// Keeps one VoxFlow process per Windows session and lets later launches ask
/// the primary process to restore its main window. Debug and Release builds
/// intentionally use different identities so a developer build cannot wake or
/// replace an installed production build.
/// </summary>
internal sealed class WindowsSingleInstanceCoordinator : IDisposable
{
#if DEBUG
    internal const string DefaultIdentity = "com.voxflow.app.debug";
#else
    internal const string DefaultIdentity = "com.voxflow.app";
#endif

    private const int SignalRetryCount = 20;
    private const int SignalRetryDelayMilliseconds = 25;

    private readonly Semaphore? ownershipLease;
    private readonly EventWaitHandle? activationEvent;
    private readonly RegisteredWaitHandle? activationRegistration;
    private bool disposed;

    private WindowsSingleInstanceCoordinator(
        bool isPrimary,
        bool activationSignaled,
        Semaphore? ownershipLease,
        EventWaitHandle? activationEvent,
        RegisteredWaitHandle? activationRegistration)
    {
        IsPrimary = isPrimary;
        ActivationSignaled = activationSignaled;
        this.ownershipLease = ownershipLease;
        this.activationEvent = activationEvent;
        this.activationRegistration = activationRegistration;
    }

    public bool IsPrimary { get; }

    public bool ActivationSignaled { get; }

    public static WindowsSingleInstanceCoordinator Start(
        string identity,
        Action activationRequested)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(identity);
        ArgumentNullException.ThrowIfNull(activationRequested);

        var leaseName = $"Local\\{identity}.lease";
        var eventName = $"Local\\{identity}.activate";
        var lease = new Semaphore(
            initialCount: 0,
            maximumCount: 1,
            leaseName,
            out var createdNew);
        if (!createdNew)
        {
            lease.Dispose();
            return new WindowsSingleInstanceCoordinator(
                isPrimary: false,
                activationSignaled: TrySignalExisting(eventName),
                ownershipLease: null,
                activationEvent: null,
                activationRegistration: null);
        }

        EventWaitHandle? activation = null;
        RegisteredWaitHandle? registration = null;
        try
        {
            activation = new EventWaitHandle(
                initialState: false,
                EventResetMode.AutoReset,
                eventName,
                out _);
            registration = ThreadPool.RegisterWaitForSingleObject(
                activation,
                static (state, timedOut) =>
                {
                    if (!timedOut && state is Action callback)
                    {
                        callback();
                    }
                },
                activationRequested,
                Timeout.Infinite,
                executeOnlyOnce: false);
            return new WindowsSingleInstanceCoordinator(
                isPrimary: true,
                activationSignaled: false,
                lease,
                activation,
                registration);
        }
        catch
        {
            registration?.Unregister(null);
            activation?.Dispose();
            lease.Dispose();
            throw;
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;

        activationRegistration?.Unregister(null);
        activationEvent?.Dispose();
        ownershipLease?.Dispose();
    }

    private static bool TrySignalExisting(string eventName)
    {
        for (var attempt = 0; attempt < SignalRetryCount; attempt++)
        {
            try
            {
                using var existing = EventWaitHandle.OpenExisting(eventName);
                return existing.Set();
            }
            catch (WaitHandleCannotBeOpenedException) when (
                attempt < SignalRetryCount - 1)
            {
                Thread.Sleep(SignalRetryDelayMilliseconds);
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                return false;
            }
        }
        return false;
    }
}
