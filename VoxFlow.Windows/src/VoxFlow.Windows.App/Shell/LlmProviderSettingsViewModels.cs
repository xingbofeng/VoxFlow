using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.App.Shell;

public sealed record LlmProviderTemplateOptionViewModel(
    string Id,
    string DisplayName,
    string BaseUrl,
    Uri? ApiKeyUri,
    int TimeoutSeconds,
    bool RequiresApiKey,
    bool IsCustom);

public sealed record LlmProviderCardViewModel(
    string Id,
    string DisplayName,
    string BaseUrl,
    string Model,
    bool Enabled,
    bool IsDefault,
    LlmProviderHealthStatus HealthStatus,
    string HealthStatusText,
    string? HealthMessage,
    long? HealthLatencyMs,
    LlmAgentCapabilityStatus AgentCapabilityStatus,
    string AgentCapabilityStatusText,
    string? AgentCapabilityMessage,
    string ApiKeyPresentation,
    bool IsConnectionTesting,
    bool IsAgentTesting,
    string? ActionFeedbackMessage)
{
    public string EnabledStatusText => L10n.Localize(
        Enabled ? "LlmProviderStatusEnabled" : "LlmProviderStatusDisabled");

    public bool CanSetDefault => Enabled && !IsDefault && !IsBusy;

    public bool IsBusy => IsConnectionTesting || IsAgentTesting;

    public bool CanRunActions => !IsBusy;

    public string DisplayedHealthStatusText => IsConnectionTesting
        ? L10n.Localize("LlmProviderHealthTesting")
        : HealthStatusText;

    public string DisplayedAgentCapabilityStatusText => IsAgentTesting
        ? L10n.Localize("LlmProviderHealthTesting")
        : AgentCapabilityStatusText;
}

public sealed class LlmProviderEditorViewModel : BindableObject
{
    private string templateId;
    private string displayName;
    private string baseUrl;
    private string model;
    private double temperature;
    private int timeoutSeconds;
    private bool enabled;
    private bool isDefault;
    private bool requiresApiKey;
    private Uri? apiKeyUri;
    private IReadOnlyList<string> modelOptions;
    private bool isApiKeyVisible;
    private string? revealedApiKey;
    private string draftApiKey = string.Empty;

    internal LlmProviderEditorViewModel(
        string? providerId,
        string templateId,
        string displayName,
        string baseUrl,
        string model,
        double temperature,
        int timeoutSeconds,
        bool enabled,
        bool isDefault,
        bool requiresApiKey,
        Uri? apiKeyUri,
        bool retainExistingCredential,
        string apiKeyPresentation,
        IReadOnlyList<string>? modelOptions = null)
    {
        ProviderId = providerId;
        this.templateId = templateId;
        this.displayName = displayName;
        this.baseUrl = baseUrl;
        this.model = model;
        this.temperature = temperature;
        this.timeoutSeconds = timeoutSeconds;
        this.enabled = enabled;
        this.isDefault = isDefault;
        this.requiresApiKey = requiresApiKey;
        this.apiKeyUri = apiKeyUri;
        RetainExistingCredential = retainExistingCredential;
        ApiKeyPresentation = apiKeyPresentation;
        this.modelOptions = modelOptions ?? Array.Empty<string>();
    }

    public string? ProviderId { get; }

    public bool IsNew => ProviderId is null;

    public string Title => L10n.Localize(
        IsNew ? "LlmProviderEditorAddTitle" : "LlmProviderEditorEditTitle");

    /// <summary>Compact template badge shown next to the name field (mac sheet).</summary>
    public string TemplateBadgeLabel =>
        string.Equals(TemplateId, LlmProviderTemplateCatalog.CustomTemplateId, StringComparison.Ordinal)
            ? L10n.Localize("LlmProviderCustomTemplate")
            : DisplayName;

    public string TemplateId
    {
        get => templateId;
        internal set
        {
            if (SetField(ref templateId, value))
            {
                OnPropertyChanged(nameof(TemplateBadgeLabel));
            }
        }
    }

