using VoxFlow.Windows.Testing;
using System.Windows.Threading;

namespace VoxFlow.Windows.IntegrationTests;

public sealed class SharedTestUtilitiesTests
{
    [Fact]
    public void Temporary_directories_are_isolated_and_removed_on_dispose()
    {
        string firstPath;

        using (var first = new TemporaryDirectory())
        using (var second = new TemporaryDirectory())
        {
            firstPath = first.Path;
            Assert.NotEqual(first.Path, second.Path);
            Assert.True(Directory.Exists(first.Path));
            Assert.True(Directory.Exists(second.Path));
            File.WriteAllText(System.IO.Path.Combine(first.Path, "fixture.txt"), "fixture");
        }

        Assert.False(Directory.Exists(firstPath));
    }

    [Fact]
    public void Controlled_time_provider_advances_only_when_requested()
    {
        var initial = new DateTimeOffset(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);
        var clock = new ControlledTimeProvider(initial);

        Assert.Equal(initial, clock.GetUtcNow());

        clock.Advance(TimeSpan.FromSeconds(5));

        Assert.Equal(initial.AddSeconds(5), clock.GetUtcNow());
        Assert.Throws<ArgumentOutOfRangeException>(() => clock.Advance(TimeSpan.FromSeconds(-1)));
    }

    [Fact]
    public async Task Controlled_time_provider_drives_TimeProvider_delays_without_wall_clock_waits()
    {
        var clock = new ControlledTimeProvider(
            new DateTimeOffset(2026, 7, 10, 12, 0, 0, TimeSpan.Zero));
        var delay = Task.Delay(TimeSpan.FromSeconds(5), clock, CancellationToken.None);

        clock.Advance(TimeSpan.FromSeconds(4));
        Assert.False(delay.IsCompleted);

        clock.Advance(TimeSpan.FromSeconds(1));
        await delay;

        Assert.True(delay.IsCompletedSuccessfully);
    }

    [Fact]
    public async Task Cancellable_test_task_finishes_after_cancellation()
    {
        using var cancellation = new CancellationTokenSource();
        var waiting = CancellableTestTask.WaitUntilCancelledAsync(cancellation.Token);

        Assert.False(waiting.IsCompleted);

        await cancellation.CancelAsync();
        await waiting.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.True(waiting.IsCompletedSuccessfully);
    }

    [Fact]
    public void Test_double_names_use_Fake_or_Capturing_prefixes()
    {
        Assert.True(TestDoubleNamingPolicy.IsAllowed(typeof(FakeMicrophone)));
        Assert.True(TestDoubleNamingPolicy.IsAllowed(typeof(CapturingTextSink)));
        Assert.False(TestDoubleNamingPolicy.IsAllowed(typeof(MockProvider)));
    }

    [Fact]
    public async Task Sta_Wpf_host_runs_the_callback_with_a_dispatcher()
    {
        StaWpfTestContext? observed = null;

        await StaWpfTestHost.RunAsync(context =>
        {
            observed = context;
            return Task.CompletedTask;
        });

        Assert.NotNull(observed);
        Assert.Equal(ApartmentState.STA, observed.ApartmentState);
        Assert.True(observed.HasDispatcher);
    }

    [Fact]
    public async Task Sta_Wpf_host_pumps_dispatcher_work_across_async_yields()
    {
        var callbackThread = 0;
        var resumedThread = 0;
        var queuedWorkRan = false;

        await StaWpfTestHost.RunAsync(async context =>
        {
            Assert.Equal(ApartmentState.STA, context.ApartmentState);
            callbackThread = Environment.CurrentManagedThreadId;

            await Dispatcher.CurrentDispatcher.InvokeAsync(
                () => queuedWorkRan = true,
                DispatcherPriority.Background);
            await Dispatcher.Yield(DispatcherPriority.Background);

            resumedThread = Environment.CurrentManagedThreadId;
        });

        Assert.True(queuedWorkRan);
        Assert.Equal(callbackThread, resumedThread);
    }

    private sealed class FakeMicrophone;

    private sealed class CapturingTextSink;

    private sealed class MockProvider;
}
