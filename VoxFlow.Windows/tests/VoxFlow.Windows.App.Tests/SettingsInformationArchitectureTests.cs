using System.Collections;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.App.Tests;

public sealed class SettingsInformationArchitectureTests
{
    [Fact]
    public async Task Settings_exposes_only_general_models_voice_and_text_with_agent_model_tab()
    {
        var viewModel = Create(new VoxFlowStateStore(), new FakeTextSettingsStore());
        await InvokeAsync(viewModel, "InitializeAsync");

        Assert.Equal(
            new[] { "general", "models", "voice", "text" },
            ItemIds((IEnumerable)((dynamic)viewModel).NavigationItems));
        Assert.False(((dynamic)viewModel).TryNavigate("screenshot"));
        Assert.False(((dynamic)viewModel).TryNavigate("translation"));
        Assert.False(((dynamic)viewModel).TryNavigate("agent"));

        Assert.True(((dynamic)viewModel).TryNavigate("models"));
        dynamic models = ((dynamic)viewModel).CurrentPage;
        Assert.Equal(new[] { "asr", "llm", "agent" }, ItemIds((IEnumerable)models.Tabs));
        Assert.True(models.TrySelectTab("llm"));
        Assert.True(models.TrySelectTab("agent"));
        Assert.False(models.TrySelectTab("downloads"));
        Assert.Equal("agent", (string)models.SelectedTabId);
    }

    [Fact]
    public async Task Voice_page_has_five_cards_and_writes_shortcut_and_middle_mouse_to_shared_state()
    {
        var stateStore = new VoxFlowStateStore();
        var viewModel = Create(stateStore, new FakeTextSettingsStore());
        await InvokeAsync(viewModel, "InitializeAsync");
        Assert.True(((dynamic)viewModel).TryNavigate("voice"));

        dynamic voice = ((dynamic)viewModel).CurrentPage;
        Assert.Equal(
            new[] { "input", "shortcut", "audio", "output", "runtime" },
            ItemIds((IEnumerable)voice.Cards));

        voice.SetInteractionMode("toggle");
        voice.MiddleMouseEnabled = true;
        voice.SelectedDeviceId = "usb-microphone";
        voice.SetRecognitionLanguage("en-US");
        voice.MutePlaybackDuringRecording = true;
        voice.FeedbackSoundsEnabled = false;
        voice.VoiceEnhancementEnabled = false;
        voice.SetOutputMode("simulatedTyping");
        voice.KeepMicrophoneActive = true;

        Assert.Equal("toggle", stateStore.Current.State.Settings["voice.interactionMode"]);
        Assert.Equal("true", stateStore.Current.State.Settings["voice.middleMouseEnabled"]);
        Assert.Equal("usb-microphone", stateStore.Current.State.Settings["voice.deviceId"]);
        Assert.Equal("en-US", stateStore.Current.State.Settings["recognition.language"]);
        Assert.Equal("true", stateStore.Current.State.Settings["voice.mutePlaybackDuringRecording"]);
        Assert.Equal("false", stateStore.Current.State.Settings["voice.feedbackSoundsEnabled"]);
        Assert.Equal("false", stateStore.Current.State.Settings["voice.voiceEnhancementEnabled"]);
        Assert.Equal("simulatedTyping", stateStore.Current.State.Settings["voice.outputMode"]);
        Assert.Equal("true", stateStore.Current.State.Settings["voice.keepMicrophoneActive"]);
    }

    [Fact]
    public async Task Text_page_edits_master_six_strategies_and_four_thresholds_as_one_saved_value()
    {
        var textStore = new FakeTextSettingsStore();
        var viewModel = Create(new VoxFlowStateStore(), textStore);
        await InvokeAsync(viewModel, "InitializeAsync");
        Assert.True(((dynamic)viewModel).TryNavigate("text"));

        dynamic text = ((dynamic)viewModel).CurrentPage;
        text.Enabled = false;
        text.SmartNumberRecognition = false;
        text.PunctuationOptimization = false;
        text.LongSentenceBreaking = true;
        text.FillerWordFiltering = false;
        text.CjkLatinSpacing = false;
        text.AutoCapitalization = false;
        text.LongSentenceWordThreshold = 20;
        text.LongSentenceCjkThreshold = 24;
        text.PunctuationCjkThreshold = 5;
        text.PunctuationWordThreshold = 7;
        await InvokeAsync(text, "SaveAsync");

        var saved = Assert.IsType<DeterministicTextProcessingSettings>(textStore.Saved);
        Assert.False(saved.Enabled);
        Assert.False(saved.SmartNumberRecognition);
        Assert.False(saved.PunctuationOptimization);
        Assert.True(saved.LongSentenceBreaking);
        Assert.False(saved.FillerWordFiltering);
        Assert.False(saved.CjkLatinSpacing);
        Assert.False(saved.AutoCapitalization);
        Assert.Equal(20, saved.LongSentenceWordThreshold);
        Assert.Equal(24, saved.LongSentenceCjkThreshold);
        Assert.Equal(5, saved.PunctuationCjkThreshold);
        Assert.Equal(7, saved.PunctuationWordThreshold);
    }

    [Fact]
    public async Task Models_hosts_llm_credentials_while_text_is_deterministic_processors_only()
    {
        var viewModel = Create(new VoxFlowStateStore(), new FakeTextSettingsStore());
        await InvokeAsync(viewModel, "InitializeAsync");
        Assert.True(((dynamic)viewModel).TryNavigate("models"));
        dynamic models = ((dynamic)viewModel).CurrentPage;
        dynamic modelsOpenAi = models.OpenAi;
        Assert.True(models.TrySelectTab("llm"));
        Assert.Equal("https://tokenhub.tencentmaas.com/v1", (string)modelsOpenAi.BaseUrl);
        Assert.True((bool)modelsOpenAi.CanEditBaseUrl);
        Assert.Equal(
            new[] { "save", "test", "delete" },
            ItemIds((IEnumerable)modelsOpenAi.Actions));

        Assert.True(((dynamic)viewModel).TryNavigate("text"));
        dynamic text = ((dynamic)viewModel).CurrentPage;
        Assert.IsType<TextSettingsPageViewModel>((object)text);
        Assert.Null(typeof(TextSettingsPageViewModel).GetProperty("OpenAi"));
        // Text page still exposes deterministic processor toggles.
        Assert.True((bool)text.Enabled);
        Assert.True((bool)text.CanSave);
    }

    private static SettingsPageViewModel Create(
        VoxFlowStateStore stateStore,
        ITextProcessingSettingsStore textStore) =>
        Assert.IsType<SettingsPageViewModel>(Activator.CreateInstance(
            typeof(SettingsPageViewModel),
            "Settings",
            "Configure VoxFlow",
            stateStore,
            textStore));

    private static string[] ItemIds(IEnumerable items) => items
        .Cast<object>()
        .Select(item => Assert.IsType<string>(
            item.GetType().GetProperty("Id")!.GetValue(item)))
        .ToArray();

    private static async Task InvokeAsync(object target, string methodName)
    {
        dynamic result = target.GetType().GetMethod(methodName)!.Invoke(
            target,
            [CancellationToken.None])!;
        await result;
    }

    private sealed class FakeTextSettingsStore : ITextProcessingSettingsStore
    {
        public DeterministicTextProcessingSettings Current { get; set; } =
            DeterministicTextProcessingSettings.Default;

        public DeterministicTextProcessingSettings? Saved { get; private set; }

        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(Current);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken)
        {
            Saved = settings;
            Current = settings;
            return ValueTask.CompletedTask;
        }
    }
}
