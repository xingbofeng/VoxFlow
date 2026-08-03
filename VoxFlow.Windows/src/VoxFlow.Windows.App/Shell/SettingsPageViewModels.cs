using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Providers.Cloud.OpenAI;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;
using VoxFlow.Windows.Platform.Audio;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Shell;

public enum SettingsRoute
{
    General,
    Models,
    Voice,
    Translation,
    Screenshot,
    Text,
}

public enum ModelsSettingsTab
{
    Asr,
    Llm,
    Agent,
}

public sealed record SettingsNavigationItemViewModel(
    string Id,
    SettingsRoute Route,
    string Label,
    string Glyph);

public sealed record SettingsTabViewModel(
    string Id,
    ModelsSettingsTab Tab,
    string Label);

public sealed record SettingsCardViewModel(
    string Id,
    string Heading,
    string Description);

public sealed record SettingsActionViewModel(string Id, string Label);

public sealed record SettingsChoiceViewModel(string Id, string Label);

/// <summary>
/// Abstraction over WASAPI capture enumeration so settings UI and tests share one path.
/// </summary>
public interface ICaptureDeviceCatalog
{
    IReadOnlyList<AudioDeviceInfo> ListCaptureDevices();
}

public sealed class WasapiCaptureDeviceCatalog : ICaptureDeviceCatalog
{
    public IReadOnlyList<AudioDeviceInfo> ListCaptureDevices() =>
        WasapiMicrophoneCapture.EnumerateDevices();
}

public sealed record ProviderSettingsCardViewModel(
    string Id,
    string Heading,
    string Description,
    string Status);

public sealed class QwenModelSettingsCardViewModel : BindableObject
{
    private readonly QwenModelManifest manifest;
    private readonly IQwenModelOperations operations;
    private QwenModelCardState state;
    private bool isBusy;
    private string? feedbackMessage;

    public QwenModelSettingsCardViewModel(
        QwenModelManifest manifest,
        QwenModelCardState state,
        IQwenModelOperations operations)
    {
        this.manifest = manifest;
        this.state = state;
        this.operations = operations;
    }

