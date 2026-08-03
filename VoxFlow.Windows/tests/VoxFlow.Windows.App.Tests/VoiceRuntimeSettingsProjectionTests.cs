using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Tests;

public sealed class VoiceRuntimeSettingsProjectionTests
{
    [Fact]
    public void Voice_settings_drive_the_actual_hotkey_router_audio_and_output_runtime_options()
    {
        var store = new VoxFlowStateStore();
        var settings = new SettingsPageViewModel(
            "Settings",
            "Configure VoxFlow",
            store,
            new FakeTextStore());
        Assert.True(settings.TryNavigate("voice"));
        var voice = Assert.IsType<VoiceSettingsPageViewModel>(settings.CurrentPage);
        voice.SetInteractionMode("toggle");
        voice.MiddleMouseEnabled = true;
        voice.MutePlaybackDuringRecording = true;
        voice.FeedbackSoundsEnabled = false;
        voice.VoiceEnhancementEnabled = false;
        voice.KeepMicrophoneActive = true;
        voice.SetOutputMode("simulatedTyping");

        var type = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.VoiceRuntimeSettingsProjection");
        Assert.NotNull(type);
        dynamic runtime = type.GetMethod("From")!.Invoke(
            null,
            [store.Current])!;
        var router = new HotkeyInputRouter(
            Assert.IsType<HotkeyRouteSettings>(runtime.Hotkey));

        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            router.HandleMouse(
                MouseButton.Middle,
                ButtonTransition.Down,
                DictationPhase.Idle));
        Assert.True((bool)runtime.Audio.Policy.MutePlaybackDuringRecording);
        Assert.False((bool)runtime.Audio.Policy.FeedbackSounds);
        Assert.False((bool)runtime.Audio.Policy.VoiceEnhancement);
        Assert.True((bool)runtime.Audio.Policy.KeepMicrophoneActive);
        Assert.Equal("simulatedTyping", (string)runtime.OutputModeId);
    }

    private sealed class FakeTextStore : ITextProcessingSettingsStore
    {
        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(DeterministicTextProcessingSettings.Default);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }
}
