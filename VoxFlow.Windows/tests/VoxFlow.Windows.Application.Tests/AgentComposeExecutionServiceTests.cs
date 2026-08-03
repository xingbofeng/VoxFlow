using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using System.Net.Http;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentComposeExecutionServiceTests
{
    [Fact]
    public async Task Missing_default_provider_does_not_start_the_sidecar()
    {
        var factory = new CapturingSessionFactory();
        var service = new AgentComposeExecutionService(
            new FakeResolver(null),
            new AgentComposePromptBuilder(),
            new BuiltinAgentSidecarRunner(factory));

        var result = await service.ExecuteAsync(
            "task-1", "draft a reply", Context(), Workspace(), _ => Task.CompletedTask,
            (_, _) => Task.FromResult(AgentToolResult.Success("read_file")), CancellationToken.None);

        Assert.Equal(AgentComposeExecutionStatus.ProviderUnavailable, result.Status);
        Assert.False(factory.Started);
    }

    [Fact]
    public async Task Resolved_provider_stays_in_memory_and_runs_the_sidecar_request()
    {
        var factory = new CapturingSessionFactory("""{"schemaVersion":1,"event":"turnCompleted","summary":"draft"}""");
        var service = new AgentComposeExecutionService(
            new FakeResolver(Provider()),
            new AgentComposePromptBuilder(),
            new BuiltinAgentSidecarRunner(factory));

        var result = await service.ExecuteAsync(
            "task-1", "draft a reply", Context(), Workspace(), _ => Task.CompletedTask,
            (_, _) => Task.FromResult(AgentToolResult.Success("read_file")), CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.NotNull(factory.Request);
        Assert.Equal("provider-1", factory.Request!.Provider.ProviderId);
        Assert.DoesNotContain("secret-value", factory.Request.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Builtin_file_tool_entrypoint_executes_the_sidecar_schema_against_its_workspace()
    {
        var workspace = Workspace();
        Directory.CreateDirectory(workspace);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(workspace, "note.txt"), "draft");
            var factory = new CapturingSessionFactory(
                """
                {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"read-1","name":"read_file","arguments":{"file_path":"note.txt"}}}
                {"schemaVersion":1,"event":"turnCompleted","summary":"done"}
                """);
            var service = new AgentComposeExecutionService(
                new FakeResolver(Provider()),
                new AgentComposePromptBuilder(),
                new BuiltinAgentSidecarRunner(factory));

            var result = await service.ExecuteWithBuiltinFileToolsAsync(
                "task-1", "read the note", Context(), workspace, _ => Task.CompletedTask,
                CancellationToken.None);

            Assert.True(result.Succeeded);
            Assert.Contains("draft", factory.Session!.WrittenInput, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(workspace, recursive: true);
        }
    }

    [Fact]
    public async Task Builtin_tools_entrypoint_routes_explicit_https_requests_to_the_controlled_host()
    {
        var factory = new CapturingSessionFactory(
            """
            {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"http-1","name":"http_request","arguments":{"url":"https://api.example.test/status","method":"GET"}}}
            {"schemaVersion":1,"event":"turnCompleted","summary":"done"}
            """);
        var httpClient = new FakeHttpClient();
        var service = new AgentComposeExecutionService(
            new FakeResolver(Provider()),
            new AgentComposePromptBuilder(),
            new BuiltinAgentSidecarRunner(factory),
            httpClient: httpClient);

        var result = await service.ExecuteWithBuiltinToolsAsync(
            "task-1", "请求 https://api.example.test/status", Context(), Workspace(),
            history: null, _ => Task.CompletedTask, CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.Equal(new Uri("https://api.example.test/status"), httpClient.Uri);
        Assert.Contains("statusCode", factory.Session!.WrittenInput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Builtin_tools_entrypoint_routes_explicit_web_fetch_to_the_controlled_host()
    {
        var factory = new CapturingSessionFactory(
            """
            {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"fetch-1","name":"web_fetch","arguments":{"url":"https://example.test/docs","prompt":"summarize"}}}
            {"schemaVersion":1,"event":"turnCompleted","summary":"done"}
            """);
        var webClient = new FakeWebFetchClient();
        var service = new AgentComposeExecutionService(new FakeResolver(Provider()), new AgentComposePromptBuilder(),
            new BuiltinAgentSidecarRunner(factory), webFetchClient: webClient);

        var result = await service.ExecuteWithBuiltinToolsAsync("task-1", "读取 https://example.test/docs", Context(), Workspace(),
            history: null, _ => Task.CompletedTask, CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.Equal(new Uri("https://example.test/docs"), webClient.Uri);
        Assert.Contains("result", factory.Session!.WrittenInput, StringComparison.Ordinal);
    }

    private static LlmProviderClientConfiguration Provider() => new(
        "provider-1", new Uri("https://example.test/v1"), "model", "secret-value", 0.2, TimeSpan.FromSeconds(30));

    private static AgentContextSnapshot Context() => new(
        new ForegroundTargetSnapshot(1, 2, "notepad.exe", "Draft", new WindowBounds(0, 0, 100, 100), ProcessIntegrityLevel.Medium, [1], 1),
        "selected", Array.Empty<string>());

    private static string Workspace() => Path.Combine(Path.GetTempPath(), "voxflow-agent-execution");

    private sealed class FakeResolver(LlmProviderClientConfiguration? provider) : IDefaultLlmProviderResolver
    {
        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(CancellationToken cancellationToken) => ValueTask.FromResult(provider);
    }

    private sealed class FakeHttpClient : IAgentHttpRequestClient
    {
        public Uri? Uri { get; private set; }

        public Task<AgentHttpResponse> SendAsync(HttpMethod method, Uri uri,
            IReadOnlyDictionary<string, string> headers, string? body, CancellationToken cancellationToken)
        {
            Uri = uri;
            return Task.FromResult(new AgentHttpResponse(200, "ok"));
        }
    }

    private sealed class FakeWebFetchClient : IAgentWebFetchClient
    {
        public Uri? Uri { get; private set; }
        public Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken)
        {
            Uri = uri;
            return Task.FromResult(new AgentWebFetchResponse(200, "text/plain", "ok"));
        }
    }

    private sealed class CapturingSessionFactory : IBuiltinAgentProcessSessionFactory
    {
        private readonly string stdout;

        public CapturingSessionFactory(string? stdout = null) => this.stdout = stdout ?? string.Empty;
        public bool Started { get; private set; }
        public BuiltinAgentSidecarRunRequest? Request { get; private set; }
        public Session? Session { get; private set; }

        public Task<IBuiltinAgentProcessSession> StartAsync(BuiltinAgentSidecarRunRequest request, CancellationToken cancellationToken)
        {
            Started = true;
            Request = request;
            Session = new Session(stdout);
            return Task.FromResult<IBuiltinAgentProcessSession>(Session);
        }
    }

    private sealed class Session : IBuiltinAgentProcessSession
    {
        private readonly StringReader output;
        private readonly StringReader error = new(string.Empty);
        private readonly StringWriter input = new();
        public Session(string stdout) => output = new StringReader(stdout);
        public TextReader StandardOutput => output;
        public TextReader StandardError => error;
        public TextWriter StandardInput => input;
        public string WrittenInput => input.ToString();
        public Task<int> WaitForExitAsync(CancellationToken cancellationToken, TimeSpan? timeout = null) => Task.FromResult(0);
        public Task<BuiltinAgentStderrSummary> DrainStandardErrorAsync(CancellationToken cancellationToken) => Task.FromResult(new BuiltinAgentStderrSummary(false, false));
        public Task CancelAsync() => Task.CompletedTask;
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
