using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class QwenModelSettingsCardViewModelTests
{
    [Fact]
    public async Task Download_exposes_immediate_busy_state_and_success_feedback()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.NotDownloaded, operations);

        var operation = card.ExecutePrimaryAsync(CancellationToken.None);

        Assert.True(card.IsBusy);
        Assert.False(card.CanExecutePrimary);
        Assert.False(card.CanDelete);
        Assert.True(card.HasFeedback);
        Assert.Equal(L10n.Localize("SettingsModelActionDownloading"), card.FeedbackMessage);

        operations.DownloadCompletion.SetResult(CreateRecord(ModelInstallPhase.Ready));

        Assert.True(await operation);
        Assert.False(card.IsBusy);
        Assert.Equal(L10n.Localize("SettingsModelDownloadSucceeded"), card.FeedbackMessage);
        Assert.Equal(100D, card.ProgressPercent);
        Assert.True(card.CanDelete);
        Assert.Equal(1, operations.DownloadCalls);
    }

    [Fact]
    public async Task Download_failure_does_not_escape_and_shows_sanitized_feedback()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.NotDownloaded, operations);
        var operation = card.ExecutePrimaryAsync(CancellationToken.None);

        operations.DownloadCompletion.SetException(
            new InvalidOperationException("secret download diagnostic"));

        Assert.False(await operation);
        Assert.False(card.IsBusy);
        Assert.True(card.CanExecutePrimary);
        Assert.Equal(L10n.Localize("SettingsModelActionFailed"), card.FeedbackMessage);
        Assert.DoesNotContain("secret", card.FeedbackMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Retry_button_invokes_retry_and_reports_success()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.Failed, operations);

        var operation = card.ExecutePrimaryAsync(CancellationToken.None);

        Assert.True(card.IsBusy);
        Assert.Equal(L10n.Localize("SettingsModelActionDownloading"), card.FeedbackMessage);
        operations.DownloadCompletion.SetResult(CreateRecord(ModelInstallPhase.Ready));

        Assert.True(await operation);
        Assert.Equal(0, operations.DownloadCalls);
        Assert.Equal(1, operations.RetryCalls);
        Assert.Equal(L10n.Localize("SettingsModelDownloadSucceeded"), card.FeedbackMessage);
    }

    [Fact]
    public async Task Select_is_busy_during_dispatch_and_reports_success()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.Ready, operations);
        operations.OnSelect = _ => Assert.True(card.IsBusy);

        Assert.True(await card.ExecutePrimaryAsync(CancellationToken.None));

        Assert.Equal(TestModelId, operations.SelectedModelId);
        Assert.False(card.IsBusy);
        Assert.False(card.CanExecutePrimary);
        Assert.Equal(L10n.Localize("SettingsModelSelectSucceeded"), card.FeedbackMessage);
    }

    [Fact]
    public async Task Select_failure_does_not_escape_and_restores_the_button()
    {
        var operations = new CapturingQwenModelOperations
        {
            SelectException = new InvalidOperationException("sensitive selection diagnostic"),
        };
        var card = CreateCard(ModelInstallPhase.Ready, operations);

        Assert.False(await card.ExecutePrimaryAsync(CancellationToken.None));

        Assert.False(card.IsBusy);
        Assert.True(card.CanExecutePrimary);
        Assert.Equal(L10n.Localize("SettingsModelActionFailed"), card.FeedbackMessage);
        Assert.DoesNotContain("sensitive", card.FeedbackMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Delete_requires_confirmation_before_invoking_operations()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.Ready, operations);

        Assert.False(await card.DeleteAsync(confirmed: false, CancellationToken.None));

        Assert.Equal(0, operations.DeleteCalls);
        Assert.False(card.IsBusy);
        Assert.False(card.HasFeedback);
    }

    [Fact]
    public async Task Confirmed_delete_exposes_busy_state_and_success_feedback()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.Ready, operations);

        var operation = card.DeleteAsync(confirmed: true, CancellationToken.None);

        Assert.True(card.IsBusy);
        Assert.False(card.CanExecutePrimary);
        Assert.False(card.CanDelete);
        Assert.Equal(L10n.Localize("SettingsModelActionDeleting"), card.FeedbackMessage);

        operations.DeleteCompletion.SetResult(null);

        Assert.True(await operation);
        Assert.False(card.IsBusy);
        Assert.False(card.CanDelete);
        Assert.True(card.CanExecutePrimary);
        Assert.Equal(L10n.Localize("SettingsModelDeleteSucceeded"), card.FeedbackMessage);
        Assert.Equal(L10n.Localize("SettingsModelStatusNotDownloaded"), card.Status);
        Assert.Equal(1, operations.DeleteCalls);
    }

    [Fact]
    public async Task Delete_failure_does_not_escape_and_restores_actions()
    {
        var operations = new CapturingQwenModelOperations();
        var card = CreateCard(ModelInstallPhase.Ready, operations);
        var operation = card.DeleteAsync(confirmed: true, CancellationToken.None);

        operations.DeleteCompletion.SetException(
            new InvalidOperationException("private deletion diagnostic"));

        Assert.False(await operation);
        Assert.False(card.IsBusy);
        Assert.True(card.CanDelete);
        Assert.True(card.CanExecutePrimary);
        Assert.Equal(L10n.Localize("SettingsModelActionFailed"), card.FeedbackMessage);
        Assert.DoesNotContain("private", card.FeedbackMessage, StringComparison.OrdinalIgnoreCase);
    }

    private const string TestModelId = "qwen3-asr-0.6b";
    private const string TestRevision = "test-revision";

    private static QwenModelSettingsCardViewModel CreateCard(
        ModelInstallPhase phase,
        IQwenModelOperations operations)
    {
        var ready = phase == ModelInstallPhase.Ready;
        return new QwenModelSettingsCardViewModel(
            CreateManifest(),
            new QwenModelCardState(
                TestModelId,
                "Qwen3-ASR 0.6B",
                QwenVariant.Qwen06B,
                phase,
                ready ? 1 : 0,
                1,
                IsSelected: false,
                IsReady: ready,
                IsSelectable: ready,
                ErrorCode: null),
            operations);
    }

    private static QwenModelManifest CreateManifest() => new(
        TestModelId,
        "Qwen3-ASR 0.6B",
        QwenVariant.Qwen06B,
        TestRevision,
        "runtime-revision",
        totalBytes: 1,
        files:
        [
            new QwenModelFile(
                "model.bin",
                new Uri("https://example.test/model.bin"),
                bytes: 1,
                sha256: new string('a', 64)),
        ],
        runtimeGate: new QwenRuntimePublicationGate(IsPublishable: true, Blocker: null));

    private static ModelInstallRecord CreateRecord(ModelInstallPhase phase) => new(
        TestModelId,
        TestRevision,
        phase,
        bytesDownloaded: phase == ModelInstallPhase.Ready ? 1 : 0,
        totalBytes: 1,
        installPath: phase == ModelInstallPhase.Ready ? "C:\\Models\\Qwen" : null,
        errorCode: null);

    private sealed class CapturingQwenModelOperations : IQwenModelOperations
    {
        public TaskCompletionSource<ModelInstallRecord> DownloadCompletion { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<object?> DeleteCompletion { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public int DownloadCalls { get; private set; }

        public int RetryCalls { get; private set; }

        public int DeleteCalls { get; private set; }

        public string? SelectedModelId { get; private set; }

        public Exception? SelectException { get; init; }

        public Action<string>? OnSelect { get; set; }

        public Task<ModelInstallRecord> DownloadAsync(
            QwenModelManifest manifest,
            bool userInitiated,
            CancellationToken cancellationToken)
        {
            DownloadCalls++;
            return DownloadCompletion.Task;
        }

        public Task<ModelInstallRecord> RetryAsync(
            QwenModelManifest manifest,
            CancellationToken cancellationToken)
        {
            RetryCalls++;
            return DownloadCompletion.Task;
        }

        public Task PauseAsync(QwenModelManifest manifest) => Task.CompletedTask;

        public Task CancelAsync(QwenModelManifest manifest) => Task.CompletedTask;

        public async Task DeleteAsync(
            QwenModelManifest manifest,
            CancellationToken cancellationToken)
        {
            DeleteCalls++;
            _ = await DeleteCompletion.Task;
        }

        public void Select(string modelId)
        {
            OnSelect?.Invoke(modelId);
            if (SelectException is not null)
            {
                throw SelectException;
            }

            SelectedModelId = modelId;
        }
    }
}
