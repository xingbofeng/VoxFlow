using System.Diagnostics;
using System.Text;

namespace VoxFlow.Windows.Infrastructure.Media;

public sealed record FfmpegProcessRequest
{
    public FfmpegProcessRequest(string executablePath, IReadOnlyList<string> arguments)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);
        ArgumentNullException.ThrowIfNull(arguments);
        if (arguments.Any(argument => argument is null))
        {
            throw new ArgumentException("FFmpeg arguments cannot contain null values.", nameof(arguments));
        }

        ExecutablePath = executablePath;
        Arguments = arguments.ToArray();
    }

    public string ExecutablePath { get; }

    public IReadOnlyList<string> Arguments { get; }
}

public sealed record FfmpegProcessResult(
    int ExitCode,
    string StandardOutput,
    string StandardError,
    string? DiagnosticCode);

public interface IFfmpegProcessRunner
{
    Task<FfmpegProcessResult> RunAsync(
        FfmpegProcessRequest request,
        CancellationToken cancellationToken);
}

public sealed class FfmpegProcessRunner : IFfmpegProcessRunner
{
    private const int OutputCharacterLimit = 65_536;

    public async Task<FfmpegProcessResult> RunAsync(
        FfmpegProcessRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        using var process = new Process
        {
            StartInfo = CreateStartInfo(request),
            EnableRaisingEvents = true,
        };
        if (!process.Start())
        {
            throw new InvalidOperationException("The controlled FFmpeg process could not be started.");
        }

        var outputTask = ReadLimitedAsync(process.StandardOutput);
        var errorTask = ReadLimitedAsync(process.StandardError);
        try
        {
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            TryKillProcessTree(process);
            await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
            await Task.WhenAll(outputTask, errorTask).ConfigureAwait(false);
            throw;
        }

        await Task.WhenAll(outputTask, errorTask).ConfigureAwait(false);
        return new FfmpegProcessResult(
            process.ExitCode,
            outputTask.Result,
            errorTask.Result,
            process.ExitCode == 0 ? null : $"ffmpeg_exit_{process.ExitCode}");
    }

    internal static ProcessStartInfo CreateStartInfo(FfmpegProcessRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var startInfo = new ProcessStartInfo
        {
            FileName = request.ExecutablePath,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardInput = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var argument in request.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        return startInfo;
    }

    private static async Task<string> ReadLimitedAsync(StreamReader reader)
    {
        var output = new StringBuilder(OutputCharacterLimit);
        var buffer = new char[4_096];
        while (true)
        {
            var read = await reader.ReadAsync(buffer).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            var remaining = OutputCharacterLimit - output.Length;
            if (remaining > 0)
            {
                output.Append(buffer, 0, Math.Min(read, remaining));
            }
        }

        return output.ToString();
    }

    private static void TryKillProcessTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            // The process exited between the state check and Kill.
        }
    }
}
