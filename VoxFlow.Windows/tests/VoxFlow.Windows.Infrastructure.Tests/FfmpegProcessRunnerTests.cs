using VoxFlow.Windows.Infrastructure.Media;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class FfmpegProcessRunnerTests
{
    [Fact]
    public void Start_info_uses_an_argument_list_hidden_window_and_redirected_pipes()
    {
        var request = new FfmpegProcessRequest(
            @"C:\Program Files\VoxFlow\runtime\ffmpeg\ffmpeg.exe",
            ["-hide_banner", "-i", @"C:\User Files\private meeting.mp4", "output.wav"]);

        var startInfo = FfmpegProcessRunner.CreateStartInfo(request);

        Assert.False(startInfo.UseShellExecute);
        Assert.True(startInfo.CreateNoWindow);
        Assert.True(startInfo.RedirectStandardOutput);
        Assert.True(startInfo.RedirectStandardError);
        Assert.Equal(request.Arguments, startInfo.ArgumentList);
        Assert.Empty(startInfo.Arguments);
    }

    [Fact]
    public async Task Nonzero_exit_maps_to_a_safe_code_while_output_is_captured()
    {
        var command = Environment.GetEnvironmentVariable("ComSpec")!;
        var request = new FfmpegProcessRequest(
            command,
            ["/d", "/c", "echo probe-output& echo probe-error 1>&2& exit /b 7"]);

        var result = await new FfmpegProcessRunner().RunAsync(
            request,
            CancellationToken.None);

        Assert.Equal(7, result.ExitCode);
        Assert.Equal("ffmpeg_exit_7", result.DiagnosticCode);
        Assert.Contains("probe-output", result.StandardOutput, StringComparison.Ordinal);
        Assert.Contains("probe-error", result.StandardError, StringComparison.Ordinal);
        Assert.DoesNotContain("private", result.DiagnosticCode, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Cancellation_terminates_the_started_process_tree()
    {
        var command = Environment.GetEnvironmentVariable("ComSpec")!;
        var request = new FfmpegProcessRequest(
            command,
            ["/d", "/c", "ping -n 30 127.0.0.1 >nul"]);
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(150));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await new FfmpegProcessRunner().RunAsync(request, cancellation.Token));
    }
}
