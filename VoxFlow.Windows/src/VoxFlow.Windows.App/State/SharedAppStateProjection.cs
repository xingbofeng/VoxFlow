using System.Collections.Immutable;
using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.State;

public sealed record SharedAppStateSnapshot(
    long Version,
    TrayMenuState TrayMenu,
    VoxFlowError? LastFailure,
    bool LlmFallbackUsed);

/// <summary>
/// Projects one versioned state-store snapshot for every visible entry point.
/// No surface maintains an independently mutable provider or model selection.
/// </summary>
public sealed class SharedAppStateProjection : ITrayMenuStateSource, IDisposable
{
    private readonly object syncRoot = new();
    private readonly IDisposable subscription;
    private readonly bool selectionTransformsAvailable;
    private SharedAppStateSnapshot current;

    public SharedAppStateProjection(VoxFlowStateStore stateStore)
        : this(stateStore, selectionTransformsAvailable: false)
    {
    }

    public SharedAppStateProjection(
        VoxFlowStateStore stateStore,
        bool selectionTransformsAvailable)
    {
        ArgumentNullException.ThrowIfNull(stateStore);
        this.selectionTransformsAvailable = selectionTransformsAvailable;
        current = Project(stateStore.Current, selectionTransformsAvailable);
        subscription = stateStore.Subscribe(HandleStateChanged, replayCurrent: false);
    }

    public event EventHandler<SharedAppStateSnapshot>? SnapshotChanged;

    public SharedAppStateSnapshot Current
    {
        get
        {
            lock (syncRoot)
            {
                return current;
            }
        }
    }

    public TrayMenuState Read() => Current.TrayMenu;

    public void Dispose() => subscription.Dispose();

    private void HandleStateChanged(StateChanged change)
    {
        var next = Project(change.Snapshot, selectionTransformsAvailable);
        lock (syncRoot)
        {
            current = next;
        }

        SnapshotChanged?.Invoke(this, next);
    }

    private static SharedAppStateSnapshot Project(
        VoxFlowStateSnapshot snapshot,
        bool selectionTransformsAvailable)
    {
        var settings = snapshot.State.Settings;
        var choices = new[]
        {
            Choice(settings, AsrProviderId.Qwen, QwenVariant.Qwen06B),
            Choice(settings, AsrProviderId.Qwen, QwenVariant.Qwen17B),
            Choice(settings, AsrProviderId.TencentCloud, null),
            Choice(settings, AsrProviderId.AliyunDashScope, null),
            Choice(settings, AsrProviderId.Volcengine, null),
        };
        var selected = ReadSelection(settings);
        if (selected is not null
            && !choices.Any(choice =>
                choice.Provider == selected.Provider
                && choice.QwenVariant == selected.QwenVariant
                && choice.IsConfigured
                && choice.IsReady))
        {
            selected = null;
        }

        var tray = new TrayMenuState(
            ReadEnum(settings, "recognition.language", RecognitionLanguage.Automatic),
            selected,
            choices,
            ReadBool(settings, "openai.configured"),
            ReadBool(settings, "openai.enabled"),
            new TrayAgentState(
                ReadBool(settings, "agent.runtime.available"),
                ReadBool(settings, "agent.provider.configured"),
                ReadBool(settings, "agent.provider.connectionHealthy"),
                ReadBool(settings, "agent.provider.toolCallingSupported"),
                ReadEnum(settings, "agent.phase", DictationPhase.Idle)),
            selectionTransformsAvailable);
        return new SharedAppStateSnapshot(
            snapshot.Version,
            tray,
            ReadFailure(settings),
            ReadBool(settings, "failure.llmFallback"));
    }

    private static TrayAsrChoice Choice(
        IReadOnlyDictionary<string, string> settings,
        AsrProviderId provider,
        QwenVariant? variant)
    {
        var prefix = SettingsStateKeys.ProviderPrefix(provider, variant);
        return new TrayAsrChoice(
            provider,
            variant,
            ReadBool(settings, $"{prefix}.configured"),
            ReadBool(settings, $"{prefix}.ready"));
    }

