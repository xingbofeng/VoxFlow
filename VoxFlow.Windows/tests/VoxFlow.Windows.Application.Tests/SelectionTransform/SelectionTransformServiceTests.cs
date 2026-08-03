using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.SelectionTransform;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests.SelectionTransform;

public sealed class SelectionTransformServiceTests
{
    [Fact]
    public async Task Missing_default_provider_fails_before_any_network_call()
    {
        var client = new FakeClient();
        var service = new SelectionTransformService(new FakeResolver(null), client);

        var events = await ReadAll(service.TransformAsync(Request(), CancellationToken.None));

        Assert.Collection(events,
            item => Assert.IsType<SelectionTransformStarted>(item),
            item => Assert.IsType<SelectionTransformFailed>(item));
        Assert.Equal(0, client.StreamCalls);
    }

    [Fact]
    public async Task Default_provider_streams_cumulative_snapshots_with_fixed_temperature_and_one_final()
    {
        var configuration = Configuration(temperature: 1.6);
        var client = new FakeClient
        {
            Updates =
            [
                new LlmStreamUpdate("译", "译", false, null),
                new LlmStreamUpdate("文", "译文", true, null),
            ],
        };
        var service = new SelectionTransformService(new FakeResolver(configuration), client);

        var events = await ReadAll(service.TransformAsync(Request(), CancellationToken.None));

        Assert.Equal(1, client.StreamCalls);
        Assert.Equal(0.2, client.Configuration!.Temperature);
        Assert.Equal("textTransform", client.Request!.Messages[0].Content.Contains("translation assistant") ? "textTransform" : null);
        Assert.Collection(events,
            item => Assert.IsType<SelectionTransformStarted>(item),
            item => Assert.Equal("译", Assert.IsType<SelectionTransformPartial>(item).Text),
            item => Assert.Equal("译文", Assert.IsType<SelectionTransformPartial>(item).Text),
            item => Assert.Equal("译文", Assert.IsType<SelectionTransformCompleted>(item).Text));
    }

    private static SelectionTransformRequest Request() => new(
        Guid.Parse("33333333-3333-3333-3333-333333333333"),
        "source text",
        SelectionTransformOperation.Translation);

    private static LlmProviderClientConfiguration Configuration(double temperature) => new(
        "provider", new Uri("https://example.com/v1"), "model", "secret", temperature, TimeSpan.FromSeconds(30));

    private static async Task<IReadOnlyList<SelectionTransformEvent>> ReadAll(
        IAsyncEnumerable<SelectionTransformEvent> source)
    {
        List<SelectionTransformEvent> result = [];
        await foreach (var item in source)
        {
            result.Add(item);
        }
        return result;
    }

    private sealed class FakeResolver(LlmProviderClientConfiguration? configuration)
        : IDefaultLlmProviderResolver
    {
        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(configuration);
    }

    private sealed class FakeClient : ILlmStreamingClient
    {
        public int StreamCalls { get; private set; }
        public LlmProviderClientConfiguration? Configuration { get; private set; }
        public LlmCompletionRequest? Request { get; private set; }
        public IReadOnlyList<LlmStreamUpdate> Updates { get; init; } = [];

        public async IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            StreamCalls++;
            Configuration = configuration;
            Request = request;
            foreach (var update in Updates)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return update;
                await Task.Yield();
            }
        }
    }
}
