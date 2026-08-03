using System.Diagnostics;
using System.Security.Cryptography;
using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentProcessSessionTests
{
    [Fact]
    public async Task Cancellation_closes_stdin_and_kills_a_long_running_process_tree()
    {
        using var process = StartLongRunningCommand();
        await using var session = new BuiltinAgentProcessSession(process);

        await session.CancelAsync();

        Assert.True(process.HasExited);
    }

    [Fact]
    public async Task Timeout_kills_the_process_and_returns_a_safe_timeout_code()
    {
        using var process = StartLongRunningCommand();
        await using var session = new BuiltinAgentProcessSession(process);

        var exception = await Assert.ThrowsAsync<TimeoutException>(() =>
            session.WaitForExitAsync(CancellationToken.None, TimeSpan.FromMilliseconds(100)));

        Assert.Equal("agent_task_timeout", exception.Message);
        Assert.True(process.HasExited);
    }

    [Fact]
    public async Task Disposal_uses_the_same_terminal_cleanup_as_application_shutdown()
    {
        var process = StartLongRunningCommand();
        var processId = process.Id;

        await using (var session = new BuiltinAgentProcessSession(process))
        {
        }

        Assert.False(IsRunning(processId));
    }

    [Fact]
    public async Task Each_agent_task_starts_an_independent_verified_process()
    {
        var binary = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(binary)));
        var host = new BuiltinAgentProcessHost(new BuiltinAgentProcessSpecification(
            new BuiltinAgentBinaryDescriptor(binary, hash)));

        await using var first = await host.StartAsync(Request("task-1"), CancellationToken.None);
        await using var second = await host.StartAsync(Request("task-2"), CancellationToken.None);

        Assert.NotEqual(first.ProcessId, second.ProcessId);
    }

    private static Process StartLongRunningCommand()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        var process = Process.Start(new ProcessStartInfo
        {
            FileName = command,
            Arguments = "/c ping 127.0.0.1 -n 60 > nul",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        });

        return process ?? throw new InvalidOperationException("Could not start test process.");
    }

    private static BuiltinAgentSidecarRunRequest Request(string taskId) => new(
        taskId,
        "instruction",
        new BuiltinAgentSidecarProviderConfig("provider", "https://example.test", "model", "secret", 30),
        [new BuiltinAgentSidecarContentPart("context")],
        new BuiltinAgentSidecarLoopLimits());

    private static bool IsRunning(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }
}
