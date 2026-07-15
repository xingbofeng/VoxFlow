using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Platform.Audio;

namespace VoxFlow.Windows.App.Tests;

public sealed class VoiceDeviceSelectionTests
{
    [Fact]
    public void Voice_settings_enumerate_real_devices_and_persist_selection_into_runtime_projection()
    {
        var catalog = new FakeCatalog(
        [
            new AudioDeviceInfo("dev-a", "Headset Mic", IsDefault: false, IsAvailable: true),
            new AudioDeviceInfo("dev-b", "Built-in Mic", IsDefault: true, IsAvailable: true),
        ]);
        var store = new VoxFlowStateStore();
        var voice = new VoiceSettingsPageViewModel(
            store,
            interactiveHotkeys: null,
            agentHotkeyEnabled: false,
            captureDevices: catalog);

        voice.RefreshAvailableDevices();

        Assert.Equal(3, voice.AvailableDevices.Count);
        Assert.Equal("default", voice.AvailableDevices[0].Id);
        Assert.Contains(voice.AvailableDevices, d => d.Id == "dev-a");
        Assert.Contains(voice.AvailableDevices, d => d.Id == "dev-b");

        voice.SelectedDeviceId = "dev-a";
        Assert.Equal("dev-a", store.Current.State.Settings["voice.deviceId"]);

        var type = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.VoiceRuntimeSettingsProjection");
        Assert.NotNull(type);
        dynamic runtime = type.GetMethod("From")!.Invoke(null, [store.Current])!;
        Assert.Equal("dev-a", (string?)runtime.Audio.DeviceId);
    }

    [Fact]
    public void Selecting_system_default_projects_null_device_id_to_capture()
    {
        var store = new VoxFlowStateStore();
        var voice = new VoiceSettingsPageViewModel(
            store,
            interactiveHotkeys: null,
            agentHotkeyEnabled: false,
            captureDevices: new FakeCatalog(
            [
                new AudioDeviceInfo("dev-a", "Headset Mic", IsDefault: true, IsAvailable: true),
            ]));
        voice.SelectedDeviceId = "dev-a";
        voice.SelectedDeviceId = "default";

        var type = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.VoiceRuntimeSettingsProjection");
        Assert.NotNull(type);
        dynamic runtime = type.GetMethod("From")!.Invoke(null, [store.Current])!;
        Assert.Null((string?)runtime.Audio.DeviceId);
    }

    private sealed class FakeCatalog(IReadOnlyList<AudioDeviceInfo> devices) : ICaptureDeviceCatalog
    {
        public IReadOnlyList<AudioDeviceInfo> ListCaptureDevices() => devices;
    }
}
