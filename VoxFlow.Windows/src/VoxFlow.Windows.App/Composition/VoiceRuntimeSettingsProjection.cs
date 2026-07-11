using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Platform.Audio;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Composition;

public sealed record VoiceRuntimeSettingsProjection(
    HotkeyRouteSettings Hotkey,
    WasapiDictationAudioOptions Audio,
    string OutputModeId)
{
    public static VoiceRuntimeSettingsProjection From(VoxFlowStateSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var settings = snapshot.State.Settings;
        var interaction = Read(settings, "voice.interactionMode", "hybrid") switch
        {
            "hold" => HotkeyInteractionMode.Hold,
            "toggle" => HotkeyInteractionMode.Toggle,
            _ => HotkeyInteractionMode.Hybrid,
        };
        var deviceId = Read(settings, "voice.deviceId", "default");
        if (string.Equals(deviceId, "default", StringComparison.Ordinal))
        {
            deviceId = null;
        }

        return new VoiceRuntimeSettingsProjection(
            new HotkeyRouteSettings(
                HotkeyBinding.RightControlDefault,
                interaction,
                ReadBool(settings, "voice.middleMouseEnabled", false)),
            new WasapiDictationAudioOptions(
                deviceId,
                new AudioCapturePolicyOptions(
                    ReadBool(settings, "voice.mutePlaybackDuringRecording", false),
                    ReadBool(settings, "voice.feedbackSoundsEnabled", true),
                    ReadBool(settings, "voice.voiceEnhancementEnabled", true),
                    ReadBool(settings, "voice.keepMicrophoneActive", false))),
            Read(settings, "voice.outputMode", "quickPaste"));
    }

    private static string Read(
        IReadOnlyDictionary<string, string> settings,
        string key,
        string fallback) => settings.TryGetValue(key, out var value)
            ? value
            : fallback;

    private static bool ReadBool(
        IReadOnlyDictionary<string, string> settings,
        string key,
        bool fallback) => settings.TryGetValue(key, out var value)
            ? string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
            : fallback;
}
