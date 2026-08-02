using System.Data.Common;
using System.Net.WebSockets;
using System.Security.Cryptography;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Security;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.OpenAI;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;

namespace VoxFlow.Windows.App.Tests.Live;

/// <summary>
/// Explicit, billable smoke against the current Windows user's existing app
/// database. The test never calls credential-reveal APIs or observes decrypted
/// values or stored ciphertext. Production services keep credential access
/// inside their network call boundary, and every test diagnostic is reduced to
/// a controlled provider id, success flag, and stable error category.
/// </summary>
public sealed class WindowsSavedCredentialLiveSmokeTests
{
    private const string TokenHubProviderId = "tencent-tokenhub";
    private const string ExpectedTokenHubModel = "deepseek-v4-flash";
    private const string CanonicalCredentialMask =
        "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022";

    [WindowsSavedCredentialsLiveFact]
    [Trait("Category", "Live")]
    public async Task Saved_provider_credentials_pass_production_health_checks()
    {
        var outcomes = new List<LiveSmokeOutcome>();
        var databasePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow",
            "voxflow.db");
        if (!File.Exists(databasePath))
        {
            outcomes.Add(Failure("local-db", "database_missing"));
            AssertOutcomes(outcomes);
            return;
        }

        LiveProductionGraph graph;
        try
        {
            graph = new LiveProductionGraph(databasePath);
        }
        catch (Exception exception)
        {
            outcomes.Add(Failure(
                "local-db",
                string.Concat("open_", Classify(exception))));
            AssertOutcomes(outcomes);
            return;
        }

        using (graph)
        {
            var tokenHub = ResolveDefaultTokenHub(
                graph.LlmProviderManagement,
                outcomes);
            outcomes.AddRange(await TestPresentationReloadAsync(
                graph.ModelsSettings,
                tokenHub.Provider?.Id));
            if (tokenHub.Provider is null || !tokenHub.HasExpectedModel)
            {
                outcomes.Add(Failure(
                    TokenHubProviderId,
                    "connection_default_provider_unavailable"));
                outcomes.Add(Failure(
                    TokenHubProviderId,
                    "agent_default_provider_unavailable"));
            }
            else
            {
                outcomes.Add(await TestLlmConnectionAsync(
                    graph.LlmProviderManagement,
                    tokenHub.Provider.Id));
                outcomes.Add(await TestLlmAgentCapabilityAsync(
                    graph.LlmProviderManagement,
                    tokenHub.Provider.Id));
                outcomes.Add(await TestBundledAgentAsync(
                    graph.AgentComposeExecution));
            }

            outcomes.Add(await TestCloudAsrAsync(
                graph.CloudAsrSettings,
                AsrProviderId.TencentCloud,
                "tencent-cloud"));
            outcomes.Add(await TestCloudAsrAsync(
                graph.CloudAsrSettings,
                AsrProviderId.AliyunDashScope,
                "aliyun-dashscope"));
            outcomes.Add(await TestCloudAsrAsync(
                graph.CloudAsrSettings,
                AsrProviderId.Volcengine,
                "volcengine"));
        }

