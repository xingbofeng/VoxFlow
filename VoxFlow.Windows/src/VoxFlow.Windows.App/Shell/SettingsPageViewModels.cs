using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Providers.Cloud.OpenAI;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Shell;

public enum SettingsRoute
{
    General,
    Models,
    Voice,
    Text,
}

public enum ModelsSettingsTab
{
    Asr,
    Llm,
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

public sealed record ProviderSettingsCardViewModel(
    string Id,
    string Heading,
    string Description,
    string Status);

public sealed class CloudProviderSettingsCardViewModel : BindableObject
{
    private bool isConfigured;
    private bool isReady;
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

    public string Status => L10n.Localize(IsReady
        ? "SettingsStatusReady"
        : IsConfigured
            ? "SettingsStatusConfigured"
            : "SettingsStatusNotConfigured");

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public void Apply(bool configured, bool ready, string? feedbackKey = null)
    {
        IsConfigured = configured;
        IsReady = ready;
        FeedbackMessage = feedbackKey is null ? null : L10n.Localize(feedbackKey);
        OnPropertyChanged(nameof(Status));
    }
}

public sealed class OpenAiSettingsCardViewModel : BindableObject
{
    private readonly OpenAiSettingsService? service;
    private readonly SettingsStateCoordinator coordinator;
    private string model = OpenAiProductionDefaults.DefaultModel;
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
    }

    public string Heading => L10n.Localize("SettingsOpenAiHeading");

    public string Description => L10n.Localize("SettingsOpenAiDescription");

    public string BaseUrl => OpenAiProductionDefaults.BaseUri.AbsoluteUri.TrimEnd('/');

    public bool CanEditBaseUrl => false;

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
        private set => SetField(ref isBusy, value);
    }

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

        var status = await service.GetStatusAsync(cancellationToken).ConfigureAwait(false);
        Model = status.Model;
        Enabled = status.Enabled;
        IsConfigured = status.IsConfigured;
        ApiKeyPresentation = status.ApiKey.Mask;
        coordinator.RecordOpenAi(IsConfigured, Enabled);
    }

    public async Task SaveAsync(
        string apiKey,
        string selectedModel,
        bool selectedEnabled,
        CancellationToken cancellationToken)
    {
        if (service is null)
        {
            throw new InvalidOperationException("OpenAI settings are unavailable.");
        }

        IsBusy = true;
        FeedbackMessage = null;
        try
        {
            await service.SaveAsync(
                    apiKey,
                    selectedModel,
                    selectedEnabled,
                    cancellationToken)
                .ConfigureAwait(false);
            Model = selectedModel;
            Enabled = selectedEnabled;
            IsConfigured = true;
            ApiKeyPresentation = L10n.Localize("SettingsCredentialConfigured");
            FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
            coordinator.RecordOpenAi(configured: true, enabled: selectedEnabled);
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
            return false;
        }

        IsBusy = true;
        try
        {
            var result = await service.TestConnectionAsync(cancellationToken)
                .ConfigureAwait(false);
            FeedbackMessage = L10n.Localize(
                result.Succeeded
                    ? "SettingsConnectionSucceeded"
                    : "SettingsConnectionFailed");
            return result.Succeeded;
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
            return false;
        }

        IsBusy = true;
        try
        {
            await service.DeleteAsync(cancellationToken).ConfigureAwait(false);
            Enabled = false;
            IsConfigured = false;
            ApiKeyPresentation = L10n.Localize("SettingsCredentialNotConfigured");
            FeedbackMessage = L10n.Localize("SettingsDeleteSucceeded");
            coordinator.RecordOpenAi(configured: false, enabled: false);
            return true;
        }
        finally
        {
            IsBusy = false;
        }
    }
}

public sealed record GeneralSettingsPageViewModel(
    string Heading,
    string Subtitle);

public sealed class ModelsSettingsPageViewModel : BindableObject
{
    private readonly CloudAsrSettingsCoordinator? cloudSettings;
    private ModelsSettingsTab selectedTab;

