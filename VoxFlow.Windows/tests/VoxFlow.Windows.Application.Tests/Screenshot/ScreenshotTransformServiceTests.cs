using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests.Screenshot;

public sealed class ScreenshotTransformServiceTests
{
    [Fact]
    public async Task Missing_provider_fails_before_network_and_preserves_request_privacy_in_diagnostics()
    {
        var client = new FakeClient();
        var request = Request(ScreenshotTransformOperation.Refinement);
        var service = new ScreenshotTransformService(
            new FakeResolver(null),
            client,
            new ScreenshotTransformCache());

        var events = await ReadAll(service.TransformAsync(request, CancellationToken.None));

        Assert.Collection(
            events,
            item => Assert.IsType<ScreenshotTransformStarted>(item),
            item => Assert.IsType<ScreenshotTransformFailed>(item));
        Assert.Equal(0, client.Calls);
        Assert.DoesNotContain(request.SourceText, request.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Explicit_transform_streams_partial_and_final_with_fixed_provider_snapshot()
    {
        var client = new FakeClient
        {
            Updates =
            [
                new LlmStreamUpdate("译", "译", false, null),
                new LlmStreamUpdate("文", "译文", true, null),
            ],
        };
        var configuration = Configuration(temperature: 1.8);
        var request = Request(ScreenshotTransformOperation.Translation);
        var service = new ScreenshotTransformService(
            new FakeResolver(configuration),
            client,
            new ScreenshotTransformCache());

        var events = await ReadAll(service.TransformAsync(request, CancellationToken.None));

        Assert.Equal(1, client.Calls);
        Assert.Equal(0.2, client.Configuration!.Temperature);
        Assert.Equal(request.SourceText, client.Request!.Messages[1].Content);
        Assert.DoesNotContain(".png", client.Request.Messages[1].Content, StringComparison.OrdinalIgnoreCase);
        Assert.Collection(
            events,
            item => Assert.IsType<ScreenshotTransformStarted>(item),
            item => Assert.Equal("译", Assert.IsType<ScreenshotTransformPartial>(item).Text),
            item => Assert.Equal("译文", Assert.IsType<ScreenshotTransformPartial>(item).Text),
            item =>
            {
                var completed = Assert.IsType<ScreenshotTransformCompleted>(item);
                Assert.Equal("译文", completed.Text);
                Assert.False(completed.FromCache);
            });
    }

    [Fact]
    public async Task Completed_request_is_cached_but_image_revision_or_ocr_change_invalidates_it()
    {
        var cache = new ScreenshotTransformCache();
        var client = new FakeClient
        {
            Updates = [new LlmStreamUpdate("first", "first", true, null)],
        };
        var service = new ScreenshotTransformService(
            new FakeResolver(Configuration(0.2)),
            client,
            cache);
        var first = Request(ScreenshotTransformOperation.Summary, inputRevision: "image-a");

        _ = await ReadAll(service.TransformAsync(first, CancellationToken.None));
        client.Updates = [new LlmStreamUpdate("second", "second", true, null)];
        var cached = await ReadAll(service.TransformAsync(first, CancellationToken.None));
        var changedImage = await ReadAll(service.TransformAsync(
            Request(ScreenshotTransformOperation.Summary, inputRevision: "image-b"),
            CancellationToken.None));
        var changedOcr = await ReadAll(service.TransformAsync(
            Request(
                ScreenshotTransformOperation.Summary,
                inputRevision: "image-b",
                sourceText: "changed OCR"),
            CancellationToken.None));

        Assert.Equal(3, client.Calls);
        Assert.True(Assert.IsType<ScreenshotTransformCompleted>(cached.Last()).FromCache);
        Assert.Equal("second", Assert.IsType<ScreenshotTransformCompleted>(changedImage.Last()).Text);
        Assert.Equal("second", Assert.IsType<ScreenshotTransformCompleted>(changedOcr.Last()).Text);
    }

    [Fact]
    public async Task Cancelled_request_does_not_return_a_cached_success()
    {
        var cache = new ScreenshotTransformCache();
        var request = Request(ScreenshotTransformOperation.Refinement);
        cache.Store(request, "cached result");
        var client = new FakeClient();
        var service = new ScreenshotTransformService(
            new FakeResolver(Configuration(0.2)),
            client,
            cache);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        var events = await ReadAll(service.TransformAsync(request, cancellation.Token));

        Assert.Collection(
            events,
            item => Assert.IsType<ScreenshotTransformStarted>(item),
            item => Assert.IsType<ScreenshotTransformCancelled>(item));
        Assert.Equal(0, client.Calls);
    }

    [Fact]
    public async Task Summary_final_is_deterministically_limited_to_three_nonempty_points()
    {
        var client = new FakeClient
        {
            Updates =
            [
                new LlmStreamUpdate(
                    "- one\n- two\n- three\n- invented fourth",
                    "- one\n- two\n- three\n- invented fourth",
                    true,
                    null),
            ],
        };
        var service = new ScreenshotTransformService(
            new FakeResolver(Configuration(0.2)),
            client,
            new ScreenshotTransformCache());

        var events = await ReadAll(service.TransformAsync(
            Request(ScreenshotTransformOperation.Summary),
            CancellationToken.None));

        Assert.Equal(
            "- one\n- two\n- three",
            Assert.IsType<ScreenshotTransformCompleted>(events.Last()).Text);
    }

    [Fact]
    public async Task Stream_error_preserves_partial_in_failure_event_and_does_not_cache_it()
    {
        var client = new FakeClient
        {
            Updates = [new LlmStreamUpdate("partial", "partial", false, null)],
            ThrowAfterUpdates = true,
        };
        var service = new ScreenshotTransformService(
            new FakeResolver(Configuration(0.2)),
            client,
            new ScreenshotTransformCache());
        var request = Request(ScreenshotTransformOperation.Translation);

        var failed = await ReadAll(service.TransformAsync(request, CancellationToken.None));
        client.ThrowAfterUpdates = false;
        client.Updates = [new LlmStreamUpdate("final", "final", true, null)];
        var retried = await ReadAll(service.TransformAsync(request, CancellationToken.None));

        Assert.Equal("partial", Assert.IsType<ScreenshotTransformFailed>(failed.Last()).PartialText);
        Assert.Equal(2, client.Calls);
        Assert.False(Assert.IsType<ScreenshotTransformCompleted>(retried.Last()).FromCache);
    }

    [Fact]
    public async Task Provider_final_arriving_after_cancellation_is_not_cached_or_completed()
    {
        using var cancellation = new CancellationTokenSource();
        var cache = new ScreenshotTransformCache();
        var client = new FakeClient
        {
            Updates = [new LlmStreamUpdate("late", "late final", true, null)],
            BeforeYield = cancellation.Cancel,
        };
        var request = Request(ScreenshotTransformOperation.Translation);
        var service = new ScreenshotTransformService(
            new FakeResolver(Configuration(0.2)),
            client,
            cache);

        var events = await ReadAll(service.TransformAsync(request, cancellation.Token));

        Assert.IsType<ScreenshotTransformCancelled>(events.Last());
        Assert.DoesNotContain(events, item => item is ScreenshotTransformCompleted);
        Assert.False(cache.TryGet(request, out _));
    }

    [Fact]
    public void Cache_evicts_the_least_recently_used_entry_at_capacity()
    {
        var cache = new ScreenshotTransformCache(capacity: 2);
        var first = Request(
            ScreenshotTransformOperation.Summary,
            sourceText: "first",
            screenshotId: "screenshot-1");
        var second = Request(
            ScreenshotTransformOperation.Summary,
            sourceText: "second",
            screenshotId: "screenshot-2");
        var third = Request(
            ScreenshotTransformOperation.Summary,
            sourceText: "third",
            screenshotId: "screenshot-3");
        cache.Store(first, "first result");
        cache.Store(second, "second result");
        Assert.True(cache.TryGet(first, out _));

        cache.Store(third, "third result");

        Assert.True(cache.TryGet(first, out var firstResult));
        Assert.False(cache.TryGet(second, out _));
        Assert.True(cache.TryGet(third, out var thirdResult));
        Assert.Equal("first result", firstResult);
        Assert.Equal("third result", thirdResult);
    }

    [Fact]
    public void Cache_expires_entries_at_the_configured_ttl()
    {
        var clock = new ControlledTimeProvider(
            new DateTimeOffset(2026, 7, 14, 8, 30, 0, TimeSpan.Zero));
        var cache = new ScreenshotTransformCache(
            capacity: 2,
            timeToLive: TimeSpan.FromMinutes(5),
            timeProvider: clock);
        var request = Request(ScreenshotTransformOperation.Translation);
        cache.Store(request, "translated result");

        clock.Advance(TimeSpan.FromMinutes(5) - TimeSpan.FromTicks(1));
        Assert.True(cache.TryGet(request, out var beforeExpiry));
        Assert.Equal("translated result", beforeExpiry);

        clock.Advance(TimeSpan.FromTicks(1));
        Assert.False(cache.TryGet(request, out _));
    }

    private static ScreenshotTransformRequest Request(
        ScreenshotTransformOperation operation,
        string inputRevision = "image-revision",
        string sourceText = "private OCR text",
        string screenshotId = "screenshot-1") => new(
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            screenshotId,
            sourceText,
            operation,
            inputRevision);

    private static LlmProviderClientConfiguration Configuration(double temperature) => new(
        "provider",
        new Uri("https://example.test/v1"),
        "model",
        "secret",
        temperature,
        TimeSpan.FromSeconds(30));

    private static async Task<IReadOnlyList<ScreenshotTransformEvent>> ReadAll(
        IAsyncEnumerable<ScreenshotTransformEvent> source)
    {
        List<ScreenshotTransformEvent> result = [];
        await foreach (var item in source) result.Add(item);
        return result;
    }

    private sealed class FakeResolver(LlmProviderClientConfiguration? configuration)
        : IDefaultLlmProviderResolver
    {
        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(configuration);
        }
    }

    private sealed class FakeClient : ILlmStreamingClient
    {
        public int Calls { get; private set; }
        public LlmProviderClientConfiguration? Configuration { get; private set; }
        public LlmCompletionRequest? Request { get; private set; }
        public IReadOnlyList<LlmStreamUpdate> Updates { get; set; } = [];
        public bool ThrowAfterUpdates { get; set; }
        public Action? BeforeYield { get; set; }

        public async IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            Calls++;
            Configuration = configuration;
            Request = request;
            foreach (var update in Updates)
            {
                cancellationToken.ThrowIfCancellationRequested();
                BeforeYield?.Invoke();
                yield return update;
                await Task.Yield();
            }
            if (ThrowAfterUpdates)
            {
                throw new InvalidOperationException("provider failed");
            }
        }
    }
}
