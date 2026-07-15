using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class GenericLlmContractsTests
{
    [Fact]
    public async Task Composite_provider_exposes_five_independent_capabilities()
    {
        var provider = new FakeLlmProviderClient();
        var configuration = CreateConfiguration();
        var request = new LlmCompletionRequest(
            [
                new LlmChatMessage(LlmMessageRole.System, "Return concise text."),
                new LlmChatMessage(LlmMessageRole.User, "Hello"),
            ]);

        var completion = await ((ILlmCompletionClient)provider)
            .CompleteAsync(configuration, request, CancellationToken.None);
        var updates = new List<LlmStreamUpdate>();
        await foreach (var update in ((ILlmStreamingClient)provider)
            .StreamAsync(configuration, request, CancellationToken.None))
        {
            updates.Add(update);
        }
        var models = await ((ILlmModelDiscoveryClient)provider)
            .DiscoverModelsAsync(configuration, CancellationToken.None);
        var connection = await ((ILlmConnectionTester)provider)
            .TestConnectionAsync(configuration, CancellationToken.None);
        var agent = await ((ILlmAgentCapabilityTester)provider)
            .TestAgentCapabilityAsync(configuration, CancellationToken.None);

        Assert.Equal("complete", completion.Text);
        Assert.Equal("stream", updates.Single().AccumulatedText);
        Assert.Equal("model-a", models.Models.Single().Id);
        Assert.True(connection.Succeeded);
        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, agent.Status);
        Assert.Equal(1, provider.CompletionCalls);
        Assert.Equal(1, provider.StreamCalls);
        Assert.Equal(1, provider.ModelDiscoveryCalls);
        Assert.Equal(1, provider.ConnectionTestCalls);
        Assert.Equal(1, provider.AgentCapabilityTestCalls);
    }

    [Fact]
    public void Provider_configuration_allows_https_and_loopback_http_and_redacts_secret()
    {
        var remote = CreateConfiguration();
        var loopback = new LlmProviderClientConfiguration(
            providerId: "ollama-local",
            baseUri: new Uri("http://localhost:11434/v1"),
            model: "qwen-local",
            apiKey: null,
            temperature: 0.2,
            timeout: TimeSpan.FromSeconds(60));

        Assert.Equal("https", remote.BaseUri.Scheme);
        Assert.Equal("http", loopback.BaseUri.Scheme);
        Assert.DoesNotContain("test-api-key", remote.ToString(), StringComparison.Ordinal);
        Assert.Throws<ArgumentException>(() => new LlmProviderClientConfiguration(
            providerId: "insecure-remote",
            baseUri: new Uri("http://example.com/v1"),
            model: "model-a",
            apiKey: null,
            temperature: 0.2,
            timeout: TimeSpan.FromSeconds(60)));
    }

    [Fact]
    public void Completion_request_and_model_discovery_defensively_copy_inputs()
    {
        var messages = new[]
        {
            new LlmChatMessage(LlmMessageRole.User, "original"),
        };
        var request = new LlmCompletionRequest(messages, maxOutputTokens: 200);
        var models = new[] { new LlmModelDescriptor("model-a", "Model A", "owner") };
        var discovery = new LlmModelDiscoveryResult(
            models,
            LlmModelDiscoverySource.Remote);

        messages[0] = new LlmChatMessage(LlmMessageRole.User, "mutated");
        models[0] = new LlmModelDescriptor("model-b", "Model B", "owner");

        Assert.Equal("original", request.Messages.Single().Content);
        Assert.Equal("model-a", discovery.Models.Single().Id);
        Assert.Equal(200, request.MaxOutputTokens);
    }

    [Fact]
    public void Connection_health_and_agent_capability_are_not_the_same_status()
    {
        var connection = new LlmConnectionTestResult(
            LlmConnectionTestStatus.Succeeded,
            latencyMs: 42,
            safeMessage: null);
        var agent = new LlmAgentCapabilityTestResult(
            LlmAgentCapabilityStatus.Unsupported,
            safeMessage: "tool_calls_missing");

        Assert.True(connection.Succeeded);
        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, agent.Status);
        Assert.False(agent.IsSupported);
    }

    [Fact]
    public async Task Existing_refiner_and_file_translation_contracts_remain_source_compatible()
    {
        var adapter = new LegacyTextAdapter();
        IStreamingTextRefiner refiner = adapter;
        IFileTranscriptionTranslator translator = adapter;

        Assert.Equal(
            LlmRefinerAvailability.Ready,
            await refiner.GetAvailabilityAsync(CancellationToken.None));
        Assert.Equal(
            "translated",
            await translator.TranslateAsync("source", "zh-CN", CancellationToken.None));
        var snapshots = new List<string>();
        await foreach (var snapshot in refiner.RefineAsync("source", CancellationToken.None))
        {
            snapshots.Add(snapshot);
        }
        Assert.Equal(["refined"], snapshots);
    }

    private static LlmProviderClientConfiguration CreateConfiguration() => new(
        providerId: "provider-openai",
        baseUri: new Uri("https://example.test/v1"),
        model: "model-a",
        apiKey: "test-api-key",
        temperature: 0.2,
        timeout: TimeSpan.FromSeconds(300));

    private sealed class FakeLlmProviderClient : ILlmProviderClient
    {
        public int CompletionCalls { get; private set; }

        public int StreamCalls { get; private set; }

        public int ModelDiscoveryCalls { get; private set; }

        public int ConnectionTestCalls { get; private set; }

        public int AgentCapabilityTestCalls { get; private set; }

        public ValueTask<LlmCompletionResponse> CompleteAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            CancellationToken cancellationToken)
        {
            CompletionCalls++;
            return ValueTask.FromResult(new LlmCompletionResponse(
                "complete",
                configuration.ProviderId,
                configuration.Model,
                tokenUsage: null));
        }

        public async IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
            LlmProviderClientConfiguration configuration,
            LlmCompletionRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            StreamCalls++;
            await Task.Yield();
            cancellationToken.ThrowIfCancellationRequested();
            yield return new LlmStreamUpdate(
                deltaText: "stream",
                accumulatedText: "stream",
                isFinal: true,
                tokenUsage: null);
        }

        public ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            ModelDiscoveryCalls++;
            return ValueTask.FromResult(new LlmModelDiscoveryResult(
                [new LlmModelDescriptor("model-a", "Model A", "owner")],
                LlmModelDiscoverySource.Remote));
        }

        public ValueTask<LlmConnectionTestResult> TestConnectionAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            ConnectionTestCalls++;
            return ValueTask.FromResult(new LlmConnectionTestResult(
                LlmConnectionTestStatus.Succeeded,
                latencyMs: 12,
                safeMessage: null));
        }

        public ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
            LlmProviderClientConfiguration configuration,
            CancellationToken cancellationToken)
        {
            AgentCapabilityTestCalls++;
            return ValueTask.FromResult(new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Unsupported,
                "tool_calls_missing"));
        }
    }

    private sealed class LegacyTextAdapter
        : IStreamingTextRefiner, IFileTranscriptionTranslator
    {
        public ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(LlmRefinerAvailability.Ready);

        public async IAsyncEnumerable<string> RefineAsync(
            string text,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            await Task.Yield();
            cancellationToken.ThrowIfCancellationRequested();
            yield return "refined";
        }

        public ValueTask<string> TranslateAsync(
            string text,
            string targetLanguage,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult("translated");
    }
}