        AssertOutcomes(outcomes);
    }

    private static TokenHubResolution ResolveDefaultTokenHub(
        ILlmProviderManagementService management,
        ICollection<LiveSmokeOutcome> outcomes)
    {
        IReadOnlyList<LlmProviderRecord> providers;
        try
        {
            providers = management.List();
        }
        catch (Exception exception)
        {
            outcomes.Add(Failure(
                TokenHubProviderId,
                string.Concat("read_", Classify(exception))));
            return new TokenHubResolution(null, false);
        }

        var matches = providers
            .Where(provider => provider.IsDefault
                && provider.Enabled
                && provider.BaseUri is not null
                && string.Equals(
                    LlmProviderTemplateCatalog.Match(provider.BaseUri)?.Id,
                    TokenHubProviderId,
                    StringComparison.Ordinal))
            .Take(2)
            .ToArray();
        if (matches.Length != 1)
        {
            outcomes.Add(Failure(
                TokenHubProviderId,
                "default_provider_missing_or_ambiguous"));
            return new TokenHubResolution(null, false);
        }

        var modelMatches = string.Equals(
            matches[0].DefaultModel,
            ExpectedTokenHubModel,
            StringComparison.Ordinal);
        outcomes.Add(new LiveSmokeOutcome(
            TokenHubProviderId,
            modelMatches,
            modelMatches ? "none" : "default_model_mismatch"));
        return new TokenHubResolution(matches[0], modelMatches);
    }

    private static async Task<IReadOnlyList<LiveSmokeOutcome>>
        TestPresentationReloadAsync(
            ModelsSettingsPageViewModel page,
            string? persistedTokenHubId)
    {
        var outcomes = new List<LiveSmokeOutcome>();
        using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30)))
        {
            try
            {
                if (page.LlmProviders is null || persistedTokenHubId is null)
                {
                    outcomes.Add(Failure(
                        TokenHubProviderId,
                        "credential_mask_provider_unavailable"));
                }
                else
                {
                    await page.LlmProviders.LoadAsync(timeout.Token);
                    var cards = page.LlmProviders.Providers
                        .Where(card => string.Equals(
                            card.Id,
                            persistedTokenHubId,
                            StringComparison.Ordinal))
                        .Take(2)
                        .ToArray();
                    var masked = cards.Length == 1
                        && HasCanonicalMask(cards[0].ApiKeyPresentation);
                    outcomes.Add(new LiveSmokeOutcome(
                        TokenHubProviderId,
                        masked,
                        masked ? "none" : "credential_mask_reload_failed"));
                }
            }
            catch (Exception exception)
            {
                outcomes.Add(Failure(
                    TokenHubProviderId,
                    string.Concat("credential_mask_", Classify(exception))));
            }
        }

        using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30)))
        {
            try
            {
                await page.LoadCloudAsync(timeout.Token);
                outcomes.Add(MaskOutcome(
                    "tencent-cloud",
                    page.Tencent.IsConfigured
                        && HasCanonicalMask(page.Tencent.FirstCredentialPresentation)
                        && HasCanonicalMask(page.Tencent.SecondCredentialPresentation)
                        && HasCanonicalMask(page.Tencent.ThirdCredentialPresentation)));
                outcomes.Add(MaskOutcome(
                    "aliyun-dashscope",
                    page.Aliyun.IsConfigured
                        && HasCanonicalMask(page.Aliyun.FirstCredentialPresentation)));
                outcomes.Add(MaskOutcome(
                    "volcengine",
                    page.Volcengine.IsConfigured
                        && HasCanonicalMask(page.Volcengine.FirstCredentialPresentation)
                        && HasCanonicalMask(page.Volcengine.SecondCredentialPresentation)
                        && HasCanonicalMask(page.Volcengine.ThirdCredentialPresentation)));
            }
            catch (Exception exception)
            {
                var category = string.Concat(
                    "credential_mask_",
                    Classify(exception));
                outcomes.Add(Failure("tencent-cloud", category));
                outcomes.Add(Failure("aliyun-dashscope", category));
                outcomes.Add(Failure("volcengine", category));
            }
        }

        return outcomes;
    }

    private static LiveSmokeOutcome MaskOutcome(
        string providerId,
        bool succeeded) => new(
            providerId,
            succeeded,
            succeeded ? "none" : "credential_mask_reload_failed");

    private static bool HasCanonicalMask(string presentation) =>
        !string.IsNullOrWhiteSpace(presentation)
        && string.Equals(
            presentation,
            CanonicalCredentialMask,
            StringComparison.Ordinal);

    private static async Task<LiveSmokeOutcome> TestLlmConnectionAsync(
        ILlmProviderManagementService management,
        string persistedProviderId)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        try
        {
            var result = await management.TestConnectionAsync(
                persistedProviderId,
                timeout.Token);
            return new LiveSmokeOutcome(
                TokenHubProviderId,
                result.Succeeded,
                result.Succeeded ? "none" : "connection_failed");
        }
        catch (Exception exception)
        {
            return Failure(
                TokenHubProviderId,
                string.Concat("connection_", Classify(exception)));
        }
    }

    private static async Task<LiveSmokeOutcome> TestLlmAgentCapabilityAsync(
        ILlmProviderManagementService management,
        string persistedProviderId)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        try
        {
            var result = await management.TestAgentCapabilityAsync(
                persistedProviderId,
                timeout.Token);
            var category = result.Status switch
            {
                LlmAgentCapabilityStatus.Supported => "none",
                LlmAgentCapabilityStatus.Unknown => "agent_unknown",
                LlmAgentCapabilityStatus.Unsupported => "agent_unsupported",
                LlmAgentCapabilityStatus.Error => "agent_error",
                _ => "agent_invalid_status",
            };
            return new LiveSmokeOutcome(
                TokenHubProviderId,
                result.IsSupported,
                category);
        }
        catch (Exception exception)
        {
            return Failure(
                TokenHubProviderId,
                string.Concat("agent_", Classify(exception)));
        }
    }

    private static async Task<LiveSmokeOutcome> TestBundledAgentAsync(
        AgentComposeExecutionService? execution)
    {
        const string providerId = "builtin-agent";
        if (execution is null)
        {
            return Failure(providerId, "runtime_unavailable");
        }

        var workspace = Path.Combine(
            Path.GetTempPath(),
            "voxflow-agent-live-smoke-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workspace);
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        try
        {
            var events = new List<string>();
            var context = new AgentContextSnapshot(
                new ForegroundTargetSnapshot(
                    windowHandle: 1,
                    processId: 1,
                    processName: "voxflow-live-smoke.exe",
                    windowTitle: "VoxFlow live smoke",
                    new WindowBounds(0, 0, 800, 600),
                    ProcessIntegrityLevel.Medium,
                    [1],
                    DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()),
                SelectedText: null,
                Warnings: [],
                VisibleText:
                    "VoxFlow verifies that an injected transcript reaches the bundled Agent and returns a final summary.");
            var result = await execution.ExecuteAsync(
                "live-smoke-" + Guid.NewGuid().ToString("N"),
                "Summarize the untrusted text in exactly one short sentence. " +
                "Do not call tools or modify files, clipboard, windows, input fields, URLs, or external resources.",
                context,
                workspace,
                runtimeEvent =>
                {
                    events.Add(runtimeEvent.Event);
                    return Task.CompletedTask;
                },
                (call, _) => Task.FromResult(AgentToolResult.Failure(
                    call.Name,
                    "live_smoke_tools_disabled")),
                timeout.Token);
            var succeeded = result.Succeeded
                && events.Any(value => string.Equals(
                    value,
                    "turnCompleted",
                    StringComparison.Ordinal));
            return new LiveSmokeOutcome(
                providerId,
                succeeded,
                succeeded ? "none" : "agent_execution_failed");
        }
        catch (Exception exception)
        {
            return Failure(
                providerId,
                string.Concat("execution_", Classify(exception)));
        }
        finally
        {
            try
            {
                Directory.Delete(workspace, recursive: true);
            }
            catch
            {
                // Cleanup diagnostics must not expose the temporary path.
            }
        }
    }

    private static async Task<LiveSmokeOutcome> TestCloudAsrAsync(
        CloudAsrSettingsCoordinator coordinator,
        AsrProviderId provider,
        string providerId)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(1));
        try
        {
            var succeeded = await coordinator.TestAsync(provider, timeout.Token);
            return new LiveSmokeOutcome(
                providerId,
                succeeded,
                succeeded ? "none" : "connection_failed");
        }
        catch (Exception exception)
        {
            return Failure(
                providerId,
                string.Concat("connection_", Classify(exception)));
        }
    }

    private static LiveSmokeOutcome Failure(
        string providerId,
        string errorCategory) => new(providerId, false, errorCategory);

    private static string Classify(Exception exception) => exception switch
    {
        CredentialUnavailableException => "credential_unavailable",
        CryptographicException => "credential_unavailable",
        OperationCanceledException => "timeout_or_cancelled",
        TimeoutException => "timeout",
        WebSocketException => "network_failure",
        HttpRequestException => "network_failure",
        UnauthorizedAccessException => "access_denied",
        DbException => "database_failure",
        IOException => "io_failure",
        InvalidOperationException => "invalid_state",
        _ => "unexpected_failure",
    };

    private static void AssertOutcomes(IEnumerable<LiveSmokeOutcome> outcomes)
    {
        var failures = outcomes
            .Where(outcome => !outcome.Succeeded)
            .Select(outcome => outcome.SafeDiagnostic)
            .ToArray();
        Assert.True(failures.Length == 0, string.Join(" | ", failures));
    }

    private sealed record LiveSmokeOutcome(
        string ProviderId,
        bool Succeeded,
        string ErrorCategory)
    {
        public string SafeDiagnostic => string.Concat(
            "provider=",
            ProviderId,
            "; success=",
            Succeeded ? "true" : "false",
            "; error=",
            ErrorCategory);
    }

    private sealed record TokenHubResolution(
        LlmProviderRecord? Provider,
        bool HasExpectedModel);

    private sealed class LiveProductionGraph : IDisposable
    {
        private readonly SqliteTransactionRunner transactionRunner;
        private readonly SqliteCredentialVault credentialVault;
        private readonly HttpClient httpClient;

        public LiveProductionGraph(string databasePath)
        {
            var connectionFactory = new SqliteConnectionFactory(
                databasePath,
                pooling: false);
            transactionRunner = new SqliteTransactionRunner(connectionFactory);
            credentialVault = new SqliteCredentialVault(
                connectionFactory,
                new DpapiCurrentUserDataProtector());
            httpClient = new HttpClient
            {
                Timeout = Timeout.InfiniteTimeSpan,
            };

            var providerRepository = new SqliteLlmProviderRepository(
                transactionRunner);
            var credentialService = new LlmProviderCredentialService(
                credentialVault,
                providerRepository);
            var llmClient = new OpenAiCompatibleClient(
                httpClient,
                typeof(WindowsSavedCredentialLiveSmokeTests)
                    .Assembly.GetName().Version?.ToString());
            LlmProviderManagement = new LlmProviderManagementService(
                providerRepository,
                credentialService,
                llmClient);
            var defaultProvider = new DefaultLlmProviderResolver(
                providerRepository,
                credentialService);
            var agentProvider = new AgentCapableLlmProviderResolver(
                providerRepository,
                defaultProvider);
            var agentRuntime = new BuiltinAgentRuntimeVerifier()
                .Verify(AppContext.BaseDirectory);
            if (agentRuntime is { IsAvailable: true, Binary: { } binary })
            {
                AgentComposeExecution = new AgentComposeExecutionService(
                    agentProvider,
                    new AgentComposePromptBuilder(),
                    new BuiltinAgentSidecarRunner(
                        new BuiltinAgentProcessSessionFactory(
                            new BuiltinAgentProcessHost(
                                new BuiltinAgentProcessSpecification(binary))),
                        new BuiltinAgentJsonlPump()));
            }

            var tencent = new TencentAsrSettingsService(
                credentialVault,
                new TencentSettingsConnectionTester());
            var aliyun = new AliyunAsrSettingsService(
                credentialVault,
                new AliyunSettingsConnectionTester());
            var volcengine = new VolcengineAsrSettingsService(credentialVault);
            var settingsState = new SettingsStateCoordinator(
                new VoxFlowStateStore());
            CloudAsrSettings = new CloudAsrSettingsCoordinator(
                tencent,
                aliyun,
                volcengine,
                settingsState);
            ModelsSettings = new ModelsSettingsPageViewModel(
                new OpenAiSettingsCardViewModel(settingsState),
                CloudAsrSettings,
                LlmProviderManagement);
        }

        public ILlmProviderManagementService LlmProviderManagement { get; }

        public AgentComposeExecutionService? AgentComposeExecution { get; }

        public CloudAsrSettingsCoordinator CloudAsrSettings { get; }

        public ModelsSettingsPageViewModel ModelsSettings { get; }

        public void Dispose()
        {
            try
            {
                httpClient.Dispose();
            }
            catch
            {
                // Cleanup must not expose a path or network diagnostic.
            }
            try
            {
                credentialVault.Dispose();
            }
            catch
            {
                // Cleanup must not expose credential storage details.
            }
            try
            {
                transactionRunner.Dispose();
            }
            catch
            {
                // Cleanup must not expose a database diagnostic.
            }
        }
    }
}