    private static AsrSelection? ReadSelection(
        IReadOnlyDictionary<string, string> settings)
    {
        if (!settings.TryGetValue("asr.selected.provider", out var providerText)
            || !Enum.TryParse<AsrProviderId>(providerText, out var provider))
        {
            return null;
        }

        QwenVariant? variant = null;
        if (provider == AsrProviderId.Qwen)
        {
            if (!settings.TryGetValue("asr.selected.variant", out var variantText)
                || !Enum.TryParse<QwenVariant>(variantText, out var parsedVariant))
            {
                return null;
            }

            variant = parsedVariant;
        }

        return new AsrSelection(provider, variant);
    }

    private static VoxFlowError? ReadFailure(
        IReadOnlyDictionary<string, string> settings)
    {
        if (!settings.TryGetValue("failure.code", out var codeText)
            || !Enum.TryParse<VoxFlowErrorCode>(codeText, out var code))
        {
            return null;
        }

        AsrProviderId? provider = null;
        if (settings.TryGetValue("failure.provider", out var providerText)
            && Enum.TryParse<AsrProviderId>(providerText, out var parsedProvider))
        {
            provider = parsedProvider;
        }

        return new VoxFlowError(code, provider);
    }

    private static bool ReadBool(
        IReadOnlyDictionary<string, string> settings,
        string key) => settings.TryGetValue(key, out var value)
            && string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);

    private static T ReadEnum<T>(
        IReadOnlyDictionary<string, string> settings,
        string key,
        T fallback)
        where T : struct, Enum => settings.TryGetValue(key, out var value)
            && Enum.TryParse<T>(value, out var parsed)
                ? parsed
                : fallback;
}

public sealed class SettingsStateCoordinator
{
    private readonly VoxFlowStateStore stateStore;

    public SettingsStateCoordinator(VoxFlowStateStore stateStore)
    {
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
    }

    public void RecordCloudProvider(
        AsrProviderId provider,
        bool configured,
        bool ready)
    {
        if (provider == AsrProviderId.Qwen)
        {
            throw new ArgumentException("Use the Qwen model status operation.", nameof(provider));
        }

        RecordProvider(provider, null, configured, ready);
    }

    public void RecordQwenModel(
        QwenVariant variant,
        bool installed,
        bool ready) => RecordProvider(
            AsrProviderId.Qwen,
            variant,
            installed,
            ready);

    public void RecordOpenAi(bool configured, bool enabled) => stateStore.Dispatch(
        new UpdateSettingsCommand(
            new Dictionary<string, string?>
            {
                ["openai.configured"] = Bool(configured),
                ["openai.enabled"] = Bool(configured && enabled),
            },
            StateChangeKind.Settings | StateChangeKind.Llm));

    public void RecordAgentReadiness(
        bool runtimeAvailable,
        bool providerConfigured,
        bool connectionHealthy,
        bool toolCallingSupported) => stateStore.Dispatch(
        new UpdateSettingsCommand(
            new Dictionary<string, string?>
            {
                ["agent.runtime.available"] = Bool(runtimeAvailable),
                ["agent.provider.configured"] = Bool(providerConfigured),
                ["agent.provider.connectionHealthy"] = Bool(connectionHealthy),
                ["agent.provider.toolCallingSupported"] = Bool(toolCallingSupported),
            },
            StateChangeKind.Settings | StateChangeKind.Llm | StateChangeKind.Ui));

    public void RecordAgentPhase(DictationPhase phase)
    {
        if (!Enum.IsDefined(phase))
        {
            throw new ArgumentOutOfRangeException(nameof(phase));
        }

        stateStore.Dispatch(new UpdateSettingsCommand(
            new Dictionary<string, string?>
            {
                ["agent.phase"] = phase.ToString(),
            },
            StateChangeKind.Dictation | StateChangeKind.Ui));
    }

    public void SelectAsr(AsrProviderId provider, QwenVariant? variant)
    {
        var selection = new AsrSelection(provider, variant);
        var prefix = SettingsStateKeys.ProviderPrefix(provider, variant);
        var settings = stateStore.Current.State.Settings;
        if (!ReadBool(settings, $"{prefix}.configured")
            || !ReadBool(settings, $"{prefix}.ready"))
        {
            throw new InvalidOperationException("Only a configured, ready ASR can be selected.");
        }

        stateStore.Dispatch(new UpdateSettingsCommand(
            new Dictionary<string, string?>
            {
                ["asr.selected.provider"] = selection.Provider.ToString(),
                ["asr.selected.variant"] = selection.QwenVariant?.ToString(),
            },
            StateChangeKind.ProviderSelection));
    }