    public string DisplayName
    {
        get => displayName;
        set
        {
            if (SetField(ref displayName, value))
            {
                OnPropertyChanged(nameof(TemplateBadgeLabel));
            }
        }
    }

    public string BaseUrl
    {
        get => baseUrl;
        set
        {
            if (SetField(ref baseUrl, value))
            {
                UpdateCustomCredentialRequirement();
            }
        }
    }

    public string Model
    {
        get => model;
        set => SetField(ref model, value);
    }

    public double Temperature
    {
        get => temperature;
        set => SetField(ref temperature, value);
    }

    public int TimeoutSeconds
    {
        get => timeoutSeconds;
        set => SetField(ref timeoutSeconds, value);
    }

    public bool Enabled
    {
        get => enabled;
        set
        {
            if (SetField(ref enabled, value) && !value && IsDefault)
            {
                IsDefault = false;
            }
        }
    }

    public bool IsDefault
    {
        get => isDefault;
        set
        {
            if (SetField(ref isDefault, value) && value && !Enabled)
            {
                Enabled = true;
            }
        }
    }

    public bool RequiresApiKey
    {
        get => requiresApiKey;
        private set => SetField(ref requiresApiKey, value);
    }

    public bool RetainExistingCredential { get; }

    public Uri? ApiKeyUri
    {
        get => apiKeyUri;
        private set
        {
            if (SetField(ref apiKeyUri, value))
            {
                OnPropertyChanged(nameof(HasApiKeyHelp));
            }
        }
    }

    public bool HasApiKeyHelp => ApiKeyUri is not null;

    public string ApiKeyPresentation { get; }

    public IReadOnlyList<string> ModelOptions
    {
        get => modelOptions;
        internal set => SetField(ref modelOptions, value);
    }

    public bool CanUseSavedCredential => ProviderId is not null
        && RetainExistingCredential;

    public bool CanRefreshModels => ProviderId is not null;

    public bool IsApiKeyVisible
    {
        get => isApiKeyVisible;
        set
        {
            if (SetField(ref isApiKeyVisible, value))
            {
                OnPropertyChanged(nameof(ApiKeyVisibilityGlyph));
                OnPropertyChanged(nameof(ApiKeyVisibilityTooltip));
            }
        }
    }

    public string? RevealedApiKey
    {
        get => revealedApiKey;
        set => SetField(ref revealedApiKey, value);
    }

    /// <summary>
    /// Working API-key buffer for the modal (password + eye reveal share this).
    /// Never logged; ToString redacts it.
    /// </summary>
    public string DraftApiKey
    {
        get => draftApiKey;
        set => SetField(ref draftApiKey, value ?? string.Empty);
    }

    /// <summary>Segoe Fluent Icons eye / eye-off glyph for the API-key toggle.</summary>
    public string ApiKeyVisibilityGlyph => IsApiKeyVisible
        ? "\uED1A" // Hide
        : "\uE7B3"; // Show

    public string ApiKeyVisibilityTooltip => L10n.Localize(
        IsApiKeyVisible ? "LlmProviderHideApiKey" : "LlmProviderRevealApiKey");

    public override string ToString() =>
        $"LlmProviderEditorViewModel {{ ProviderId = {ProviderId}, TemplateId = {TemplateId}, DisplayName = {DisplayName}, ApiKey = [REDACTED] }}";

    /// <summary>
    /// Adds the currently typed model id to the picker options (mac “添加模型”).
    /// </summary>
    public void AddCurrentModelToOptions()
    {
        var candidate = Model?.Trim() ?? string.Empty;
        if (candidate.Length == 0)
        {
            return;
        }

        if (ModelOptions.Any(option =>
                string.Equals(option, candidate, StringComparison.Ordinal)))
        {
            return;
        }

        ModelOptions = ModelOptions.Append(candidate).ToArray();
    }

