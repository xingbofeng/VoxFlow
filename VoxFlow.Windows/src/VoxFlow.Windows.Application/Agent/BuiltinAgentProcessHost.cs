using System.Diagnostics;
using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public interface IBuiltinAgentProcessLauncher
{
    Process Start(ProcessStartInfo startInfo);
}

public sealed class WindowsBuiltinAgentProcessLauncher : IBuiltinAgentProcessLauncher
{
    public Process Start(ProcessStartInfo startInfo) => Process.Start(startInfo)
        ?? throw new InvalidOperationException("The built-in Agent process could not be started.");
}

/// <summary>
/// Launches one verified agent process for one task and writes the sole
/// secret-bearing request line to stdin. It intentionally exposes pipes to the
/// event pump rather than accepting callbacks on a UI thread.
/// </summary>
public sealed class BuiltinAgentProcessHost
{
    private readonly BuiltinAgentProcessSpecification specification;
    private readonly IBuiltinAgentProcessLauncher launcher;

    public BuiltinAgentProcessHost(
        BuiltinAgentProcessSpecification specification,
        IBuiltinAgentProcessLauncher? launcher = null)
    {
        this.specification = specification ?? throw new ArgumentNullException(nameof(specification));
        this.launcher = launcher ?? new WindowsBuiltinAgentProcessLauncher();
    }

    public async Task<BuiltinAgentProcessSession> StartAsync(
        BuiltinAgentSidecarRunRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        var process = launcher.Start(specification.CreateStartInfo(request));
        try
        {
            var line = JsonSerializer.Serialize(request, DomainJson.Options);
            await process.StandardInput.WriteLineAsync(line).ConfigureAwait(false);
            await process.StandardInput.FlushAsync(cancellationToken).ConfigureAwait(false);
            return new BuiltinAgentProcessSession(process);
        }
        catch
        {
            TryKillProcessTree(process);
            process.Dispose();
            throw;
        }
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
            // Exit can race the request write failure path.
        }
    }
}

public sealed class BuiltinAgentProcessSession : IBuiltinAgentProcessSession
{
    public static readonly TimeSpan DefaultTaskTimeout = TimeSpan.FromSeconds(300);

    private readonly Process process;

    public BuiltinAgentProcessSession(Process process) =>
        this.process = process ?? throw new ArgumentNullException(nameof(process));

    public StreamReader StandardOutput => process.StandardOutput;
    public StreamReader StandardError => process.StandardError;
    public StreamWriter StandardInput => process.StandardInput;
    TextReader IBuiltinAgentProcessSession.StandardOutput => StandardOutput;
    TextReader IBuiltinAgentProcessSession.StandardError => StandardError;
    TextWriter IBuiltinAgentProcessSession.StandardInput => StandardInput;
    public int ProcessId => process.Id;

    public async Task<int> WaitForExitAsync(
        CancellationToken cancellationToken,
        TimeSpan? timeout = null)
    {
        var effectiveTimeout = timeout ?? DefaultTaskTimeout;
        if (effectiveTimeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        using var timeoutCancellation = new CancellationTokenSource(effectiveTimeout);
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutCancellation.Token);
        try
        {
            await process.WaitForExitAsync(linkedCancellation.Token).ConfigureAwait(false);
            return process.ExitCode;
        }
        catch (OperationCanceledException) when (timeoutCancellation.IsCancellationRequested
                                                && !cancellationToken.IsCancellationRequested)
        {
            await CancelAsync().ConfigureAwait(false);
            throw new TimeoutException("agent_task_timeout");
        }
        catch (OperationCanceledException)
        {
            await CancelAsync().ConfigureAwait(false);
            throw;
        }
    }

    /// <summary>Drains stderr without returning model/provider text to logs.</summary>
    public async Task<BuiltinAgentStderrSummary> DrainStandardErrorAsync(
        CancellationToken cancellationToken)
    {
        var buffer = new char[1024];
        var count = 0;
        var hasContent = false;
        while (await process.StandardError.ReadAsync(buffer, cancellationToken).ConfigureAwait(false) is var read
               && read > 0)
        {
            hasContent = true;
            count = Math.Min(16_384, count + read);
        }
        return new BuiltinAgentStderrSummary(hasContent, count == 16_384);
    }

    /// <summary>
    /// Cancellation is terminal for a task: close stdin so a well-behaved
    /// sidecar can stop, then kill its complete process tree so no child is
    /// left behind if it does not cooperate.
    /// </summary>
    public async Task CancelAsync()
    {
        try
        {
            process.StandardInput.Close();
        }
        catch (InvalidOperationException)
        {
            // The process may have already completed and closed its pipe.
        }

        if (!process.HasExited)
        {
            TryKillProcessTree(process);
            await process.WaitForExitAsync().ConfigureAwait(false);
        }
    }

    public async ValueTask DisposeAsync()
    {
        await CancelAsync().ConfigureAwait(false);
        process.Dispose();
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
            // Exit can race the cancellation path. It is already terminal.
        }
    }
}

public sealed record BuiltinAgentStderrSummary(bool HasContent, bool WasTruncated);