    public void PublishFailure(VoxFlowError error, bool llmFallback)
    {
        ArgumentNullException.ThrowIfNull(error);
        stateStore.Dispatch(new UpdateSettingsCommand(
            new Dictionary<string, string?>
            {
                ["failure.code"] = error.Code.ToString(),
                ["failure.provider"] = error.Provider?.ToString(),
                ["failure.llmFallback"] = Bool(llmFallback),
            },
            StateChangeKind.Ui | StateChangeKind.Dictation));
    }

    public void ClearFailure() => stateStore.Dispatch(new UpdateSettingsCommand(
        new Dictionary<string, string?>
        {
            ["failure.code"] = null,
            ["failure.provider"] = null,
            ["failure.llmFallback"] = null,
        },
        StateChangeKind.Ui | StateChangeKind.Dictation));

    private void RecordProvider(
        AsrProviderId provider,
        QwenVariant? variant,
        bool configured,
        bool ready)
    {
        if (ready && !configured)
        {
            throw new ArgumentException("A ready provider must be configured.", nameof(ready));
        }

        var prefix = SettingsStateKeys.ProviderPrefix(provider, variant);
        var values = new Dictionary<string, string?>
        {
            [$"{prefix}.configured"] = Bool(configured),
            [$"{prefix}.ready"] = Bool(ready),
        };
        var current = ReadCurrentSelection();
        if (!configured
            && current?.Provider == provider
            && current.QwenVariant == variant)
        {
            values["asr.selected.provider"] = null;
            values["asr.selected.variant"] = null;
        }

        stateStore.Dispatch(new UpdateSettingsCommand(
            values,
            StateChangeKind.Models | StateChangeKind.ProviderSelection));
    }

    private AsrSelection? ReadCurrentSelection()
    {
        var settings = stateStore.Current.State.Settings;
        if (!settings.TryGetValue("asr.selected.provider", out var providerText)
            || !Enum.TryParse<AsrProviderId>(providerText, out var provider))
        {
            return null;
        }

        if (provider != AsrProviderId.Qwen)
        {
            return new AsrSelection(provider, null);
        }

        return settings.TryGetValue("asr.selected.variant", out var variantText)
            && Enum.TryParse<QwenVariant>(variantText, out var variant)
                ? new AsrSelection(provider, variant)
                : null;
    }

    private static bool ReadBool(
        IReadOnlyDictionary<string, string> settings,
        string key) => settings.TryGetValue(key, out var value)
            && string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);

    private static string Bool(bool value) => value ? "true" : "false";
}

internal static class SettingsStateKeys
{
    public static string ProviderPrefix(
        AsrProviderId provider,
        QwenVariant? variant) => (provider, variant) switch
        {
            (AsrProviderId.Qwen, QwenVariant.Qwen06B) => "asr.qwen.0.6b",
            (AsrProviderId.Qwen, QwenVariant.Qwen17B) => "asr.qwen.1.7b",
            (AsrProviderId.TencentCloud, null) => "asr.tencent",
            (AsrProviderId.AliyunDashScope, null) => "asr.aliyun",
            (AsrProviderId.Volcengine, null) => "asr.volcengine",
            _ => throw new ArgumentException("The provider and variant do not form a valid ASR choice."),
        };
}

public abstract class SharedStateObserver : IDisposable
{
    private readonly SharedAppStateProjection projection;

    protected SharedStateObserver(SharedAppStateProjection projection)
    {
        this.projection = projection ?? throw new ArgumentNullException(nameof(projection));
        ObservedSnapshot = projection.Current;
        projection.SnapshotChanged += HandleSnapshotChanged;
    }

    public SharedAppStateSnapshot ObservedSnapshot { get; private set; }

    public long ObservedVersion => ObservedSnapshot.Version;

    public void Dispose() => projection.SnapshotChanged -= HandleSnapshotChanged;

    private void HandleSnapshotChanged(object? sender, SharedAppStateSnapshot snapshot) =>
        ObservedSnapshot = snapshot;
}

public sealed class HomeStateObserver(SharedAppStateProjection projection) :
    SharedStateObserver(projection);

public sealed class SettingsStateObserver(SharedAppStateProjection projection) :
    SharedStateObserver(projection);

public sealed class HudStateObserver(SharedAppStateProjection projection) :
    SharedStateObserver(projection);