    internal void ApplyTemplate(LlmProviderTemplate template)
    {
        ArgumentNullException.ThrowIfNull(template);
        TemplateId = template.Id;
        DisplayName = template.DisplayName;
        BaseUrl = template.BaseUrl;
        Model = template.DefaultModel;
        TimeoutSeconds = template.TimeoutSeconds;
        RequiresApiKey = template.RequiresApiKey;
        ApiKeyUri = template.ApiKeyUri;
        ModelOptions = Array.Empty<string>();
        IsApiKeyVisible = false;
        RevealedApiKey = null;
        DraftApiKey = string.Empty;
    }

    private void UpdateCustomCredentialRequirement()
    {
        if (!string.Equals(
                TemplateId,
                LlmProviderTemplateCatalog.CustomTemplateId,
                StringComparison.Ordinal))
        {
            return;
        }

        RequiresApiKey = !Uri.TryCreate(BaseUrl.Trim(), UriKind.Absolute, out var endpoint)
            || !endpoint.IsLoopback;
    }
}

public sealed class LlmProviderSettingsViewModel : BindableObject
{
    private readonly ILlmProviderManagementService service;
    private IReadOnlyList<LlmProviderCardViewModel> providers =
        Array.Empty<LlmProviderCardViewModel>();
    private LlmProviderEditorViewModel? editor;
    private bool isBusy;
    private string? feedbackMessage;
    private readonly Dictionary<string, string> credentialPresentations =
        new(StringComparer.Ordinal);
    private readonly Dictionary<string, ProviderActionState> actionStates =
        new(StringComparer.Ordinal);

    public LlmProviderSettingsViewModel(ILlmProviderManagementService service)
    {
        this.service = service ?? throw new ArgumentNullException(nameof(service));
        TemplateOptions = LlmProviderTemplateCatalog.Options
            .Select(template => new LlmProviderTemplateOptionViewModel(
                template.Id,
                template.IsCustom
                    ? L10n.Localize("LlmProviderCustomTemplate")
                    : template.DisplayName,
                template.BaseUrl,
                template.ApiKeyUri,
                template.TimeoutSeconds,
                template.RequiresApiKey,
                template.IsCustom))
            .ToArray();
    }

    public IReadOnlyList<LlmProviderTemplateOptionViewModel> TemplateOptions { get; }

    public IReadOnlyList<LlmProviderCardViewModel> Providers
    {
        get => providers;
        private set => SetField(ref providers, value);
    }

    public LlmProviderEditorViewModel? Editor
    {
        get => editor;
        private set
        {
            if (SetField(ref editor, value))
            {
                OnPropertyChanged(nameof(IsEditing));
            }
        }
    }

    public bool IsEditing => Editor is not null;

