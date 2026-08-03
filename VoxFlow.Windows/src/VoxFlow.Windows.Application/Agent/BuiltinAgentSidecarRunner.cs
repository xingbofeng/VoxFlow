using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public interface IBuiltinAgentProcessSession : IAsyncDisposable
{
    TextReader StandardOutput { get; }

    TextReader StandardError { get; }

    TextWriter StandardInput { get; }

    Task<int> WaitForExitAsync(CancellationToken cancellationToken, TimeSpan? timeout = null);

    Task<BuiltinAgentStderrSummary> DrainStandardErrorAsync(CancellationToken cancellationToken);

    Task CancelAsync();
}

public interface IBuiltinAgentProcessSessionFactory
{
    Task<IBuiltinAgentProcessSession> StartAsync(
        BuiltinAgentSidecarRunRequest request,
        CancellationToken cancellationToken);
}

public sealed class BuiltinAgentProcessSessionFactory : IBuiltinAgentProcessSessionFactory
{
    private readonly BuiltinAgentProcessHost host;

    public BuiltinAgentProcessSessionFactory(BuiltinAgentProcessHost host) =>
        this.host = host ?? throw new ArgumentNullException(nameof(host));

    public async Task<IBuiltinAgentProcessSession> StartAsync(
        BuiltinAgentSidecarRunRequest request,
        CancellationToken cancellationToken) =>
        await host.StartAsync(request, cancellationToken).ConfigureAwait(false);
}

public sealed record BuiltinAgentSidecarRunOutcome(
    bool Succeeded,
    string? SafeFailureCode,
    int? ExitCode,
    BuiltinAgentStderrSummary Stderr);

/// <summary>
/// Owns a complete one-task JSONL session. It starts stderr draining before
/// stdout processing, rejects malformed/late protocol data, and always tears
/// down the complete sidecar process tree on cancellation or failure.
/// </summary>
public sealed class BuiltinAgentSidecarRunner
{
    private readonly IBuiltinAgentProcessSessionFactory sessionFactory;
    private readonly BuiltinAgentJsonlPump pump;

    public BuiltinAgentSidecarRunner(
        IBuiltinAgentProcessSessionFactory sessionFactory,
        BuiltinAgentJsonlPump? pump = null)
    {
        this.sessionFactory = sessionFactory ?? throw new ArgumentNullException(nameof(sessionFactory));
        this.pump = pump ?? new BuiltinAgentJsonlPump();
    }

    public async Task<BuiltinAgentSidecarRunOutcome> RunAsync(
        BuiltinAgentSidecarRunRequest request,
        Func<BuiltinAgentSidecarEvent, Task> onEvent,
        Func<AgentToolCall, CancellationToken, Task<AgentToolResult>> executeTool,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(onEvent);
        ArgumentNullException.ThrowIfNull(executeTool);

        await using var session = await sessionFactory.StartAsync(request, cancellationToken)
            .ConfigureAwait(false);
        var stderrTask = session.DrainStandardErrorAsync(CancellationToken.None);
        try
        {
            await pump.PumpAsync(
                    session.StandardOutput,
                    session.StandardInput,
                    onEvent,
                    executeTool,
                    cancellationToken)
                .ConfigureAwait(false);
            var exitCode = await session.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            var stderr = await stderrTask.ConfigureAwait(false);
            return exitCode == 0
                ? new(true, null, exitCode, stderr)
                : new(false, "sidecar_exit_failure", exitCode, stderr);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await session.CancelAsync().ConfigureAwait(false);
            return new(false, "cancelled", null, await stderrTask.ConfigureAwait(false));
        }
        catch (TimeoutException)
        {
            await session.CancelAsync().ConfigureAwait(false);
            return new(false, "agent_task_timeout", null, await stderrTask.ConfigureAwait(false));
        }
        catch (BuiltinAgentSidecarProtocolException)
        {
            await session.CancelAsync().ConfigureAwait(false);
            return new(false, "sidecar_protocol_failure", null, await stderrTask.ConfigureAwait(false));
        }
        catch
        {
            await session.CancelAsync().ConfigureAwait(false);
            return new(false, "sidecar_runtime_failure", null, await stderrTask.ConfigureAwait(false));
        }
    }
}
