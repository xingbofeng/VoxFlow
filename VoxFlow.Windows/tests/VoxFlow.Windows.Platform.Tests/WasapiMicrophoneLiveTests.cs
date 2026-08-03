using VoxFlow.Windows.Platform.Audio;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WasapiMicrophoneLiveTests
{
    [Fact]
    public async Task Explicit_live_smoke_captures_a_real_wasapi_frame()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("VOICEINPUT_TEST_WINDOWS_AUDIO"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        var devices = WasapiMicrophoneCapture.EnumerateDevices();
        Assert.Contains(devices, device => device.IsAvailable);

        await using var capture = new WasapiMicrophoneCapture();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        await capture.StartAsync(
            requestedDeviceId: null,
            AudioCapturePolicyOptions.Default with
            {
                FeedbackSounds = false,
                MutePlaybackDuringRecording = false,
                KeepMicrophoneActive = false,
            },
            timeout.Token);

        var frame = await capture.ReadFrameAsync(timeout.Token);
        await capture.StopAsync(CancellationToken.None);

        Assert.NotEmpty(frame.PcmS16LittleEndian.ToArray());
        Assert.Equal(0, frame.PcmS16LittleEndian.Length % sizeof(short));
        Assert.InRange(frame.Rms, 0, 1);
    }
}