    public bool IsBusy
    {
        get => isBusy;
        private set => SetField(ref isBusy, value);
    }

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public async Task LoadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        foreach (var provider in service.List())
        {
            try
            {
                var presentation = await service.GetCredentialPresentationAsync(
                    provider.Id,
                    cancellationToken);
                credentialPresentations[provider.Id] = CredentialText(presentation);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                credentialPresentations[provider.Id] =
                    L10n.Localize("SettingsCredentialNotConfigured");
            }
        }
        RefreshProviders();
    }

    public void BeginAdd(string templateId)
    {
        var template = LlmProviderTemplateCatalog.Find(templateId)
            ?? throw new ArgumentException(
                "The selected provider template does not exist.",
                nameof(templateId));
        Editor = new LlmProviderEditorViewModel(
            providerId: null,
            template.Id,
            template.DisplayName,
            template.BaseUrl,
            template.DefaultModel,
            temperature: 0.2,
            template.TimeoutSeconds,
            enabled: true,
            isDefault: Providers.Count == 0,
            template.RequiresApiKey,
            template.ApiKeyUri,
            retainExistingCredential: false,
            L10n.Localize("SettingsCredentialNotConfigured"));
        FeedbackMessage = null;
    }

    public void ApplyTemplate(string templateId)
    {
        if (Editor is null)
        {
            BeginAdd(templateId);
            return;
        }

        var template = LlmProviderTemplateCatalog.Find(templateId)
            ?? throw new ArgumentException(
                "The selected provider template does not exist.",
                nameof(templateId));
        Editor.ApplyTemplate(template);
    }

    public async Task BeginEditAsync(
        string providerId,
        CancellationToken cancellationToken)
    {
        var provider = FindProvider(providerId);
        var presentation = await service.GetCredentialPresentationAsync(
            providerId,
            cancellationToken);
        var template = provider.BaseUri is null
            ? null
            : LlmProviderTemplateCatalog.Match(provider.BaseUri);
        Editor = new LlmProviderEditorViewModel(
            provider.Id,
            template?.Id ?? LlmProviderTemplateCatalog.CustomTemplateId,
            provider.DisplayName,
            provider.BaseUri?.AbsoluteUri.TrimEnd('/') ?? string.Empty,
            provider.DefaultModel ?? string.Empty,
            provider.Temperature,
            provider.TimeoutSeconds,
            provider.Enabled,
            provider.IsDefault,
            template?.RequiresApiKey ?? provider.BaseUri is not { IsLoopback: true },
            template?.ApiKeyUri,
            retainExistingCredential: presentation.Availability
                == CredentialAvailability.Available,
            presentation.Mask);
        // mac parity: edit opens with a masked key; reveal is explicit.
        Editor.IsApiKeyVisible = false;
        Editor.RevealedApiKey = null;
        Editor.DraftApiKey = string.Empty;
        FeedbackMessage = null;
    }

    public void CancelEditor()
    {
        if (Editor is not null)
        {
            Editor.IsApiKeyVisible = false;
            Editor.RevealedApiKey = null;
            Editor.DraftApiKey = string.Empty;
        }

        Editor = null;
        FeedbackMessage = null;
    }

    public void ReportUiFailure() =>
        FeedbackMessage = L10n.Localize("LlmProviderActionFailed");

    public async Task SaveEditorAsync(
        string? apiKey,
        CancellationToken cancellationToken)
    {
        var current = Editor
            ?? throw new InvalidOperationException("No provider is being edited.");
        await RunBusyAsync(async () =>
        {
            var draft = new LlmProviderDraft(
                current.ProviderId,
                current.TemplateId,
                current.DisplayName,
                current.BaseUrl,
                current.Model,
                current.Temperature,
                current.TimeoutSeconds,
                current.Enabled,
                current.IsDefault);
            var saved = await service.SaveAsync(
                    draft,
                    string.IsNullOrWhiteSpace(apiKey) ? null : apiKey,
                    current.RetainExistingCredential
                        && string.IsNullOrWhiteSpace(apiKey),
                    cancellationToken);
            await RefreshCredentialPresentationAsync(
                saved.Id,
                cancellationToken);
            Editor = null;
            RefreshProviders();
            FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
        });
    }

    public async Task RefreshModelsAsync(CancellationToken cancellationToken)
    {
        var current = Editor
            ?? throw new InvalidOperationException("No provider is being edited.");
        if (current.ProviderId is null)
        {
            throw new InvalidOperationException(
                "Save the provider before refreshing its model list.");
        }

        await RunBusyAsync(async () =>
        {
            var result = await service.DiscoverModelsAsync(
                    current.ProviderId,
                    cancellationToken);
            current.ModelOptions = result.Models
                .Select(model => model.Id)
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            FeedbackMessage = result.SafeMessage;
        });
    }

    public async Task RevealApiKeyAsync(CancellationToken cancellationToken)
    {
        var current = Editor
            ?? throw new InvalidOperationException("No provider is being edited.");
        if (current.ProviderId is null)
        {
            return;
        }

        await RunBusyAsync(async () =>
        {
            current.RevealedApiKey = await service.RevealApiKeyAsync(
                    current.ProviderId,
                    cancellationToken);
            current.IsApiKeyVisible = current.RevealedApiKey is not null;
            if (current.RevealedApiKey is not null && string.IsNullOrEmpty(current.DraftApiKey))
            {
                current.DraftApiKey = current.RevealedApiKey;
            }
        });
    }

    public bool SetDefault(string providerId)
    {
        try
        {
            var changed = service.SetDefault(providerId);
            RefreshProviders();
            FeedbackMessage = L10n.Localize(
                changed ? "SettingsSaveSucceeded" : "LlmProviderActionFailed");
            return changed;
        }
        catch
        {
            FeedbackMessage = L10n.Localize("LlmProviderActionFailed");
            return false;
        }
    }

    public bool SetEnabled(string providerId, bool enabled)
    {
        try
        {
            var changed = service.SetEnabled(providerId, enabled);
            RefreshProviders();
            FeedbackMessage = L10n.Localize(
                changed ? "SettingsSaveSucceeded" : "LlmProviderActionFailed");
            return changed;
        }
        catch
        {
            FeedbackMessage = L10n.Localize("LlmProviderActionFailed");
            return false;
        }
    }

    public async Task<LlmConnectionTestResult> TestConnectionAsync(
        string providerId,
        CancellationToken cancellationToken)
    {
        _ = FindProvider(providerId);
        var state = ActionStateFor(providerId);
        if (state.IsConnectionTesting || state.IsAgentTesting)
        {
            return new LlmConnectionTestResult(
                LlmConnectionTestStatus.Failed,
                latencyMs: null,
                safeMessage: "provider_action_busy");
        }
        state.IsConnectionTesting = true;
        state.FeedbackMessage = null;
        IsBusy = true;
        RefreshProviders();
        try
        {
            var result = await service.TestConnectionAsync(
                providerId,
                cancellationToken);
            state.FeedbackMessage = WithSafeMessage(
                L10n.Localize(
                    result.Succeeded
                        ? "SettingsConnectionSucceeded"
                        : "SettingsConnectionFailed"),
                result.SafeMessage);
            RefreshProviders();
            FeedbackMessage = state.FeedbackMessage;
            return result;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            state.FeedbackMessage = L10n.Localize("WorkflowStatusCancelled");
            FeedbackMessage = state.FeedbackMessage;
            throw;
        }
        catch
        {
            state.FeedbackMessage = L10n.Localize("LlmProviderActionFailed");
            FeedbackMessage = state.FeedbackMessage;
            throw;
        }
        finally
        {
            state.IsConnectionTesting = false;
            IsBusy = false;
            RefreshProviders();
        }
    }

    public async Task<LlmAgentCapabilityTestResult> TestAgentAsync(
        string providerId,
        CancellationToken cancellationToken)
    {
        _ = FindProvider(providerId);
        var state = ActionStateFor(providerId);
        if (state.IsConnectionTesting || state.IsAgentTesting)
        {
            return new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Error,
                "provider_action_busy");
        }
        state.IsAgentTesting = true;
        state.FeedbackMessage = null;
        IsBusy = true;
        RefreshProviders();
        try
        {
            var result = await service.TestAgentCapabilityAsync(
                providerId,
                cancellationToken);
            state.FeedbackMessage = WithSafeMessage(
                AgentStatusText(result.Status),
                result.SafeMessage);
            RefreshProviders();
            FeedbackMessage = state.FeedbackMessage;
            return result;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            state.FeedbackMessage = L10n.Localize("WorkflowStatusCancelled");
            FeedbackMessage = state.FeedbackMessage;
            throw;
        }
        catch
        {
            state.FeedbackMessage = L10n.Localize("LlmProviderActionFailed");
            FeedbackMessage = state.FeedbackMessage;
            throw;
        }
        finally
        {
            state.IsAgentTesting = false;
            IsBusy = false;
            RefreshProviders();
        }
    }

    public async Task<bool> DeleteAsync(
        string providerId,
        bool confirmed,
        CancellationToken cancellationToken)
    {
        if (!confirmed)
        {
            return false;
        }

        var deleted = false;
        await RunBusyAsync(async () =>
        {
            deleted = await service.DeleteAsync(providerId, cancellationToken);
            if (deleted)
            {
                if (string.Equals(
                        Editor?.ProviderId,
                        providerId,
                        StringComparison.Ordinal))
                {
                    Editor = null;
                }
                RefreshProviders();
                FeedbackMessage = L10n.Localize("SettingsDeleteSucceeded");
            }
        });
        return deleted;
    }

    private LlmProviderRecord FindProvider(string providerId) => service.List()
        .FirstOrDefault(provider => string.Equals(
            provider.Id,
            providerId,
            StringComparison.Ordinal))
        ?? throw new InvalidOperationException("The provider no longer exists.");

    private void RefreshProviders() => Providers = service.List()
        .Select(provider =>
        {
            var action = ActionStateFor(provider.Id);
            var credential = credentialPresentations.GetValueOrDefault(
                provider.Id,
                L10n.Localize("SettingsCredentialNotConfigured"));
            return new LlmProviderCardViewModel(
                provider.Id,
                provider.DisplayName,
                provider.BaseUri?.AbsoluteUri.TrimEnd('/') ?? string.Empty,
                provider.DefaultModel ?? string.Empty,
                provider.Enabled,
                provider.IsDefault,
                provider.HealthStatus,
                HealthStatusText(provider.HealthStatus),
                provider.HealthMessage,
                provider.HealthLatencyMs,
                provider.AgentCapabilityStatus,
                AgentStatusText(provider.AgentCapabilityStatus),
                provider.AgentCapabilityMessage,
                credential,
                action.IsConnectionTesting,
                action.IsAgentTesting,
                action.FeedbackMessage);
        })
        .ToArray();

    private ProviderActionState ActionStateFor(string providerId)
    {
        if (!actionStates.TryGetValue(providerId, out var state))
        {
            state = new ProviderActionState();
            actionStates.Add(providerId, state);
        }
        return state;
    }

    private async Task RefreshCredentialPresentationAsync(
        string providerId,
        CancellationToken cancellationToken)
    {
        try
        {
            var presentation = await service.GetCredentialPresentationAsync(
                providerId,
                cancellationToken);
            credentialPresentations[providerId] = CredentialText(presentation);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            credentialPresentations[providerId] =
                L10n.Localize("SettingsCredentialNotConfigured");
        }
    }

    private static string CredentialText(CredentialPresentation presentation) =>
        string.IsNullOrWhiteSpace(presentation.Mask)
            ? L10n.Localize(presentation.Availability == CredentialAvailability.Available
                ? "SettingsCredentialConfigured"
                : "SettingsCredentialNotConfigured")
            : presentation.Mask;

    private static string WithSafeMessage(string summary, string? safeMessage) =>
        string.IsNullOrWhiteSpace(safeMessage)
            ? summary
            : string.Concat(summary, " ", safeMessage.Trim());

    private async Task RunBusyAsync(Func<Task> action)
    {
        IsBusy = true;
        try
        {
            await action();
        }
        finally
        {
            IsBusy = false;
        }
    }

    private static string HealthStatusText(LlmProviderHealthStatus status) =>
        L10n.Localize(status switch
        {
            LlmProviderHealthStatus.Unknown => "LlmProviderHealthUnknown",
            LlmProviderHealthStatus.Testing => "LlmProviderHealthTesting",
            LlmProviderHealthStatus.Ok => "LlmProviderHealthAvailable",
            LlmProviderHealthStatus.Error => "LlmProviderHealthUnavailable",
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
        });

    private static string AgentStatusText(LlmAgentCapabilityStatus status) =>
        L10n.Localize(status switch
        {
            LlmAgentCapabilityStatus.Unknown => "LlmProviderAgentUnknown",
            LlmAgentCapabilityStatus.Supported => "LlmProviderAgentSupported",
            LlmAgentCapabilityStatus.Unsupported => "LlmProviderAgentUnsupported",
            LlmAgentCapabilityStatus.Error => "LlmProviderAgentError",
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
        });

    private sealed class ProviderActionState
    {
        public bool IsConnectionTesting { get; set; }

        public bool IsAgentTesting { get; set; }

        public string? FeedbackMessage { get; set; }
    }
}