    public ModelsSettingsPageViewModel(
        OpenAiSettingsCardViewModel openAi,
        CloudAsrSettingsCoordinator? cloudSettings = null)
    {
        OpenAi = openAi ?? throw new ArgumentNullException(nameof(openAi));
        this.cloudSettings = cloudSettings;
        Tabs =
        [
            new("asr", ModelsSettingsTab.Asr, L10n.Localize("SettingsModelsAsrTab")),
            new("llm", ModelsSettingsTab.Llm, L10n.Localize("SettingsModelsLlmTab")),
        ];
        AsrCards =
        [
            ProviderCard("qwen-0.6b", "TrayAsrQwen06B", "SettingsProviderQwen06Description"),
            ProviderCard("qwen-1.7b", "TrayAsrQwen17B", "SettingsProviderQwen17Description"),
        ];
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

    public IReadOnlyList<ProviderSettingsCardViewModel> AsrCards { get; }

    public OpenAiSettingsCardViewModel OpenAi { get; }

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
        }
    }

    public string SelectedTabId => SelectedTab switch
    {
        ModelsSettingsTab.Asr => "asr",
        ModelsSettingsTab.Llm => "llm",
        _ => throw new ArgumentOutOfRangeException(),
    };

    public bool TrySelectTab(string tabId)
    {
        var tab = tabId.Trim().ToLowerInvariant() switch
        {
            "asr" => ModelsSettingsTab.Asr,
            "llm" => ModelsSettingsTab.Llm,
            _ => (ModelsSettingsTab?)null,
        };
        if (tab is null)
        {
            return false;
        }

        SelectedTab = tab.Value;
        return true;
    }

    private static ProviderSettingsCardViewModel ProviderCard(
        string id,
        string headingKey,
        string descriptionKey) => new(
            id,
            L10n.Localize(headingKey),
            L10n.Localize(descriptionKey),
            L10n.Localize("SettingsStatusNotConfigured"));

    public async Task LoadCloudAsync(CancellationToken cancellationToken)
    {
        if (cloudSettings is null)
        {
            return;
        }

        var status = await cloudSettings.LoadAsync(cancellationToken).ConfigureAwait(false);
        Tencent.Apply(status.TencentConfigured, ready: false);
        Aliyun.Apply(status.AliyunConfigured, ready: false);
        Volcengine.Apply(status.VolcengineConfigured, ready: false);
    }

    public async Task SaveTencentAsync(
        string appId,
        string secretId,
        string secretKey,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        await cloudSettings!.SaveTencentAsync(
            appId,
            secretId,
            secretKey,
            cancellationToken).ConfigureAwait(false);
        Tencent.Apply(configured: true, ready: false, "SettingsSaveSucceeded");
    }

    public async Task SaveAliyunAsync(
        string apiKey,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        await cloudSettings!.SaveAliyunAsync(apiKey, cancellationToken)
            .ConfigureAwait(false);
        Aliyun.Apply(configured: true, ready: false, "SettingsSaveSucceeded");
    }

    public async Task SaveVolcengineAsync(
        string appId,
        string accessToken,
        string secretKey,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        await cloudSettings!.SaveVolcengineAsync(
            appId,
            accessToken,
            secretKey,
            cancellationToken).ConfigureAwait(false);
        Volcengine.Apply(configured: true, ready: false, "SettingsSaveSucceeded");
    }

    public async Task<bool> TestCloudAsync(
        AsrProviderId provider,
        CancellationToken cancellationToken)
    {
        EnsureCloudAvailable();
        var succeeded = await cloudSettings!.TestAsync(provider, cancellationToken)
            .ConfigureAwait(false);
        Card(provider).Apply(
            configured: true,
            ready: succeeded,
            succeeded ? "SettingsConnectionSucceeded" : "SettingsConnectionFailed");
        return succeeded;
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
        await cloudSettings!.DeleteAsync(provider, cancellationToken)
            .ConfigureAwait(false);
        Card(provider).Apply(
            configured: false,
            ready: false,
            "SettingsDeleteSucceeded");
        return true;
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

    public VoiceSettingsPageViewModel(VoxFlowStateStore stateStore)
    {
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
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
        AvailableDevices =
        [
            new("default", L10n.Localize("SettingsVoiceDefaultMicrophone")),
        ];
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

    public IReadOnlyList<SettingsChoiceViewModel> AvailableDevices { get; }

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

    public string ShortcutId => "right-control";

    public string ShortcutDisplay => L10n.Localize("SettingsVoiceShortcutRightControl");

    public string InteractionModeId
    {
        get => interactionModeId;
        set => SetInteractionMode(value);
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

    public TextSettingsPageViewModel(
        ITextProcessingSettingsStore settingsStore,
        VoxFlowStateStore stateStore,
        OpenAiSettingsCardViewModel openAi)
    {
        this.settingsStore = settingsStore
            ?? throw new ArgumentNullException(nameof(settingsStore));
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
        OpenAi = openAi ?? throw new ArgumentNullException(nameof(openAi));
    }

    public string Heading => L10n.Localize("SettingsTextHeading");

    public string Subtitle => L10n.Localize("SettingsTextSubtitle");

    public OpenAiSettingsCardViewModel OpenAi { get; }

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

    public async Task SaveAsync(CancellationToken cancellationToken)
    {
        await settingsStore.SaveAsync(settings, cancellationToken).ConfigureAwait(false);
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

public sealed class SettingsPageViewModel : BindableObject
{
    private readonly GeneralSettingsPageViewModel general;
    private readonly ModelsSettingsPageViewModel models;
    private readonly VoiceSettingsPageViewModel voice;
    private readonly TextSettingsPageViewModel text;
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
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(heading);
        ArgumentException.ThrowIfNullOrWhiteSpace(subtitle);
        Heading = heading;
        Subtitle = subtitle;
        general = new GeneralSettingsPageViewModel(
            L10n.Localize("SettingsGeneralHeading"),
            L10n.Localize("SettingsGeneralSubtitle"));
        var coordinator = new SettingsStateCoordinator(stateStore);
        var openAi = new OpenAiSettingsCardViewModel(
            coordinator,
            openAiSettingsService);
        models = new ModelsSettingsPageViewModel(openAi, cloudAsrSettings);
        voice = new VoiceSettingsPageViewModel(stateStore);
        text = new TextSettingsPageViewModel(textSettingsStore, stateStore, openAi);
        NavigationItems =
        [
            Item("general", SettingsRoute.General, "SettingsNavigationGeneral", "\uE713"),
            Item("models", SettingsRoute.Models, "SettingsNavigationModels", "\uE950"),
            Item("voice", SettingsRoute.Voice, "SettingsNavigationVoice", "\uE720"),
            Item("text", SettingsRoute.Text, "SettingsNavigationText", "\uE8D2"),
        ];
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
        SettingsRoute.Text => text,
        _ => throw new InvalidOperationException("The settings route is unavailable."),
    };

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await text.LoadAsync(cancellationToken).ConfigureAwait(false);
        await text.OpenAi.LoadAsync(cancellationToken).ConfigureAwait(false);
        await models.LoadCloudAsync(cancellationToken).ConfigureAwait(false);
    }

    public bool TryNavigate(string routeId)
    {
        var route = routeId.Trim().ToLowerInvariant() switch
        {
            "general" => SettingsRoute.General,
            "models" => SettingsRoute.Models,
            "voice" => SettingsRoute.Voice,
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