[AttributeUsage(AttributeTargets.Method, AllowMultiple = false)]
public sealed class WindowsSavedCredentialsLiveFactAttribute : FactAttribute
{
    public WindowsSavedCredentialsLiveFactAttribute()
        : this(
            OperatingSystem.IsWindows(),
            Environment.GetEnvironmentVariable(
                "VOICEINPUT_TEST_WINDOWS_LIVE_DB"))
    {
    }

    internal WindowsSavedCredentialsLiveFactAttribute(
        bool isWindows,
        string? optInValue)
    {
        if (!isWindows)
        {
            Skip = "Requires the current Windows user's local VoxFlow database.";
            return;
        }

        if (!string.Equals(
                optInValue,
                "1",
                StringComparison.Ordinal))
        {
            Skip = "Set VOICEINPUT_TEST_WINDOWS_LIVE_DB=1 to run this billable live smoke.";
        }
    }
}

public sealed class WindowsSavedCredentialsLiveFactTests
{
    [Fact]
    public void Missing_opt_in_reports_an_explicit_discovery_skip()
    {
        var attribute = new WindowsSavedCredentialsLiveFactAttribute(
            isWindows: true,
            optInValue: null);

        Assert.False(string.IsNullOrWhiteSpace(attribute.Skip));
    }
}
