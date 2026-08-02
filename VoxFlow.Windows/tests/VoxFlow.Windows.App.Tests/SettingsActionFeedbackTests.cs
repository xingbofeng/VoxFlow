using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.App.Tests;

public sealed class SettingsActionFeedbackTests
{
    [Fact]
    public void Legacy_open_ai_card_disables_unavailable_actions_with_a_visible_reason()
    {
        var viewModel = new OpenAiSettingsCardViewModel(
            new SettingsStateCoordinator(new VoxFlowStateStore()));

        Assert.False(viewModel.CanExecuteActions);
        Assert.Equal(
            L10n.Localize("SettingsGeneralActionUnavailable"),
            viewModel.FeedbackMessage);
    }

    [Fact]
    public async Task Legacy_open_ai_save_failure_is_reported_instead_of_escaping_the_button_handler()
    {
        using var vault = new ThrowingCredentialVault();
        var service = new OpenAiSettingsService(
            vault,
            new MemoryLlmProviderSettingsStore(),
            new SuccessfulConnectionTester());
        var viewModel = new OpenAiSettingsCardViewModel(
            new SettingsStateCoordinator(new VoxFlowStateStore()),
            service);

        var saved = await viewModel.SaveAsync(
            "fixture-api-key",
            "https://example.test/v1",
            "fixture-model",
            selectedEnabled: true,
            CancellationToken.None);

        Assert.False(saved);
        Assert.False(viewModel.IsBusy);
        Assert.True(viewModel.CanExecuteActions);
        Assert.Equal(
            L10n.Localize("SettingsOperationFailed"),
            viewModel.FeedbackMessage);
    }

    [Fact]
    public async Task Text_settings_save_reports_success_and_restores_the_button()
    {
        var store = new CapturingTextSettingsStore();
        var stateStore = new VoxFlowStateStore();
        var viewModel = TextSettings(store, stateStore);
        viewModel.Enabled = true;

        var saved = await viewModel.SaveAsync(CancellationToken.None);

        Assert.True(saved);
        Assert.True(store.Saved?.Enabled);
        Assert.False(viewModel.IsBusy);
        Assert.True(viewModel.CanSave);
        Assert.Equal(L10n.Localize("SettingsSaveSucceeded"), viewModel.FeedbackMessage);
        Assert.Equal("true", stateStore.Current.State.Settings["text.enabled"]);
    }

    [Fact]
    public async Task Text_settings_save_failure_is_visible_and_does_not_publish_unsaved_state()
    {
        var stateStore = new VoxFlowStateStore();
        var viewModel = TextSettings(new ThrowingTextSettingsStore(), stateStore);
        viewModel.Enabled = true;

        var saved = await viewModel.SaveAsync(CancellationToken.None);

        Assert.False(saved);
        Assert.False(viewModel.IsBusy);
        Assert.True(viewModel.CanSave);
        Assert.Equal(
            L10n.Localize("SettingsOperationFailed"),
            viewModel.FeedbackMessage);
        Assert.False(stateStore.Current.State.Settings.ContainsKey("text.enabled"));
    }

    private static TextSettingsPageViewModel TextSettings(
        ITextProcessingSettingsStore store,
        VoxFlowStateStore stateStore) => new(store, stateStore);

    private sealed class CapturingTextSettingsStore : ITextProcessingSettingsStore
    {
        public DeterministicTextProcessingSettings? Saved { get; private set; }

        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(DeterministicTextProcessingSettings.Default);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken)
        {
            Saved = settings;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class ThrowingTextSettingsStore : ITextProcessingSettingsStore
    {
        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(DeterministicTextProcessingSettings.Default);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken) =>
            ValueTask.FromException(new InvalidOperationException("fixture failure"));
    }

    private sealed class ThrowingCredentialVault : ICredentialVault
    {
        public Task SaveAsync(
            CredentialKey key,
            string secret,
            CancellationToken cancellationToken = default) =>
            Task.FromException(new InvalidOperationException("fixture failure"));

        public Task<string?> ReadSecretAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<string?>(null);

        public Task<CredentialPresentation> GetPresentationAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(new CredentialPresentation(
                CredentialAvailability.Missing,
                string.Empty));

        public Task DeleteAsync(
            CredentialKey key,
            CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<int> DeleteOwnerAsync(
            string ownerKind,
            string ownerId,
            CancellationToken cancellationToken = default) => Task.FromResult(0);

        public void Dispose()
        {
        }
    }

    private sealed class MemoryLlmProviderSettingsStore : ILlmProviderSettingsStore
    {
        public ValueTask<LlmProviderSettings?> LoadAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult<LlmProviderSettings?>(null);

        public ValueTask SaveAsync(
            LlmProviderSettings settings,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask DeleteAsync(
            LlmProviderId provider,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }

    private sealed class SuccessfulConnectionTester : IOpenAiConnectionTester
    {
        public ValueTask<OpenAiConnectionTestResult> TestAsync(
            OpenAiClientConfiguration configuration,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(OpenAiConnectionTestResult.Success);
    }
}
