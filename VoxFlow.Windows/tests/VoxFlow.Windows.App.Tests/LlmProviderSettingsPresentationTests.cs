using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class LlmProviderSettingsPresentationTests
{
    [Fact]
    public async Task Provider_cards_templates_and_editor_project_mac_equivalent_fields()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true),
            Provider("deepseek", "DeepSeek", isDefault: false));
        var viewModel = new LlmProviderSettingsViewModel(service);

        await viewModel.LoadAsync(CancellationToken.None);

        Assert.Equal(2, viewModel.Providers.Count);
        Assert.Equal("openai", viewModel.Providers[0].Id);
        Assert.True(viewModel.Providers[0].IsDefault);
        Assert.Equal("••••••••", viewModel.Providers[0].ApiKeyPresentation);
        Assert.Equal(22, viewModel.TemplateOptions.Count);
        Assert.Equal("custom", viewModel.TemplateOptions[0].Id);
        Assert.Contains(viewModel.TemplateOptions, option => option.Id == "tencent-tokenhub");
        Assert.Contains(viewModel.TemplateOptions, option => option.Id == "opencode");
        var deepSeekOption = Assert.Single(
            viewModel.TemplateOptions,
            option => option.Id == "deepseek");
        Assert.Equal(
            new Uri("https://platform.deepseek.com/api_keys"),
            deepSeekOption.ApiKeyUri);

        viewModel.BeginAdd("deepseek");
        var editor = Assert.IsType<LlmProviderEditorViewModel>(viewModel.Editor);
        Assert.Equal("deepseek", editor.TemplateId);
        Assert.Equal("DeepSeek", editor.DisplayName);
        Assert.Equal("https://api.deepseek.com", editor.BaseUrl);
        Assert.Equal(30, editor.TimeoutSeconds);
        Assert.True(editor.RequiresApiKey);
        Assert.Equal(deepSeekOption.ApiKeyUri, editor.ApiKeyUri);
        Assert.True(editor.Enabled);
        // Modal editor starts masked (mac parity).
        Assert.False(editor.IsApiKeyVisible);
        Assert.Equal(string.Empty, editor.DraftApiKey);
        Assert.True(editor.HasApiKeyHelp);
        Assert.False(string.IsNullOrEmpty(editor.ApiKeyVisibilityGlyph));

        editor.Model = "deepseek-chat";
        editor.Temperature = 0.4;
        editor.TimeoutSeconds = 60;
        editor.AddCurrentModelToOptions();
        Assert.Contains("deepseek-chat", editor.ModelOptions);
        await viewModel.SaveEditorAsync(
            "new fixture key",
            CancellationToken.None);

        Assert.Equal("deepseek", service.LastDraft?.TemplateId);
        Assert.Equal("deepseek-chat", service.LastDraft?.Model);
        Assert.Equal(0.4, service.LastDraft?.Temperature);
        Assert.Equal(60, service.LastDraft?.TimeoutSeconds);
        Assert.Equal("new fixture key", service.LastApiKey);
        Assert.False(service.LastRetainExistingCredential);
        Assert.Null(viewModel.Editor);
    }

    [Fact]
    public async Task Edit_opens_with_masked_key_and_reveal_toggle_uses_saved_credential()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true));
        var viewModel = new LlmProviderSettingsViewModel(service);
        await viewModel.LoadAsync(CancellationToken.None);

        await viewModel.BeginEditAsync("openai", CancellationToken.None);
        var editor = Assert.IsType<LlmProviderEditorViewModel>(viewModel.Editor);
        Assert.False(editor.IsApiKeyVisible);
        Assert.Null(editor.RevealedApiKey);
        Assert.Equal(string.Empty, editor.DraftApiKey);
        Assert.True(editor.CanUseSavedCredential);
        Assert.Equal("••••••••", editor.ApiKeyPresentation);

        await viewModel.RevealApiKeyAsync(CancellationToken.None);
        Assert.Equal("revealed fixture key", editor.RevealedApiKey);
        Assert.Equal("revealed fixture key", editor.DraftApiKey);
        editor.IsApiKeyVisible = true;
        Assert.Equal(
            L10n.Localize("LlmProviderHideApiKey"),
            editor.ApiKeyVisibilityTooltip);

        editor.IsApiKeyVisible = false;
        Assert.False(editor.IsApiKeyVisible);
        Assert.Equal(
            L10n.Localize("LlmProviderRevealApiKey"),
            editor.ApiKeyVisibilityTooltip);

        viewModel.CancelEditor();
        Assert.Null(viewModel.Editor);
    }

    [Fact]
    public async Task Connection_test_immediately_disables_the_card_and_finishes_with_a_safe_inline_result()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true));
        service.DelayNextConnectionTest();
        var viewModel = new LlmProviderSettingsViewModel(service);
        await viewModel.LoadAsync(CancellationToken.None);

        var running = viewModel.TestConnectionAsync(
            "openai",
            CancellationToken.None);

        var testing = Assert.Single(viewModel.Providers);
        Assert.True(testing.IsBusy);
        Assert.True(testing.IsConnectionTesting);
        Assert.False(testing.CanRunActions);
        Assert.Equal(
            L10n.Localize("LlmProviderHealthTesting"),
            testing.DisplayedHealthStatusText);
        Assert.Equal(1, service.ConnectionCalls);

        var duplicate = await viewModel.TestConnectionAsync(
            "openai",
            CancellationToken.None);
        Assert.False(duplicate.Succeeded);
        Assert.Equal("provider_action_busy", duplicate.SafeMessage);
        Assert.Equal(1, service.ConnectionCalls);

        service.CompleteConnectionTest(new LlmConnectionTestResult(
            LlmConnectionTestStatus.Succeeded,
            18,
            "completion_ok"));
        var result = await running;

        Assert.True(result.Succeeded);
        var completed = Assert.Single(viewModel.Providers);
        Assert.False(completed.IsBusy);
        Assert.False(completed.IsConnectionTesting);
        Assert.True(completed.CanRunActions);
        var feedback = Assert.IsType<string>(completed.ActionFeedbackMessage);
        Assert.Contains(
            "completion_ok",
            feedback,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Agent_test_immediately_disables_the_card_and_surfaces_the_safe_capability_result()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true));
        service.DelayNextAgentTest();
        var viewModel = new LlmProviderSettingsViewModel(service);
        await viewModel.LoadAsync(CancellationToken.None);

        var running = viewModel.TestAgentAsync(
            "openai",
            CancellationToken.None);

        var testing = Assert.Single(viewModel.Providers);
        Assert.True(testing.IsBusy);
        Assert.True(testing.IsAgentTesting);
        Assert.False(testing.CanRunActions);
        Assert.Equal(
            L10n.Localize("LlmProviderHealthTesting"),
            testing.DisplayedAgentCapabilityStatusText);

        var duplicate = await viewModel.TestAgentAsync(
            "openai",
            CancellationToken.None);
        Assert.Equal(LlmAgentCapabilityStatus.Error, duplicate.Status);
        Assert.Equal("provider_action_busy", duplicate.SafeMessage);
        Assert.Equal(1, service.AgentCalls);

        service.CompleteAgentTest(new LlmAgentCapabilityTestResult(
            LlmAgentCapabilityStatus.Unsupported,
            "tool_calls_missing"));
        var result = await running;

        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, result.Status);
        var completed = Assert.Single(viewModel.Providers);
        Assert.False(completed.IsBusy);
        var feedback = Assert.IsType<string>(completed.ActionFeedbackMessage);
        Assert.Contains(
            "tool_calls_missing",
            feedback,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Failed_provider_test_clears_busy_and_never_exposes_exception_details()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true));
        service.DelayNextConnectionTest();
        var viewModel = new LlmProviderSettingsViewModel(service);
        await viewModel.LoadAsync(CancellationToken.None);

        var running = viewModel.TestConnectionAsync(
            "openai",
            CancellationToken.None);
        service.FailConnectionTest(
            new InvalidOperationException("sensitive upstream response body"));

        _ = await Assert.ThrowsAsync<InvalidOperationException>(() => running);
        var failed = Assert.Single(viewModel.Providers);
        Assert.False(failed.IsBusy);
        var feedback = Assert.IsType<string>(failed.ActionFeedbackMessage);
        Assert.Equal(
            L10n.Localize("LlmProviderActionFailed"),
            feedback);
        Assert.DoesNotContain(
            "sensitive upstream response body",
            feedback,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Slow_provider_completion_updates_bound_state_on_the_WPF_dispatcher()
    {
        await StaWpfTestHost.RunAsync(async context =>
        {
            _ = context;
            var dispatcher = System.Windows.Threading.Dispatcher.CurrentDispatcher;
            var service = new FakeManagementService(
                Provider("openai", "OpenAI", isDefault: true));
            service.DelayNextConnectionTest();
            var viewModel = new LlmProviderSettingsViewModel(service);
            await viewModel.LoadAsync(CancellationToken.None);
            var raisedOffDispatcher = false;
            viewModel.PropertyChanged += (_, _) =>
                raisedOffDispatcher |= !dispatcher.CheckAccess();

            var running = viewModel.TestConnectionAsync(
                "openai",
                CancellationToken.None);
            await Task.Run(() => service.CompleteConnectionTest(
                new LlmConnectionTestResult(
                    LlmConnectionTestStatus.Succeeded,
                    9,
                    "completion_ok")));
            await running;

            Assert.False(raisedOffDispatcher);
        });
    }

    [Fact]
    public async Task Edit_refresh_tests_reveal_default_toggle_and_delete_are_distinct_actions()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true),
            Provider("deepseek", "DeepSeek", isDefault: false));
        var viewModel = new LlmProviderSettingsViewModel(service);
        await viewModel.LoadAsync(CancellationToken.None);

        await viewModel.BeginEditAsync("deepseek", CancellationToken.None);
        var editor = Assert.IsType<LlmProviderEditorViewModel>(viewModel.Editor);
        Assert.True(editor.RetainExistingCredential);
        Assert.Equal("••••••••", editor.ApiKeyPresentation);
        await viewModel.RefreshModelsAsync(CancellationToken.None);
        Assert.Equal(["model-deepseek", "remote-model"], editor.ModelOptions);

        await viewModel.RevealApiKeyAsync(CancellationToken.None);
        Assert.True(editor.IsApiKeyVisible);
        Assert.Equal("revealed fixture key", editor.RevealedApiKey);
        Assert.Contains("[REDACTED]", editor.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(
            "revealed fixture key",
            editor.ToString(),
            StringComparison.Ordinal);

        Assert.True(viewModel.SetDefault("deepseek"));
        Assert.Equal("deepseek", service.SetDefaultId);
        Assert.True(viewModel.SetEnabled("deepseek", enabled: false));
        Assert.Equal(("deepseek", false), service.SetEnabledCall);
        var connection = await viewModel.TestConnectionAsync(
            "deepseek",
            CancellationToken.None);
        var agent = await viewModel.TestAgentAsync(
            "deepseek",
            CancellationToken.None);
        Assert.True(connection.Succeeded);
        Assert.Equal(LlmAgentCapabilityStatus.Unsupported, agent.Status);
        Assert.Equal(1, service.ConnectionCalls);
        Assert.Equal(1, service.AgentCalls);
        Assert.True(await viewModel.DeleteAsync(
            "deepseek",
            confirmed: true,
            CancellationToken.None));
        Assert.DoesNotContain(viewModel.Providers, provider => provider.Id == "deepseek");
    }

    [Fact]
    public async Task Default_and_enabled_failures_are_safe_visible_and_do_not_escape_click_handlers()
    {
        var service = new FakeManagementService(
            Provider("openai", "OpenAI", isDefault: true))
        {
            ThrowOnSetDefault = true,
            ThrowOnSetEnabled = true,
        };
        var viewModel = new LlmProviderSettingsViewModel(service);
        await viewModel.LoadAsync(CancellationToken.None);

        Assert.False(viewModel.SetDefault("openai"));
        Assert.Equal(
            L10n.Localize("LlmProviderActionFailed"),
            viewModel.FeedbackMessage);
        Assert.False(viewModel.SetEnabled("openai", enabled: false));
        var feedback = Assert.IsType<string>(viewModel.FeedbackMessage);
        Assert.Equal(
            L10n.Localize("LlmProviderActionFailed"),
            feedback);
        Assert.DoesNotContain(
            "sensitive fixture failure",
            feedback,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Models_page_exposes_new_provider_presentation_only_when_management_is_available()
    {
        var coordinator = new SettingsStateCoordinator(
            new VoxFlow.Windows.Application.State.VoxFlowStateStore());
        var legacy = new OpenAiSettingsCardViewModel(coordinator);
        var disabled = new ModelsSettingsPageViewModel(legacy);
        var enabled = new ModelsSettingsPageViewModel(
            legacy,
            cloudSettings: null,
            llmProviderManagement: new FakeManagementService());

        Assert.Null(disabled.LlmProviders);
        Assert.NotNull(enabled.LlmProviders);
        Assert.Same(legacy, disabled.OpenAi);
        Assert.Equal(new[] { "asr", "llm", "agent" }, disabled.Tabs.Select(tab => tab.Id));
        Assert.Equal(new[] { "asr", "llm", "agent" }, enabled.Tabs.Select(tab => tab.Id));
    }

    [Fact]
    public void Agent_card_projects_only_the_verified_runtime_and_default_provider_health()
    {
        var provider = Provider("openai", "OpenAI", isDefault: true);
        var runtime = new BuiltinAgentRuntimeStatus(
            BuiltinAgentRuntimeAvailability.HashMismatch,
            "0.1.0",
            null)
        {
            ExpectedSha256 = new string('a', 64),
        };

        var page = new ModelsSettingsPageViewModel(
            new OpenAiSettingsCardViewModel(new SettingsStateCoordinator(
                new VoxFlow.Windows.Application.State.VoxFlowStateStore())),
            llmProviderManagement: new FakeManagementService(provider),
            builtinAgentRuntime: runtime);

        Assert.Equal("agent", page.Tabs[2].Id);
        Assert.False(page.BuiltinAgent.IsRuntimeAvailable);
        Assert.Equal("0.1.0", page.BuiltinAgent.Version);
        Assert.Equal(new string('a', 64), page.BuiltinAgent.Hash);
        Assert.Equal("OpenAI", page.BuiltinAgent.Provider);
        Assert.Equal("model-openai", page.BuiltinAgent.Model);
        Assert.Equal(
            L10n.Localize("SettingsAgentRuntimeHashMismatch"),
            page.BuiltinAgent.RuntimeStatus);
        Assert.Equal(
            L10n.Localize("LlmProviderAgentUnsupported"),
            page.BuiltinAgent.ToolCallingHealth);
    }

    [Fact]
    public void Entering_agent_tab_refreshes_provider_added_after_page_creation()
    {
        var service = new FakeManagementService();
        var runtime = new BuiltinAgentRuntimeStatus(
            BuiltinAgentRuntimeAvailability.Available,
            "0.1.0",
            new BuiltinAgentBinaryDescriptor(
                @"C:\Program Files\VoxFlow\runtime\agent\voxflow-agent.exe",
                new string('a', 64)));
        var page = new ModelsSettingsPageViewModel(
            new OpenAiSettingsCardViewModel(new SettingsStateCoordinator(
                new VoxFlow.Windows.Application.State.VoxFlowStateStore())),
            llmProviderManagement: service,
            builtinAgentRuntime: runtime);

        Assert.False(page.BuiltinAgent.CanTest);
        service.AddProvider(Provider("deepseek", "DeepSeek", isDefault: true));

        page.SelectedTab = ModelsSettingsTab.Agent;

        Assert.Equal("DeepSeek", page.BuiltinAgent.Provider);
        Assert.Equal("model-deepseek", page.BuiltinAgent.Model);
        Assert.True(page.BuiltinAgent.CanTest);
    }

    private static LlmProviderRecord Provider(
        string id,
        string name,
        bool isDefault) => new(
            id,
            name,
            LlmProviderType.OpenAiCompatible,
            new Uri($"https://{id}.example/v1"),
            $"model-{id}",
            $"llm-provider/{id}/api_key",
            0.2,
            30,
            enabled: true,
            isDefault,
            LlmProviderHealthStatus.Ok,
            "completion_ok",
            23,
            900,
            LlmAgentCapabilityStatus.Unsupported,
            "tool_calls_missing",
            901,
            100,
            901);

    private sealed class FakeManagementService : ILlmProviderManagementService
    {
        private readonly List<LlmProviderRecord> providers;

        public FakeManagementService(params LlmProviderRecord[] providers)
        {
            this.providers = [.. providers];
        }

        public LlmProviderDraft? LastDraft { get; private set; }

        public string? LastApiKey { get; private set; }

        public bool LastRetainExistingCredential { get; private set; }

        public string? SetDefaultId { get; private set; }

        public (string Id, bool Enabled)? SetEnabledCall { get; private set; }

        public bool ThrowOnSetDefault { get; init; }

        public bool ThrowOnSetEnabled { get; init; }

        public int ConnectionCalls { get; private set; }

        public int AgentCalls { get; private set; }

        private TaskCompletionSource<LlmConnectionTestResult>?
            pendingConnectionTest;

        private TaskCompletionSource<LlmAgentCapabilityTestResult>?
            pendingAgentTest;

        public IReadOnlyList<LlmProviderRecord> List() => providers.ToArray();

        public void AddProvider(LlmProviderRecord provider) => providers.Add(provider);

        public Task<LlmProviderRecord> SaveAsync(
            LlmProviderDraft draft,
            string? apiKey,
            bool retainExistingCredential,
            CancellationToken cancellationToken)
        {
            LastDraft = draft;
            LastApiKey = apiKey;
            LastRetainExistingCredential = retainExistingCredential;
            var saved = Provider(
                draft.ProviderId ?? "saved-provider",
                draft.DisplayName,
                draft.IsDefault);
            providers.RemoveAll(provider => provider.Id == saved.Id);
            providers.Add(saved);
            return Task.FromResult(saved);
        }

        public bool SetDefault(string providerId)
        {
            if (ThrowOnSetDefault)
            {
                throw new InvalidOperationException("sensitive fixture failure");
            }
            SetDefaultId = providerId;
            return providers.Any(provider => provider.Id == providerId);
        }

        public bool SetEnabled(string providerId, bool enabled)
        {
            if (ThrowOnSetEnabled)
            {
                throw new InvalidOperationException("sensitive fixture failure");
            }
            SetEnabledCall = (providerId, enabled);
            return providers.Any(provider => provider.Id == providerId);
        }

        public Task<bool> DeleteAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            Task.FromResult(providers.RemoveAll(provider =>
                provider.Id == providerId) > 0);

        public ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
            string providerId,
            CancellationToken cancellationToken) => ValueTask.FromResult(
                new LlmModelDiscoveryResult(
                    [
                        new LlmModelDescriptor($"model-{providerId}", null, null),
                        new LlmModelDescriptor("remote-model", null, null),
                    ],
                    LlmModelDiscoverySource.Remote));

        public ValueTask<LlmConnectionTestResult> TestConnectionAsync(
            string providerId,
            CancellationToken cancellationToken)
        {
            ConnectionCalls++;
            if (pendingConnectionTest is { } pending)
            {
                return new ValueTask<LlmConnectionTestResult>(pending.Task);
            }
            return ValueTask.FromResult(new LlmConnectionTestResult(
                LlmConnectionTestStatus.Succeeded,
                12,
                null));
        }

        public ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
            string providerId,
            CancellationToken cancellationToken)
        {
            AgentCalls++;
            if (pendingAgentTest is { } pending)
            {
                return new ValueTask<LlmAgentCapabilityTestResult>(pending.Task);
            }
            return ValueTask.FromResult(new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Unsupported,
                "tool_calls_missing"));
        }

        public void DelayNextConnectionTest() => pendingConnectionTest = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public void CompleteConnectionTest(LlmConnectionTestResult result) =>
            Assert.True(pendingConnectionTest?.TrySetResult(result));

        public void FailConnectionTest(Exception exception) =>
            Assert.True(pendingConnectionTest?.TrySetException(exception));

        public void DelayNextAgentTest() => pendingAgentTest = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public void CompleteAgentTest(LlmAgentCapabilityTestResult result) =>
            Assert.True(pendingAgentTest?.TrySetResult(result));

        public Task<CredentialPresentation> GetCredentialPresentationAsync(
            string providerId,
            CancellationToken cancellationToken) => Task.FromResult(
                new CredentialPresentation(
                    CredentialAvailability.Available,
                    "••••••••"));

        public Task<string?> RevealApiKeyAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            Task.FromResult<string?>("revealed fixture key");
    }
}