    public string Id => manifest.Id;
    public string Heading => manifest.DisplayName;
    public string Description => L10n.Localize(manifest.Variant == QwenVariant.Qwen06B
        ? "SettingsProviderQwen06Description"
        : "SettingsProviderQwen17Description");
    public double ProgressPercent => state.Progress * 100D;
    public bool ShowsProgress => state.Phase == ModelInstallPhase.Downloading;
    public bool CanExecutePrimary => !IsBusy && !state.IsSelected;
    public bool CanDelete => !IsBusy && state.Phase != ModelInstallPhase.NotDownloaded;
    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set
        {
            if (SetField(ref feedbackMessage, value))
            {
                OnPropertyChanged(nameof(HasFeedback));
            }
        }
    }
    public bool HasFeedback => !string.IsNullOrWhiteSpace(FeedbackMessage);
    public bool IsBusy
    {
        get => isBusy;
        private set
        {
            if (SetField(ref isBusy, value))
            {
                OnPropertyChanged(nameof(CanDelete));
                OnPropertyChanged(nameof(CanExecutePrimary));
            }
        }
    }
    public string Status => state.Phase switch
    {
        ModelInstallPhase.NotDownloaded => L10n.Localize("SettingsModelStatusNotDownloaded"),
        ModelInstallPhase.Downloading => string.Format(
            CultureInfo.CurrentCulture,
            L10n.Localize("SettingsModelStatusDownloadingFormat"),
            ProgressPercent),
        ModelInstallPhase.Ready when state.IsSelected => L10n.Localize("SettingsModelStatusSelected"),
        ModelInstallPhase.Ready => L10n.Localize("SettingsModelStatusReady"),
        ModelInstallPhase.InsufficientSpace => L10n.Localize("SettingsModelStatusInsufficientSpace"),
        ModelInstallPhase.Corrupted or ModelInstallPhase.Failed => L10n.Localize("SettingsModelStatusFailed"),
        _ => L10n.Localize("SettingsModelStatusPreparing"),
    };
    public string PrimaryActionLabel => state.IsReady
        ? state.IsSelected
            ? L10n.Localize("SettingsModelSelected")
            : L10n.Localize("SettingsModelSelect")
        : state.Phase is ModelInstallPhase.Failed
            or ModelInstallPhase.Corrupted
            or ModelInstallPhase.InsufficientSpace
            ? L10n.Localize("SettingsModelRetry")
            : L10n.Localize("SettingsModelDownload");

    public async Task<bool> ExecutePrimaryAsync(CancellationToken cancellationToken)
    {
        if (IsBusy)
        {
            return false;
        }

        IsBusy = true;
        try
        {
            if (state.IsReady)
            {
                SetFeedback("SettingsModelActionSelecting");
                operations.Select(manifest.Id);
                Apply(state with { IsSelected = true });
                SetFeedback("SettingsModelSelectSucceeded");
                return true;
            }

            SetFeedback("SettingsModelActionDownloading");
            var result = state.Phase is ModelInstallPhase.Failed
                or ModelInstallPhase.Corrupted
                or ModelInstallPhase.InsufficientSpace
                ? await operations.RetryAsync(manifest, cancellationToken)
                : await operations.DownloadAsync(manifest, true, cancellationToken);
            Apply(result);
            if (result.Phase != ModelInstallPhase.Ready
                || !manifest.RuntimeGate.IsPublishable)
            {
                SetFeedback("SettingsModelActionFailed");
                return false;
            }

            SetFeedback("SettingsModelDownloadSucceeded");
            return true;
        }
        catch
        {
            SetFeedback("SettingsModelActionFailed");
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task<bool> DeleteAsync(
        bool confirmed,
        CancellationToken cancellationToken)
    {
        if (!confirmed || IsBusy)
        {
            return false;
        }

        IsBusy = true;
        SetFeedback("SettingsModelActionDeleting");
        try
        {
            await operations.DeleteAsync(manifest, cancellationToken);
            Apply(state with
            {
                Phase = ModelInstallPhase.NotDownloaded,
                BytesDownloaded = 0,
                IsSelected = false,
                IsReady = false,
                IsSelectable = false,
                ErrorCode = null,
            });
            SetFeedback("SettingsModelDeleteSucceeded");
            return true;
        }
        catch
        {
            SetFeedback("SettingsModelActionFailed");
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    internal void ReportUnexpectedFailure()
    {
        SetFeedback("SettingsModelActionFailed");
        IsBusy = false;
    }

    public void Apply(QwenModelCardState next)
    {
        state = next;
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(ProgressPercent));
        OnPropertyChanged(nameof(ShowsProgress));
        OnPropertyChanged(nameof(CanDelete));
        OnPropertyChanged(nameof(CanExecutePrimary));
        OnPropertyChanged(nameof(PrimaryActionLabel));
    }

    private void Apply(ModelInstallRecord next)
    {
        var ready = next.Phase == ModelInstallPhase.Ready
            && manifest.RuntimeGate.IsPublishable;
        Apply(state with
        {
            Phase = next.Phase,
            BytesDownloaded = next.BytesDownloaded,
            TotalBytes = next.TotalBytes,
            IsSelected = ready && state.IsSelected,
            IsReady = ready,
            IsSelectable = ready,
            ErrorCode = next.ErrorCode,
        });
    }

    private void SetFeedback(string key) =>
        FeedbackMessage = L10n.Localize(key);
}

public sealed class CloudProviderSettingsCardViewModel : BindableObject
{
    private bool isConfigured;
    private bool isReady;
    private bool isSelected;
    private bool isBusy;
    private bool secretsVisible;
    private string firstCredentialPresentation;
    private string secondCredentialPresentation;
    private string thirdCredentialPresentation;
    private string? feedbackMessage;

    public CloudProviderSettingsCardViewModel(
        AsrProviderId provider,
        string heading,
        string description)
    {
        if (provider == AsrProviderId.Qwen)
        {
            throw new ArgumentException("A cloud card cannot represent Qwen.", nameof(provider));
        }

        Provider = provider;
        Heading = heading;
        Description = description;
        firstCredentialPresentation = L10n.Localize("SettingsCredentialNotConfigured");
        secondCredentialPresentation = L10n.Localize("SettingsCredentialNotConfigured");
        thirdCredentialPresentation = L10n.Localize("SettingsCredentialNotConfigured");
    }

    public AsrProviderId Provider { get; }

    public string Heading { get; }

    public string Description { get; }

    public bool IsConfigured
    {
        get => isConfigured;
        private set => SetField(ref isConfigured, value);
    }

    public bool IsReady
    {
        get => isReady;
        private set => SetField(ref isReady, value);
    }

    public bool IsSelected
    {
        get => isSelected;
        private set
        {
            if (SetField(ref isSelected, value))
            {
                OnPropertyChanged(nameof(Status));
                OnPropertyChanged(nameof(SelectActionLabel));
                OnPropertyChanged(nameof(CanSelect));
            }
        }
    }

    public bool IsBusy
    {
        get => isBusy;
        private set
        {
            if (SetField(ref isBusy, value))
            {
                OnPropertyChanged(nameof(CanExecuteActions));
                OnPropertyChanged(nameof(CanSelect));
                OnPropertyChanged(nameof(CanRevealSecrets));
            }
        }
    }

    public bool SecretsVisible
    {
        get => secretsVisible;
        private set
        {
            if (SetField(ref secretsVisible, value))
            {
                OnPropertyChanged(nameof(RevealActionLabel));
                OnPropertyChanged(nameof(RevealGlyph));
            }
        }
    }

    public bool CanExecuteActions => !IsBusy;

    public bool CanSelect => !IsBusy && IsReady && !IsSelected;

    public bool CanRevealSecrets => !IsBusy && IsConfigured;

    public string RevealActionLabel => L10n.Localize(
        SecretsVisible ? "SettingsCredentialHide" : "SettingsCredentialShow");

    /// <summary>Eye / eye-slash glyph for reveal toggle (matches macOS credential UI).</summary>
    public string RevealGlyph => SecretsVisible ? "🙈" : "👁";

    public string SelectActionLabel => L10n.Localize(
        IsSelected ? "SettingsModelSelected" : "SettingsCloudSelect");

    public string FirstCredentialPresentation
    {
        get => firstCredentialPresentation;
        private set
        {
            if (SetField(ref firstCredentialPresentation, value))
            {
                OnPropertyChanged(nameof(CredentialSummary));
            }
        }
    }

    public string SecondCredentialPresentation
    {
        get => secondCredentialPresentation;
        private set
        {
            if (SetField(ref secondCredentialPresentation, value))
            {
                OnPropertyChanged(nameof(CredentialSummary));
            }
        }
    }

    public string ThirdCredentialPresentation
    {
        get => thirdCredentialPresentation;
        private set
        {
            if (SetField(ref thirdCredentialPresentation, value))
            {
                OnPropertyChanged(nameof(CredentialSummary));
            }
        }
    }

    public string CredentialSummary => string.Join(
        " ",
        new[]
        {
            FirstCredentialPresentation,
            SecondCredentialPresentation,
            ThirdCredentialPresentation,
        }.Where(value => !string.IsNullOrWhiteSpace(value)));

    public string Status => L10n.Localize(IsSelected
        ? "SettingsModelStatusSelected"
        : IsReady
            ? "SettingsStatusReady"
            : IsConfigured
                ? "SettingsStatusConfigured"
                : "SettingsStatusNotConfigured");

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public void Apply(
        bool configured,
        bool ready,
        string? feedbackKey = null,
        bool? selected = null)
    {
        IsConfigured = configured;
        IsReady = ready;
        if (selected is not null)
        {
            IsSelected = selected.Value;
        }

        if (!configured)
        {
            SecretsVisible = false;
        }

        FeedbackMessage = feedbackKey is null ? null : L10n.Localize(feedbackKey);
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(CanSelect));
        OnPropertyChanged(nameof(CanRevealSecrets));
        OnPropertyChanged(nameof(SelectActionLabel));
    }

    public void SetSelected(bool selected) => IsSelected = selected;

    public void SetSecretsVisible(bool visible) => SecretsVisible = visible;

    public void ApplyCredentialPresentations(params CredentialPresentation[] presentations)
    {
        ArgumentNullException.ThrowIfNull(presentations);
        FirstCredentialPresentation = Present(presentations.ElementAtOrDefault(0));
        SecondCredentialPresentation = Present(presentations.ElementAtOrDefault(1));
        ThirdCredentialPresentation = Present(presentations.ElementAtOrDefault(2));
    }

    public bool TryBeginOperation(string feedbackKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(feedbackKey);
        if (IsBusy)
        {
            return false;
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize(feedbackKey);
        return true;
    }

    public void CompleteOperation(bool configured, bool ready, string feedbackKey)
    {
        Apply(configured, ready, feedbackKey);
        IsBusy = false;
    }

    public void FailOperation()
    {
        FeedbackMessage = L10n.Localize("SettingsOperationFailed");
        IsBusy = false;
    }

    public void CancelOperation()
    {
        FeedbackMessage = null;
        IsBusy = false;
    }

    private static string Present(CredentialPresentation? presentation) =>
        presentation is { Mask.Length: > 0 }
            ? presentation.Mask
            : L10n.Localize("SettingsCredentialNotConfigured");
}

public sealed class OpenAiSettingsCardViewModel : BindableObject
{
    private readonly OpenAiSettingsService? service;
    private readonly SettingsStateCoordinator coordinator;
    private string model = OpenAiProductionDefaults.DefaultModel;
    private string baseUrl = OpenAiProductionDefaults.BaseUri.AbsoluteUri.TrimEnd('/');
    private bool enabled;
    private bool isConfigured;
    private bool isBusy;
    private string apiKeyPresentation;
    private string? feedbackMessage;

    public OpenAiSettingsCardViewModel(
        SettingsStateCoordinator coordinator,
        OpenAiSettingsService? service = null)
    {
        this.coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        this.service = service;
        apiKeyPresentation = L10n.Localize("SettingsCredentialNotConfigured");
        Actions =
        [
            new("save", L10n.Localize("SettingsActionSave")),
            new("test", L10n.Localize("SettingsActionTest")),
            new("delete", L10n.Localize("SettingsActionDelete")),
        ];
        if (service is null)
        {
            feedbackMessage = L10n.Localize("SettingsGeneralActionUnavailable");
        }
    }

    public string Heading => L10n.Localize("SettingsOpenAiHeading");

    public string Description => L10n.Localize("SettingsOpenAiDescription");

    public string BaseUrl
    {
        get => baseUrl;
        set
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(value);
            SetField(ref baseUrl, value.Trim());
        }
    }

    public bool CanEditBaseUrl => true;

    public string Model
    {
        get => model;
        set
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(value);
            SetField(ref model, value.Trim());
        }
    }

    public bool Enabled
    {
        get => enabled;
        set => SetField(ref enabled, value);
    }

    public string ApiKeyPresentation
    {
        get => apiKeyPresentation;
        private set => SetField(ref apiKeyPresentation, value);
    }

    public bool IsConfigured
    {
        get => isConfigured;
        private set => SetField(ref isConfigured, value);
    }

    public bool IsBusy
    {
        get => isBusy;
        private set
        {
            if (SetField(ref isBusy, value))
            {
                OnPropertyChanged(nameof(CanExecuteActions));
            }
        }
    }

    public bool CanExecuteActions => service is not null && !IsBusy;

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public IReadOnlyList<SettingsActionViewModel> Actions { get; }

    public async Task LoadAsync(CancellationToken cancellationToken)
    {
        if (service is null)
        {
            coordinator.RecordOpenAi(configured: false, enabled: false);
            return;
        }

        var status = await service.GetStatusAsync(cancellationToken).ConfigureAwait(true);
        Model = status.Model;
        BaseUrl = status.BaseUri.AbsoluteUri.TrimEnd('/');
        Enabled = status.Enabled;
        IsConfigured = status.IsConfigured;
        ApiKeyPresentation = status.ApiKey.Mask;
        coordinator.RecordOpenAi(IsConfigured, Enabled);
    }

    public Task<bool> SaveAsync(
        string apiKey,
        string selectedModel,
        bool selectedEnabled,
        CancellationToken cancellationToken) => SaveAsync(
            apiKey,
            BaseUrl,
            selectedModel,
            selectedEnabled,
            cancellationToken);

    public async Task<bool> SaveAsync(
        string apiKey,
        string selectedBaseUrl,
        string selectedModel,
        bool selectedEnabled,
        CancellationToken cancellationToken)
    {
        if (service is null)
        {
            ReportUiFailure("SettingsGeneralActionUnavailable");
            return false;
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize("SettingsOperationSaving");
        try
        {
            await service.SaveAsync(
                    apiKey,
                new Uri(selectedBaseUrl, UriKind.Absolute),
                selectedModel,
                selectedEnabled,
                cancellationToken)
                .ConfigureAwait(true);
            Model = selectedModel;
            BaseUrl = selectedBaseUrl;
            Enabled = selectedEnabled;
            IsConfigured = true;
            ApiKeyPresentation = L10n.Localize("SettingsCredentialConfigured");
            FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
            coordinator.RecordOpenAi(configured: true, enabled: selectedEnabled);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            FeedbackMessage = null;
            throw;
        }
        catch
        {
            ReportUiFailure();
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task<bool> TestConnectionAsync(CancellationToken cancellationToken)
    {
        if (service is null)
        {
            ReportUiFailure("SettingsGeneralActionUnavailable");
            return false;
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize("SettingsOperationTesting");
        try
        {
            var result = await service.TestConnectionAsync(cancellationToken)
                .ConfigureAwait(true);
            FeedbackMessage = L10n.Localize(
                result.Succeeded
                    ? "SettingsConnectionSucceeded"
                    : "SettingsConnectionFailed");
            return result.Succeeded;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            FeedbackMessage = null;
            throw;
        }
        catch
        {
            ReportUiFailure();
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task<bool> DeleteAsync(
        bool confirmed,
        CancellationToken cancellationToken)
    {
        if (!confirmed || service is null)
        {
            if (confirmed && service is null)
            {
                ReportUiFailure("SettingsGeneralActionUnavailable");
            }

            return false;
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize("SettingsOperationSaving");
        try
        {
            await service.DeleteAsync(cancellationToken).ConfigureAwait(true);
            Enabled = false;
            IsConfigured = false;
            ApiKeyPresentation = L10n.Localize("SettingsCredentialNotConfigured");
            FeedbackMessage = L10n.Localize("SettingsDeleteSucceeded");
            coordinator.RecordOpenAi(configured: false, enabled: false);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            FeedbackMessage = null;
            throw;
        }
        catch
        {
            ReportUiFailure();
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    public void ReportUiFailure(string messageKey = "SettingsOperationFailed") =>
        FeedbackMessage = L10n.Localize(messageKey);
}

public sealed class ModelsSettingsPageViewModel : BindableObject
{
    private readonly CloudAsrSettingsCoordinator? cloudSettings;
    private readonly VoxFlowStateStore? stateStore;
    private ModelsSettingsTab selectedTab;

    public ModelsSettingsPageViewModel(
        OpenAiSettingsCardViewModel openAi,
        CloudAsrSettingsCoordinator? cloudSettings = null,
        ILlmProviderManagementService? llmProviderManagement = null,
        QwenModelCatalog? qwenCatalog = null,
        QwenModelEntryPointProjection? qwenProjection = null,
        IQwenModelOperations? qwenOperations = null,
        BuiltinAgentRuntimeStatus? builtinAgentRuntime = null,
        VoxFlowStateStore? stateStore = null)
    {
        OpenAi = openAi ?? throw new ArgumentNullException(nameof(openAi));
        this.cloudSettings = cloudSettings;
        this.stateStore = stateStore;
        LlmProviders = llmProviderManagement is null
            ? null
            : new LlmProviderSettingsViewModel(llmProviderManagement);
        Tabs =
        [
            new("asr", ModelsSettingsTab.Asr, L10n.Localize("SettingsModelsAsrTab")),
            new("llm", ModelsSettingsTab.Llm, L10n.Localize("SettingsModelsLlmTab")),
            new("agent", ModelsSettingsTab.Agent, L10n.Localize("SettingsModelsAgentTab")),
        ];
        BuiltinAgent = new BuiltinAgentSettingsCardViewModel(
            builtinAgentRuntime,
            llmProviderManagement);
        if (qwenCatalog is not null && qwenProjection is not null && qwenOperations is not null)
        {
            var states = qwenProjection.Current.Models.ToDictionary(model => model.Id);
            QwenCards = qwenCatalog.Models.Select(manifest =>
                new QwenModelSettingsCardViewModel(
                    manifest,
                    states[manifest.Id],
                    qwenOperations)).ToArray();
            qwenProjection.Changed += snapshot =>
            {
                var next = snapshot.Models.ToDictionary(model => model.Id);
                foreach (var card in QwenCards)
                {
                    card.Apply(next[card.Id]);
                }
            };
        }
        else
        {
            QwenCards = [];
        }
        Tencent = CloudCard(
            AsrProviderId.TencentCloud,
            "HistorySourceTencent",
            "SettingsProviderTencentDescription");
        Aliyun = CloudCard(
            AsrProviderId.AliyunDashScope,
            "HistorySourceAliyun",
            "SettingsProviderAliyunDescription");
        Volcengine = CloudCard(
            AsrProviderId.Volcengine,
            "HistorySourceVolcengine",
            "SettingsProviderVolcengineDescription");
    }

    public string Heading => L10n.Localize("SettingsModelsHeading");

    public string Subtitle => L10n.Localize("SettingsModelsSubtitle");

    public IReadOnlyList<SettingsTabViewModel> Tabs { get; }

    public IReadOnlyList<QwenModelSettingsCardViewModel> QwenCards { get; }

    public OpenAiSettingsCardViewModel OpenAi { get; }

    public LlmProviderSettingsViewModel? LlmProviders { get; }

    public bool HasLlmProviderManagement => LlmProviders is not null;

    public bool UsesLegacyOpenAiCard => LlmProviders is null;

    public BuiltinAgentSettingsCardViewModel BuiltinAgent { get; }

    public CloudProviderSettingsCardViewModel Tencent { get; }

    public CloudProviderSettingsCardViewModel Aliyun { get; }

    public CloudProviderSettingsCardViewModel Volcengine { get; }

    public bool CanManageCloudProviders => cloudSettings is not null;

    public int SelectedTabIndex
    {
        get => (int)SelectedTab;
        set => SelectedTab = value switch
        {
            0 => ModelsSettingsTab.Asr,
            1 => ModelsSettingsTab.Llm,
            2 => ModelsSettingsTab.Agent,
            _ => throw new ArgumentOutOfRangeException(nameof(value)),
        };
    }

    public ModelsSettingsTab SelectedTab
    {
        get => selectedTab;
        set
        {
            if (!Enum.IsDefined(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }

            if (SetField(ref selectedTab, value))
            {
                OnPropertyChanged(nameof(SelectedTabId));
                OnPropertyChanged(nameof(SelectedTabIndex));
            }

            if (value == ModelsSettingsTab.Agent)
            {
                BuiltinAgent.Refresh();
            }
        }
    }

    public string SelectedTabId => SelectedTab switch
    {
        ModelsSettingsTab.Asr => "asr",
        ModelsSettingsTab.Llm => "llm",
        ModelsSettingsTab.Agent => "agent",
        _ => throw new ArgumentOutOfRangeException(),
    };

    public bool TrySelectTab(string tabId)
    {
        var tab = tabId.Trim().ToLowerInvariant() switch
        {
            "asr" => ModelsSettingsTab.Asr,
            "llm" => ModelsSettingsTab.Llm,
            "agent" => ModelsSettingsTab.Agent,
            _ => (ModelsSettingsTab?)null,
        };
        if (tab is null)
        {
            return false;
        }

        SelectedTab = tab.Value;
        return true;
    }


    public async Task LoadCloudAsync(CancellationToken cancellationToken)
    {
        if (cloudSettings is null)
        {
            return;
        }

        try
        {
            var status = await cloudSettings.LoadAsync(cancellationToken);
            ApplyCloudSnapshot(status);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            Tencent.FailOperation();
            Aliyun.FailOperation();
            Volcengine.FailOperation();
        }
    }

    public async Task<bool> SaveTencentAsync(
        string appId,
        string secretId,
        string secretKey,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        if (!Tencent.TryBeginOperation("SettingsOperationSaving"))
        {
            return false;
        }

        try
        {
            await cloudSettings!.SaveTencentAsync(
                appId,
                secretId,
                secretKey,
                cancellationToken);
            var snapshot = await cloudSettings.LoadAsync(cancellationToken);
            ApplyCredentialPresentations(snapshot);
            Tencent.CompleteOperation(
                configured: true,
                ready: true,
                "SettingsSaveSucceeded");
            RefreshCloudSelection();
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Tencent.CancelOperation();
            throw;
        }
        catch
        {
            Tencent.FailOperation();
            return false;
        }
    }

    public async Task<bool> SaveAliyunAsync(
        string apiKey,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        if (!Aliyun.TryBeginOperation("SettingsOperationSaving"))
        {
            return false;
        }

        try
        {
            await cloudSettings!.SaveAliyunAsync(apiKey, cancellationToken);
            var snapshot = await cloudSettings.LoadAsync(cancellationToken);
            ApplyCredentialPresentations(snapshot);
            Aliyun.CompleteOperation(
                configured: true,
                ready: true,
                "SettingsSaveSucceeded");
            RefreshCloudSelection();
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Aliyun.CancelOperation();
            throw;
        }
        catch
        {
            Aliyun.FailOperation();
            return false;
        }
    }

    public async Task<bool> SaveVolcengineAsync(
        string appId,
        string accessToken,
        string secretKey,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        if (!Volcengine.TryBeginOperation("SettingsOperationSaving"))
        {
            return false;
        }

        try
        {
            await cloudSettings!.SaveVolcengineAsync(
                appId,
                accessToken,
                secretKey,
                cancellationToken);
            var snapshot = await cloudSettings.LoadAsync(cancellationToken);
            ApplyCredentialPresentations(snapshot);
            Volcengine.CompleteOperation(
                configured: true,
                ready: true,
                "SettingsSaveSucceeded");
            RefreshCloudSelection();
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Volcengine.CancelOperation();
            throw;
        }
        catch
        {
            Volcengine.FailOperation();
            return false;
        }
    }

    public async Task<bool> TestCloudAsync(
        AsrProviderId provider,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        var card = Card(provider);
        if (!card.TryBeginOperation("SettingsOperationTesting"))
        {
            return false;
        }

        try
        {
            var succeeded = await cloudSettings!.TestAsync(provider, cancellationToken);
            card.CompleteOperation(
                configured: card.IsConfigured || succeeded,
                ready: card.IsConfigured || succeeded,
                succeeded ? "SettingsConnectionSucceeded" : "SettingsConnectionFailed");
            RefreshCloudSelection();
            return succeeded;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            card.CancelOperation();
            throw;
        }
        catch
        {
            card.FailOperation();
            return false;
        }
    }

    public async Task<bool> DeleteCloudAsync(
        AsrProviderId provider,
        bool confirmed,
        CancellationToken cancellationToken)
    {
        if (!confirmed)
        {
            return false;
        }

        EnsureCloudAvailable();
        var card = Card(provider);
        if (!card.TryBeginOperation("SettingsOperationDeleting"))
        {
            return false;
        }

        try
        {
            await cloudSettings!.DeleteAsync(provider, cancellationToken);
            card.ApplyCredentialPresentations();
            card.SetSecretsVisible(false);
            card.CompleteOperation(
                configured: false,
                ready: false,
                "SettingsDeleteSucceeded");
            RefreshCloudSelection();
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            card.CancelOperation();
            throw;
        }
        catch
        {
            card.FailOperation();
            return false;
        }
    }

    public bool SelectCloud(AsrProviderId provider)
    {
        EnsureCloudAvailable();
        var card = Card(provider);
        if (!card.CanSelect)
        {
            return false;
        }

        try
        {
            cloudSettings!.SelectProvider(provider);
            RefreshCloudSelection();
            card.Apply(
                card.IsConfigured,
                card.IsReady,
                "SettingsCloudSelectSucceeded",
                selected: true);
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    public async Task<TencentAsrCredentials?> RevealTencentAsync(
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        return await cloudSettings!.RevealTencentAsync(cancellationToken)
            .ConfigureAwait(true);
    }

    public async Task<string?> RevealAliyunApiKeyAsync(
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        return await cloudSettings!.RevealAliyunApiKeyAsync(cancellationToken)
            .ConfigureAwait(true);
    }

    public async Task<VolcengineAsrCredentials?> RevealVolcengineAsync(
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        return await cloudSettings!.RevealVolcengineAsync(cancellationToken)
            .ConfigureAwait(true);
    }

    private void ApplyCloudSnapshot(CloudAsrConfigurationSnapshot snapshot)
    {
        ApplyCredentialPresentations(snapshot);
        Tencent.Apply(snapshot.TencentConfigured, ready: snapshot.TencentConfigured);
        Aliyun.Apply(snapshot.AliyunConfigured, ready: snapshot.AliyunConfigured);
        Volcengine.Apply(snapshot.VolcengineConfigured, ready: snapshot.VolcengineConfigured);
        RefreshCloudSelection();
        // Recover selection after restart: credentials are durable, but the
        // in-memory selected provider is not. Prefer an already-configured cloud
        // ASR so dictation is not left without a provider.
        if (ReadSelectedCloudProvider() is null
            && cloudSettings is not null)
        {
            AsrProviderId? fallback = snapshot.TencentConfigured
                ? AsrProviderId.TencentCloud
                : snapshot.AliyunConfigured
                    ? AsrProviderId.AliyunDashScope
                    : snapshot.VolcengineConfigured
                        ? AsrProviderId.Volcengine
                        : null;
            if (fallback is not null)
            {
                try
                {
                    cloudSettings.SelectProvider(fallback.Value);
                    RefreshCloudSelection();
                }
                catch (InvalidOperationException)
                {
                    // Leave unselected if state is not yet ready.
                }
            }
        }
    }

    private void RefreshCloudSelection()
    {
        var selected = ReadSelectedCloudProvider();
        Tencent.SetSelected(selected == AsrProviderId.TencentCloud);
        Aliyun.SetSelected(selected == AsrProviderId.AliyunDashScope);
        Volcengine.SetSelected(selected == AsrProviderId.Volcengine);
    }

    private AsrProviderId? ReadSelectedCloudProvider()
    {
        if (stateStore is null)
        {
            return null;
        }

        var settings = stateStore.Current.State.Settings;
        if (!settings.TryGetValue("asr.selected.provider", out var providerText)
            || !Enum.TryParse<AsrProviderId>(providerText, out var provider)
            || provider == AsrProviderId.Qwen)
        {
            return null;
        }

        return provider;
    }

    private void ApplyCredentialPresentations(CloudAsrConfigurationSnapshot snapshot)
    {
        Tencent.ApplyCredentialPresentations(
            snapshot.Tencent.AppId,
            snapshot.Tencent.SecretId,
            snapshot.Tencent.SecretKey);
        Aliyun.ApplyCredentialPresentations(snapshot.Aliyun.ApiKey);
        Volcengine.ApplyCredentialPresentations(
            snapshot.Volcengine.AppId,
            snapshot.Volcengine.AccessToken,
            snapshot.Volcengine.SecretKey);
    }

    private CloudProviderSettingsCardViewModel Card(AsrProviderId provider) => provider switch
    {
        AsrProviderId.TencentCloud => Tencent,
        AsrProviderId.AliyunDashScope => Aliyun,
        AsrProviderId.Volcengine => Volcengine,
        _ => throw new ArgumentOutOfRangeException(nameof(provider)),
    };

    private void EnsureCloudAvailable()
    {
        if (cloudSettings is null)
        {
            throw new InvalidOperationException("Cloud ASR settings are unavailable.");
        }
    }

    private static CloudProviderSettingsCardViewModel CloudCard(
        AsrProviderId provider,
        string headingKey,
        string descriptionKey) => new(
            provider,
            L10n.Localize(headingKey),
            L10n.Localize(descriptionKey));
}

public enum VoiceOutputMode
{
    QuickPaste,
    SimulatedTyping,
}

public sealed class VoiceSettingsPageViewModel : BindableObject
{
    private readonly VoxFlowStateStore stateStore;
    private string interactionModeId;
    private string selectedDeviceId;
    private string recognitionLanguageId;
    private bool middleMouseEnabled;
    private bool mutePlaybackDuringRecording;
    private bool feedbackSoundsEnabled = true;
    private bool voiceEnhancementEnabled = true;
    private VoiceOutputMode outputMode;
    private bool keepMicrophoneActive;
    private readonly InteractiveHotkeySettingsViewModel? interactiveHotkeys;
    private readonly bool agentHotkeyEnabled;
    private readonly ICaptureDeviceCatalog captureDevices;

    public VoiceSettingsPageViewModel(VoxFlowStateStore stateStore)
        : this(stateStore, interactiveHotkeys: null)
    {
    }

    public VoiceSettingsPageViewModel(
        VoxFlowStateStore stateStore,
        InteractiveHotkeySettingsViewModel? interactiveHotkeys)
        : this(
            stateStore,
            interactiveHotkeys,
            agentHotkeyEnabled: interactiveHotkeys is not null)
    {
    }

    internal VoiceSettingsPageViewModel(
        VoxFlowStateStore stateStore,
        InteractiveHotkeySettingsViewModel? interactiveHotkeys,
        bool agentHotkeyEnabled,
        ICaptureDeviceCatalog? captureDevices = null)
    {
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
        this.interactiveHotkeys = interactiveHotkeys;
        this.agentHotkeyEnabled = agentHotkeyEnabled;
        this.captureDevices = captureDevices ?? new WasapiCaptureDeviceCatalog();
        var settings = stateStore.Current.State.Settings;
        selectedDeviceId = Read(settings, "voice.deviceId", "default");
        recognitionLanguageId = Read(settings, "recognition.language", "Automatic");
        interactionModeId = Read(settings, "voice.interactionMode", "hybrid");
        middleMouseEnabled = ReadBool(settings, "voice.middleMouseEnabled", false);
        mutePlaybackDuringRecording = ReadBool(
            settings,
            "voice.mutePlaybackDuringRecording",
            false);
        feedbackSoundsEnabled = ReadBool(settings, "voice.feedbackSoundsEnabled", true);
        voiceEnhancementEnabled = ReadBool(settings, "voice.voiceEnhancementEnabled", true);
        outputMode = Read(settings, "voice.outputMode", "quickPaste") == "simulatedTyping"
            ? VoiceOutputMode.SimulatedTyping
            : VoiceOutputMode.QuickPaste;
        keepMicrophoneActive = ReadBool(settings, "voice.keepMicrophoneActive", false);
        Cards =
        [
            Card("input", "SettingsVoiceInputHeading", "SettingsVoiceInputDescription"),
            Card("shortcut", "SettingsVoiceShortcutHeading", "SettingsVoiceShortcutDescription"),
            Card("audio", "SettingsVoiceAudioHeading", "SettingsVoiceAudioDescription"),
            Card("output", "SettingsVoiceOutputHeading", "SettingsVoiceOutputDescription"),
            Card("runtime", "SettingsVoiceRuntimeHeading", "SettingsVoiceRuntimeDescription"),
        ];
        AvailableDevices = new ObservableCollection<SettingsChoiceViewModel>(
        [
            new("default", L10n.Localize("SettingsVoiceDefaultMicrophone")),
        ]);
        RefreshAvailableDevices();
        RecognitionLanguages =
        [
            new("auto", L10n.Localize("TrayLanguageAutomatic")),
            new("zh-CN", L10n.Localize("TrayLanguageChinese")),
            new("en-US", L10n.Localize("TrayLanguageEnglish")),
            new("ja-JP", L10n.Localize("TrayLanguageJapanese")),
            new("ko-KR", L10n.Localize("TrayLanguageKorean")),
        ];
        InteractionModes =
        [
            new("hybrid", L10n.Localize("SettingsVoiceModeHybrid")),
            new("hold", L10n.Localize("SettingsVoiceModeHold")),
            new("toggle", L10n.Localize("SettingsVoiceModeToggle")),
        ];
    }

    public string Heading => L10n.Localize("SettingsVoiceHeading");

    public string Subtitle => L10n.Localize("SettingsVoiceSubtitle");

    public IReadOnlyList<SettingsCardViewModel> Cards { get; }

    public ObservableCollection<SettingsChoiceViewModel> AvailableDevices { get; }

    public IReadOnlyList<SettingsChoiceViewModel> RecognitionLanguages { get; }

    public IReadOnlyList<SettingsChoiceViewModel> InteractionModes { get; }

    public string SelectedDeviceId
    {
        get => selectedDeviceId;
        set
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(value);
            var normalized = value.Trim();
            if (SetField(ref selectedDeviceId, normalized))
            {
                Publish("voice.deviceId", normalized);
            }
        }
    }

    public string RecognitionLanguageId
    {
        get => recognitionLanguageId switch
        {
            "Automatic" => "auto",
            "ChineseMandarin" => "zh-CN",
            "English" => "en-US",
            "Japanese" => "ja-JP",
            "Korean" => "ko-KR",
            _ => recognitionLanguageId,
        };
        set => SetRecognitionLanguage(value);
    }

    public InteractiveHotkeyRowViewModel? ScreenshotHotkey => interactiveHotkeys?.Screenshot;

    public InteractiveHotkeyRowViewModel? DictationHotkey => interactiveHotkeys?.Dictation;

    public bool HasScreenshotHotkey => ScreenshotHotkey is not null;

    public InteractiveHotkeyRowViewModel? AgentHotkey => agentHotkeyEnabled
        ? interactiveHotkeys?.Agent
        : null;

    public bool HasAgentHotkey => AgentHotkey is not null;

    public string InteractionModeId
    {
        get => interactionModeId;
        set => SetInteractionMode(value);
    }

    /// <summary>Mac segmented control: hold mode (includes hybrid as hold-primary).</summary>
    public bool IsHoldMode
    {
        get => interactionModeId is "hold" or "hybrid";
        set
        {
            if (value)
            {
                SetInteractionMode("hold");
            }
        }
    }

    public bool IsToggleMode
    {
        get => interactionModeId == "toggle";
        set
        {
            if (value)
            {
                SetInteractionMode("toggle");
            }
        }
    }

    public bool MiddleMouseEnabled
    {
        get => middleMouseEnabled;
        set
        {
            if (SetField(ref middleMouseEnabled, value))
            {
                Publish("voice.middleMouseEnabled", Bool(value));
            }
        }
    }

    public bool MutePlaybackDuringRecording
    {
        get => mutePlaybackDuringRecording;
        set
        {
            if (SetField(ref mutePlaybackDuringRecording, value))
            {
                Publish("voice.mutePlaybackDuringRecording", Bool(value));
            }
        }
    }

    public bool FeedbackSoundsEnabled
    {
        get => feedbackSoundsEnabled;
        set
        {
            if (SetField(ref feedbackSoundsEnabled, value))
            {
                Publish("voice.feedbackSoundsEnabled", Bool(value));
            }
        }
    }

    public bool VoiceEnhancementEnabled
    {
        get => voiceEnhancementEnabled;
        set
        {
            if (SetField(ref voiceEnhancementEnabled, value))
            {
                Publish("voice.voiceEnhancementEnabled", Bool(value));
            }
        }
    }

    public VoiceOutputMode OutputMode
    {
        get => outputMode;
        set
        {
            if (!Enum.IsDefined(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }

            if (SetField(ref outputMode, value))
            {
                OnPropertyChanged(nameof(IsQuickPaste));
                OnPropertyChanged(nameof(IsSimulatedTyping));
                Publish(
                    "voice.outputMode",
                    value == VoiceOutputMode.QuickPaste
                        ? "quickPaste"
                        : "simulatedTyping");
            }
        }
    }

    public bool KeepMicrophoneActive
    {
        get => keepMicrophoneActive;
        set
        {
            if (SetField(ref keepMicrophoneActive, value))
            {
                Publish("voice.keepMicrophoneActive", Bool(value));
            }
        }
    }

    public void SetInteractionMode(string modeId)
    {
        var normalized = modeId.Trim().ToLowerInvariant();
        if (normalized is not ("hybrid" or "hold" or "toggle"))
        {
            throw new ArgumentOutOfRangeException(nameof(modeId));
        }

        if (string.Equals(interactionModeId, normalized, StringComparison.Ordinal))
        {
            return;
        }

        interactionModeId = normalized;
        OnPropertyChanged(nameof(InteractionModeId));
        OnPropertyChanged(nameof(IsHoldMode));
        OnPropertyChanged(nameof(IsToggleMode));
        Publish("voice.interactionMode", normalized);
    }

    public void SetRecognitionLanguage(string languageId)
    {
        var normalized = languageId.Trim();
        var value = normalized switch
        {
            "auto" => RecognitionLanguage.Automatic.ToString(),
            "zh-CN" => RecognitionLanguage.ChineseMandarin.ToString(),
            "en-US" => RecognitionLanguage.English.ToString(),
            "ja-JP" => RecognitionLanguage.Japanese.ToString(),
            "ko-KR" => RecognitionLanguage.Korean.ToString(),
            _ => throw new ArgumentOutOfRangeException(nameof(languageId)),
        };
        if (string.Equals(recognitionLanguageId, value, StringComparison.Ordinal))
        {
            return;
        }

        recognitionLanguageId = value;
        OnPropertyChanged(nameof(RecognitionLanguageId));
        Publish("recognition.language", normalized);
    }

    public void SetOutputMode(string modeId)
    {
        OutputMode = modeId.Trim() switch
        {
            "quickPaste" => VoiceOutputMode.QuickPaste,
            "simulatedTyping" => VoiceOutputMode.SimulatedTyping,
            _ => throw new ArgumentOutOfRangeException(nameof(modeId)),
        };
    }

    public bool IsQuickPaste
    {
        get => OutputMode == VoiceOutputMode.QuickPaste;
        set
        {
            if (value)
            {
                OutputMode = VoiceOutputMode.QuickPaste;
            }
        }
    }

    public bool IsSimulatedTyping
    {
        get => OutputMode == VoiceOutputMode.SimulatedTyping;
        set
        {
            if (value)
            {
                OutputMode = VoiceOutputMode.SimulatedTyping;
            }
        }
    }

    public void ResetToDefaults()
    {
        SelectedDeviceId = "default";
        SetRecognitionLanguage("auto");
        SetInteractionMode("hybrid");
        MiddleMouseEnabled = false;
        MutePlaybackDuringRecording = false;
        FeedbackSoundsEnabled = true;
        VoiceEnhancementEnabled = true;
        OutputMode = VoiceOutputMode.QuickPaste;
        KeepMicrophoneActive = false;
    }

    /// <summary>
    /// Rebuilds the capture device list from WASAPI (or the injected catalog).
    /// Always keeps the synthetic "default" entry first.
    /// </summary>
    public void RefreshAvailableDevices()
    {
        var previous = selectedDeviceId;
        List<SettingsChoiceViewModel> next =
        [
            new("default", L10n.Localize("SettingsVoiceDefaultMicrophone")),
        ];

        try
        {
            foreach (var device in captureDevices.ListCaptureDevices())
            {
                if (string.IsNullOrWhiteSpace(device.Id))
                {
                    continue;
                }

                var label = device.Name;
                if (device.IsDefault)
                {
                    label += " (" + L10n.Localize("SettingsVoiceDeviceDefaultMarker") + ")";
                }

                if (!device.IsAvailable)
                {
                    label += " (" + L10n.Localize("SettingsVoiceDeviceUnavailableMarker") + ")";
                }

                next.Add(new SettingsChoiceViewModel(device.Id, label));
            }
        }
        catch
        {
            // Enumeration failures keep the system-default entry only.
        }

        AvailableDevices.Clear();
        foreach (var item in next)
        {
            AvailableDevices.Add(item);
        }

        if (!AvailableDevices.Any(item => string.Equals(item.Id, previous, StringComparison.Ordinal)))
        {
            SelectedDeviceId = "default";
        }
        else
        {
            // Re-assert selection so the ComboBox keeps the persisted id after refresh.
            selectedDeviceId = previous;
            OnPropertyChanged(nameof(SelectedDeviceId));
        }
    }

    private void Publish(string key, string value) => stateStore.Dispatch(
        new UpdateSettingsCommand(
            new Dictionary<string, string?> { [key] = value },
            StateChangeKind.Settings | StateChangeKind.Dictation));

    private static SettingsCardViewModel Card(
        string id,
        string headingKey,
        string descriptionKey) => new(
            id,
            L10n.Localize(headingKey),
            L10n.Localize(descriptionKey));

    private static string Read(
        IReadOnlyDictionary<string, string> values,
        string key,
        string fallback) => values.TryGetValue(key, out var value) ? value : fallback;

    private static bool ReadBool(
        IReadOnlyDictionary<string, string> values,
        string key,
        bool fallback) => values.TryGetValue(key, out var value)
            ? string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
            : fallback;

    private static string Bool(bool value) => value ? "true" : "false";
}

public sealed class TextSettingsPageViewModel : BindableObject
{
    private readonly ITextProcessingSettingsStore settingsStore;
    private readonly VoxFlowStateStore stateStore;
    private DeterministicTextProcessingSettings settings =
        DeterministicTextProcessingSettings.Default;
    private bool isBusy;
    private string? feedbackMessage;

    public TextSettingsPageViewModel(
        ITextProcessingSettingsStore settingsStore,
        VoxFlowStateStore stateStore)
    {
        this.settingsStore = settingsStore
            ?? throw new ArgumentNullException(nameof(settingsStore));
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
    }

    public string Heading => L10n.Localize("SettingsTextHeading");

    public string Subtitle => L10n.Localize("SettingsTextSubtitle");

    public bool IsBusy
    {
        get => isBusy;
        private set
        {
            if (SetField(ref isBusy, value))
            {
                OnPropertyChanged(nameof(CanSave));
            }
        }
    }

    public bool CanSave => !IsBusy;

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public bool Enabled
    {
        get => settings.Enabled;
        set => SetSettings(settings with { Enabled = value });
    }

    public bool SmartNumberRecognition
    {
        get => settings.SmartNumberRecognition;
        set => SetSettings(settings with { SmartNumberRecognition = value });
    }

    public bool PunctuationOptimization
    {
        get => settings.PunctuationOptimization;
        set => SetSettings(settings with { PunctuationOptimization = value });
    }

    public bool LongSentenceBreaking
    {
        get => settings.LongSentenceBreaking;
        set => SetSettings(settings with { LongSentenceBreaking = value });
    }

    public bool FillerWordFiltering
    {
        get => settings.FillerWordFiltering;
        set => SetSettings(settings with { FillerWordFiltering = value });
    }

    public bool CjkLatinSpacing
    {
        get => settings.CjkLatinSpacing;
        set => SetSettings(settings with { CjkLatinSpacing = value });
    }

    public bool AutoCapitalization
    {
        get => settings.AutoCapitalization;
        set => SetSettings(settings with { AutoCapitalization = value });
    }

    public int LongSentenceWordThreshold
    {
        get => settings.LongSentenceWordThreshold;
        set => SetSettings(settings with { LongSentenceWordThreshold = value });
    }

    public int LongSentenceCjkThreshold
    {
        get => settings.LongSentenceCjkThreshold;
        set => SetSettings(settings with { LongSentenceCjkThreshold = value });
    }

    public int PunctuationCjkThreshold
    {
        get => settings.PunctuationCjkThreshold;
        set => SetSettings(settings with { PunctuationCjkThreshold = value });
    }

    public int PunctuationWordThreshold
    {
        get => settings.PunctuationWordThreshold;
        set => SetSettings(settings with { PunctuationWordThreshold = value });
    }

    public async Task LoadAsync(CancellationToken cancellationToken)
    {
        settings = await settingsStore.LoadAsync(cancellationToken).ConfigureAwait(false);
        RaiseAll();
    }

    public async Task<bool> SaveAsync(CancellationToken cancellationToken)
    {
        IsBusy = true;
        FeedbackMessage = L10n.Localize("SettingsOperationSaving");
        try
        {
            await settingsStore.SaveAsync(settings, cancellationToken).ConfigureAwait(true);
            stateStore.Dispatch(new UpdateSettingsCommand(
                new Dictionary<string, string?>
                {
                    ["text.enabled"] = Bool(settings.Enabled),
                    ["text.smartNumberRecognition"] = Bool(settings.SmartNumberRecognition),
                    ["text.punctuationOptimization"] = Bool(settings.PunctuationOptimization),
                    ["text.longSentenceBreaking"] = Bool(settings.LongSentenceBreaking),
                    ["text.fillerWordFiltering"] = Bool(settings.FillerWordFiltering),
                    ["text.cjkLatinSpacing"] = Bool(settings.CjkLatinSpacing),
                    ["text.autoCapitalization"] = Bool(settings.AutoCapitalization),
                    ["text.longSentenceWordThreshold"] = settings.LongSentenceWordThreshold.ToString(CultureInfo.InvariantCulture),
                    ["text.longSentenceCjkThreshold"] = settings.LongSentenceCjkThreshold.ToString(CultureInfo.InvariantCulture),
                    ["text.punctuationCjkThreshold"] = settings.PunctuationCjkThreshold.ToString(CultureInfo.InvariantCulture),
                    ["text.punctuationWordThreshold"] = settings.PunctuationWordThreshold.ToString(CultureInfo.InvariantCulture),
                }));
            FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            FeedbackMessage = null;
            throw;
        }
        catch
        {
            FeedbackMessage = L10n.Localize("SettingsOperationFailed");
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void SetSettings(DeterministicTextProcessingSettings value)
    {
        if (settings == value)
        {
            return;
        }

        settings = value;
        RaiseAll();
    }

    private void RaiseAll()
    {
        OnPropertyChanged(nameof(Enabled));
        OnPropertyChanged(nameof(SmartNumberRecognition));
        OnPropertyChanged(nameof(PunctuationOptimization));
        OnPropertyChanged(nameof(LongSentenceBreaking));
        OnPropertyChanged(nameof(FillerWordFiltering));
        OnPropertyChanged(nameof(CjkLatinSpacing));
        OnPropertyChanged(nameof(AutoCapitalization));
        OnPropertyChanged(nameof(LongSentenceWordThreshold));
        OnPropertyChanged(nameof(LongSentenceCjkThreshold));
        OnPropertyChanged(nameof(PunctuationCjkThreshold));
        OnPropertyChanged(nameof(PunctuationWordThreshold));
    }

    private static string Bool(bool value) => value ? "true" : "false";
}

public sealed class TranslationSettingsPageViewModel
{
    public TranslationSettingsPageViewModel(
        InteractiveHotkeySettingsViewModel interactiveHotkeys)
    {
        ArgumentNullException.ThrowIfNull(interactiveHotkeys);
        HotkeyRows = interactiveHotkeys.AssistantRows;
    }

    public string Heading => L10n.Localize("SettingsSelectionAssistantHeading");

    public string Subtitle => L10n.Localize("SettingsSelectionAssistantSubtitle");

    public IReadOnlyList<InteractiveHotkeyRowViewModel> HotkeyRows { get; }
}

public sealed class ScreenshotSettingsPageViewModel : BindableObject
{
    private readonly IScreenshotAutomationSettingsStore settingsStore;
    private readonly Action<bool>? settingChanged;
    private bool clipboardOcrEnabled;

    public ScreenshotSettingsPageViewModel(
        InteractiveHotkeySettingsViewModel interactiveHotkeys,
        IScreenshotAutomationSettingsStore settingsStore,
        Action<bool>? settingChanged = null)
    {
        ArgumentNullException.ThrowIfNull(interactiveHotkeys);
        this.settingsStore = settingsStore ?? throw new ArgumentNullException(nameof(settingsStore));
        this.settingChanged = settingChanged;
        ScreenshotHotkey = interactiveHotkeys.Screenshot;
        ClipboardImageOcrHotkey = interactiveHotkeys.ClipboardImageOcr;
        clipboardOcrEnabled = ScreenshotAutomationSettings.Default.ClipboardImageOcrEnabled;
    }

    public string Heading => L10n.Localize("SettingsScreenshotHeading");

    public string Subtitle => L10n.Localize("SettingsScreenshotSubtitle");

    public InteractiveHotkeyRowViewModel ScreenshotHotkey { get; }

    public InteractiveHotkeyRowViewModel ClipboardImageOcrHotkey { get; }

    public async Task LoadAsync(CancellationToken cancellationToken)
    {
        var settings = await settingsStore.LoadAsync(cancellationToken).ConfigureAwait(true);
        clipboardOcrEnabled = settings.ClipboardImageOcrEnabled;
        OnPropertyChanged(nameof(ClipboardOcrEnabled));
        settingChanged?.Invoke(clipboardOcrEnabled);
    }

    public bool ClipboardOcrEnabled
    {
        get => clipboardOcrEnabled;
        set
        {
            if (SetField(ref clipboardOcrEnabled, value))
            {
                settingChanged?.Invoke(value);
                _ = settingsStore.SaveAsync(
                    new ScreenshotAutomationSettings(
                        ScreenshotAutomationSettings.CurrentSchemaVersion,
                        value),
                    CancellationToken.None);
            }
        }
    }
}

public sealed class SettingsPageViewModel : BindableObject
{
    private readonly GeneralSettingsPageViewModel general;
    private readonly ModelsSettingsPageViewModel models;
    private readonly VoiceSettingsPageViewModel voice;
    private readonly TranslationSettingsPageViewModel? translation;
    private readonly ScreenshotSettingsPageViewModel? screenshot;
    private readonly TextSettingsPageViewModel text;
    private readonly InteractiveHotkeySettingsViewModel? interactiveHotkeys;
    private SettingsRoute currentRoute;

    public SettingsPageViewModel(string heading, string subtitle)
        : this(
            heading,
            subtitle,
            new VoxFlowStateStore(),
            new MemoryTextProcessingSettingsStore())
    {
    }

    public SettingsPageViewModel(
        string heading,
        string subtitle,
        VoxFlowStateStore stateStore,
        ITextProcessingSettingsStore textSettingsStore)
        : this(heading, subtitle, stateStore, textSettingsStore, null)
    {
    }

    public SettingsPageViewModel(
        string heading,
        string subtitle,
        VoxFlowStateStore stateStore,
        ITextProcessingSettingsStore textSettingsStore,
        OpenAiSettingsService? openAiSettingsService)
        : this(
            heading,
            subtitle,
            stateStore,
            textSettingsStore,
            openAiSettingsService,
            null)
    {
    }

    public SettingsPageViewModel(
        string heading,
        string subtitle,
        VoxFlowStateStore stateStore,
        ITextProcessingSettingsStore textSettingsStore,
        OpenAiSettingsService? openAiSettingsService,
        CloudAsrSettingsCoordinator? cloudAsrSettings)
        : this(
            heading,
            subtitle,
            stateStore,
            textSettingsStore,
            openAiSettingsService,
            cloudAsrSettings,
            null)
    {
    }

    public SettingsPageViewModel(
        string heading,
        string subtitle,
        VoxFlowStateStore stateStore,
        ITextProcessingSettingsStore textSettingsStore,
        OpenAiSettingsService? openAiSettingsService,
        CloudAsrSettingsCoordinator? cloudAsrSettings,
        ILlmProviderManagementService? llmProviderManagement)
        : this(
            heading,
            subtitle,
            stateStore,
            textSettingsStore,
            openAiSettingsService,
            cloudAsrSettings,
            llmProviderManagement,
            interactiveHotkeySettingsStore: null,
            interactiveFeatureFlags: WindowsInteractiveFeatureFlags.Disabled)
    {
    }

    public SettingsPageViewModel(
        string heading,
        string subtitle,
        VoxFlowStateStore stateStore,
        ITextProcessingSettingsStore textSettingsStore,
        OpenAiSettingsService? openAiSettingsService,
        CloudAsrSettingsCoordinator? cloudAsrSettings,
        ILlmProviderManagementService? llmProviderManagement,
        IInteractiveHotkeySettingsStore? interactiveHotkeySettingsStore,
        WindowsInteractiveFeatureFlags interactiveFeatureFlags,
        QwenModelCatalog? qwenCatalog = null,
        QwenModelEntryPointProjection? qwenProjection = null,
        IQwenModelOperations? qwenOperations = null,
        BuiltinAgentRuntimeStatus? builtinAgentRuntime = null,
        Action<InteractiveHotkeyBindingSet>? interactiveHotkeyBindingsChanged = null,
        GeneralSettingsActions? generalSettingsActions = null,
        IScreenshotAutomationSettingsStore? screenshotAutomationSettingsStore = null,
        Action<bool>? clipboardOcrSettingChanged = null
#if DEBUG
        , Func<
            string,
            DebugTranscriptInjectionMode,
            CancellationToken,
            Task<DebugTranscriptInjectionResult>>? debugTranscriptInjection = null
#endif
        )
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(heading);
        ArgumentException.ThrowIfNullOrWhiteSpace(subtitle);
        Heading = heading;
        Subtitle = subtitle;
        var coordinator = new SettingsStateCoordinator(stateStore);
        var openAi = new OpenAiSettingsCardViewModel(
            coordinator,
            openAiSettingsService);
        models = new ModelsSettingsPageViewModel(
            openAi,
            cloudAsrSettings,
            llmProviderManagement,
            qwenCatalog,
            qwenProjection,
            qwenOperations,
            builtinAgentRuntime,
            stateStore);
        ArgumentNullException.ThrowIfNull(interactiveFeatureFlags);
        if (interactiveHotkeySettingsStore is not null)
        {
            interactiveHotkeys = new InteractiveHotkeySettingsViewModel(
                interactiveHotkeySettingsStore,
                interactiveHotkeyBindingsChanged);
        }
        else if (interactiveFeatureFlags.AnyEnabled)
        {
            throw new ArgumentNullException(nameof(interactiveHotkeySettingsStore));
        }
        voice = new VoiceSettingsPageViewModel(
            stateStore,
            interactiveHotkeys,
            interactiveFeatureFlags.BuiltinAgentEnabled);
        general = new GeneralSettingsPageViewModel(
            L10n.Localize("SettingsGeneralHeading"),
            L10n.Localize("SettingsGeneralSubtitle"),
            generalSettingsActions,
            async cancellationToken =>
            {
                voice.ResetToDefaults();
                if (interactiveHotkeys is not null)
                {
                    await interactiveHotkeys.ResetAllToDefaultsAsync(cancellationToken);
                }
            }
#if DEBUG
            , debugTranscriptInjection
#endif
            );
        translation = interactiveFeatureFlags.SelectionTransformEnabled
            ? new TranslationSettingsPageViewModel(
                interactiveHotkeys
                    ?? throw new InvalidOperationException(
                        "Selection settings require interactive hotkeys."))
            : null;
        screenshot = interactiveHotkeys is null
            ? null
            : new ScreenshotSettingsPageViewModel(
                interactiveHotkeys,
                screenshotAutomationSettingsStore ?? new MemoryScreenshotAutomationSettingsStore(),
                clipboardOcrSettingChanged);
        // LLM/OpenAI credentials live only under Models → LLM (mac parity).
        text = new TextSettingsPageViewModel(textSettingsStore, stateStore);
        // Match mac settings sidebar order: General → Models → Voice → Text →
        // Screenshot → Selection assistant.
        List<SettingsNavigationItemViewModel> navigationItems =
        [
            Item("general", SettingsRoute.General, "SettingsNavigationGeneral", "\uE713"),
            Item("models", SettingsRoute.Models, "SettingsNavigationModels", "\uE950"),
            Item("voice", SettingsRoute.Voice, "SettingsNavigationVoice", "\uE720"),
            Item("text", SettingsRoute.Text, "SettingsNavigationText", "\uE8D2"),
        ];
        if (screenshot is not null)
        {
            navigationItems.Add(Item(
                "screenshot",
                SettingsRoute.Screenshot,
                "SettingsNavigationScreenshot",
                "\uE722"));
        }
        if (translation is not null)
        {
            navigationItems.Add(Item(
                "selection-assistant",
                SettingsRoute.Translation,
                "SettingsNavigationSelectionAssistant",
                "\uE8C1"));
        }
        NavigationItems = navigationItems;
    }

    public string Heading { get; }

    public string Subtitle { get; }

    public IReadOnlyList<SettingsNavigationItemViewModel> NavigationItems { get; }

    public SettingsRoute CurrentRoute
    {
        get => currentRoute;
        set
        {
            if (!Enum.IsDefined(value))
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }

            if (SetField(ref currentRoute, value))
            {
                OnPropertyChanged(nameof(CurrentPage));
            }
        }
    }

    public object CurrentPage => CurrentRoute switch
    {
        SettingsRoute.General => general,
        SettingsRoute.Models => models,
        SettingsRoute.Voice => voice,
        SettingsRoute.Translation when translation is not null => translation,
        SettingsRoute.Screenshot when screenshot is not null => screenshot,
        SettingsRoute.Text => text,
        _ => throw new InvalidOperationException("The settings route is unavailable."),
    };

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await text.LoadAsync(cancellationToken).ConfigureAwait(false);
        await models.OpenAi.LoadAsync(cancellationToken).ConfigureAwait(false);
        await models.LoadCloudAsync(cancellationToken).ConfigureAwait(false);
        if (models.LlmProviders is not null)
        {
            await models.LlmProviders.LoadAsync(cancellationToken).ConfigureAwait(false);
        }
        if (interactiveHotkeys is not null)
        {
            await interactiveHotkeys.InitializeAsync(cancellationToken).ConfigureAwait(false);
        }
        if (screenshot is not null)
        {
            await screenshot.LoadAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    public bool TryNavigate(string routeId)
    {
        var route = routeId.Trim().ToLowerInvariant() switch
        {
            "general" => SettingsRoute.General,
            "models" => SettingsRoute.Models,
            "voice" => SettingsRoute.Voice,
            "translation" or "selection-assistant" when translation is not null => SettingsRoute.Translation,
            "screenshot" when screenshot is not null => SettingsRoute.Screenshot,
            "text" => SettingsRoute.Text,
            _ => (SettingsRoute?)null,
        };
        if (route is null)
        {
            return false;
        }

        CurrentRoute = route.Value;
        return true;
    }

    private static SettingsNavigationItemViewModel Item(
        string id,
        SettingsRoute route,
        string labelKey,
        string glyph) => new(id, route, L10n.Localize(labelKey), glyph);

    private sealed class MemoryTextProcessingSettingsStore : ITextProcessingSettingsStore
    {
        private DeterministicTextProcessingSettings settings =
            DeterministicTextProcessingSettings.Default;

        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(settings);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings value,
            CancellationToken cancellationToken)
        {
            settings = value;
            return ValueTask.CompletedTask;
        }
    }

}

internal sealed class MemoryScreenshotAutomationSettingsStore
    : IScreenshotAutomationSettingsStore
{
    private ScreenshotAutomationSettings settings = ScreenshotAutomationSettings.Default;

    public ValueTask<ScreenshotAutomationSettings> LoadAsync(
        CancellationToken cancellationToken) => ValueTask.FromResult(settings);

    public ValueTask SaveAsync(
        ScreenshotAutomationSettings value,
        CancellationToken cancellationToken)
    {
        settings = value;
        return ValueTask.CompletedTask;
    }
}

public abstract class BindableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetField<T>(
        ref T field,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
