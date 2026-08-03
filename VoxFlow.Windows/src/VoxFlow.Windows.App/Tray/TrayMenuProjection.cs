using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tray;

public sealed record TrayAsrChoice
{
    public TrayAsrChoice(
        AsrProviderId provider,
        QwenVariant? qwenVariant,
        bool IsConfigured,
        bool IsReady)
    {
        if ((provider == AsrProviderId.Qwen) != (qwenVariant is not null))
        {
            throw new ArgumentException(
                "Only Qwen tray choices may carry a Qwen variant.",
                nameof(qwenVariant));
        }

        if (IsReady && !IsConfigured)
        {
            throw new ArgumentException("A ready ASR choice must be configured.");
        }

        Provider = provider;
        QwenVariant = qwenVariant;
        this.IsConfigured = IsConfigured;
        this.IsReady = IsReady;
    }

    public AsrProviderId Provider { get; }

    public QwenVariant? QwenVariant { get; }

    public bool IsConfigured { get; }

    public bool IsReady { get; }
}

public sealed record TrayAgentState(
    bool RuntimeAvailable,
    bool ProviderConfigured,
    bool ConnectionHealthy,
    bool ToolCallingSupported,
    DictationPhase Phase)
{
    public bool IsReady => RuntimeAvailable
        && ProviderConfigured
        && ConnectionHealthy
        && ToolCallingSupported;

    public bool IsRunning => Phase != DictationPhase.Idle;

    public string StatusId => IsRunning
        ? "agent.status.running"
        : IsReady
            ? "agent.status.ready"
            : !RuntimeAvailable
                ? "agent.status.runtimeUnavailable"
                : "agent.status.providerUnavailable";
}

public sealed record TrayMenuState(
    RecognitionLanguage Language,
    AsrSelection? SelectedAsr,
    IReadOnlyList<TrayAsrChoice> AsrChoices,
    bool OpenAiConfigured,
    bool OpenAiEnabled,
    TrayAgentState Agent,
    bool SelectionTransformsAvailable = false);

public enum TrayMenuItemKind
{
    Submenu,
    Option,
    Action,
    Separator,
}

public sealed record TrayMenuItemModel(
    string Id,
    TrayMenuItemKind Kind,
    bool IsEnabled = true,
    bool IsChecked = false,
    IReadOnlyList<TrayMenuItemModel>? Children = null);

public sealed record TrayMenuModel(IReadOnlyList<TrayMenuItemModel> Items)
{
    public IReadOnlyList<TrayMenuItemModel> Flatten()
    {
        List<TrayMenuItemModel> flattened = [];
        foreach (var item in Items)
        {
            Add(item, flattened);
        }

        return flattened;
    }

    public TrayMenuItemModel Find(string id) => Flatten().Single(item =>
        string.Equals(item.Id, id, StringComparison.Ordinal));

    private static void Add(
        TrayMenuItemModel item,
        ICollection<TrayMenuItemModel> destination)
    {
        destination.Add(item);
        if (item.Children is null)
        {
            return;
        }

        foreach (var child in item.Children)
        {
            Add(child, destination);
        }
    }
}

public interface ITrayMenuStateSource
{
    TrayMenuState Read();
}

public interface ITrayMenuView
{
    void Render(TrayMenuModel menu);
}

public sealed class TrayMenuController(
    ITrayMenuStateSource stateSource,
    ITrayMenuView view)
{
    public void OnMenuOpening() =>
        view.Render(TrayMenuProjection.Build(stateSource.Read()));
}

public static class TrayMenuProjection
{
    public static TrayMenuModel Build(TrayMenuState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(state.AsrChoices);

        return new TrayMenuModel(
        [
            Submenu("language", LanguageItems(state.Language)),
            Submenu("asr", AsrItems(state)),
            Submenu("openai",
            [
                Option(
                    "openai.enabled",
                    state.OpenAiConfigured,
                    state.OpenAiEnabled),
            ]),
            Submenu("agent",
            [
                Action(state.Agent.StatusId, isEnabled: false),
                Action("agent.start", isEnabled: state.Agent.IsReady && !state.Agent.IsRunning),
                Action("agent.stop", isEnabled: state.Agent.IsRunning),
            ]),
            Separator("separator.providers"),
            Action("screenshot.start"),
            .. SelectionActions(state.SelectionTransformsAvailable),
            Action("app.openWindow"),
            Action("app.openSettings"),
            Action("app.openGithub"),
            Action("app.openPermissions"),
            Separator("separator.exit"),
            Action("app.exit"),
        ]);
    }

    private static IReadOnlyList<TrayMenuItemModel> SelectionActions(bool available) =>
        available
            ?
            [
                Action("selection.translate"),
                Action("selection.summary"),
            ]
            : [];

    private static IReadOnlyList<TrayMenuItemModel> LanguageItems(
        RecognitionLanguage selected) =>
    [
        Option("language.auto", isChecked: selected == RecognitionLanguage.Automatic),
        Option("language.zh-CN", isChecked: selected == RecognitionLanguage.ChineseMandarin),
        Option("language.en-US", isChecked: selected == RecognitionLanguage.English),
        Option("language.ja-JP", isChecked: selected == RecognitionLanguage.Japanese),
        Option("language.ko-KR", isChecked: selected == RecognitionLanguage.Korean),
    ];

    private static IReadOnlyList<TrayMenuItemModel> AsrItems(TrayMenuState state)
    {
        var choices = state.AsrChoices.ToDictionary(
            choice => (choice.Provider, choice.QwenVariant));

        return
        [
            AsrOption("asr.qwen.0.6b", AsrProviderId.Qwen, QwenVariant.Qwen06B),
            AsrOption("asr.qwen.1.7b", AsrProviderId.Qwen, QwenVariant.Qwen17B),
            AsrOption("asr.tencent", AsrProviderId.TencentCloud, null),
            AsrOption("asr.aliyun", AsrProviderId.AliyunDashScope, null),
            AsrOption("asr.volcengine", AsrProviderId.Volcengine, null),
        ];

        TrayMenuItemModel AsrOption(
            string id,
            AsrProviderId provider,
            QwenVariant? variant)
        {
            choices.TryGetValue((provider, variant), out var availability);
            var isSelected = state.SelectedAsr?.Provider == provider
                && state.SelectedAsr.QwenVariant == variant;
            return Option(
                id,
                isEnabled: availability is { IsConfigured: true, IsReady: true },
                isChecked: isSelected);
        }
    }

    private static TrayMenuItemModel Submenu(
        string id,
        IReadOnlyList<TrayMenuItemModel> children) =>
        new(id, TrayMenuItemKind.Submenu, Children: children);

    private static TrayMenuItemModel Option(
        string id,
        bool isEnabled = true,
        bool isChecked = false) =>
        new(id, TrayMenuItemKind.Option, isEnabled, isChecked);

    private static TrayMenuItemModel Action(string id, bool isEnabled = true) =>
        new(id, TrayMenuItemKind.Action, isEnabled);

    private static TrayMenuItemModel Separator(string id) =>
        new(id, TrayMenuItemKind.Separator, IsEnabled: false);
}
