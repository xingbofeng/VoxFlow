using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public interface IAgentUrlLauncher
{
    bool TryOpen(Uri uri);
}

public sealed class BuiltinAgentOpenUrlToolHost
{
    private readonly AgentToolAuthorizationPolicy authorization;
    private readonly IAgentUrlLauncher launcher;

    public BuiltinAgentOpenUrlToolHost(
        AgentToolAuthorizationPolicy authorization,
        IAgentUrlLauncher launcher)
    {
        this.authorization = authorization ?? throw new ArgumentNullException(nameof(authorization));
        this.launcher = launcher ?? throw new ArgumentNullException(nameof(launcher));
    }

    public Task<AgentToolResult> ExecuteAsync(
        AgentToolCall call,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        cancellationToken.ThrowIfCancellationRequested();
        if (!call.Arguments.TryGetProperty("url", out var value)
            || value.ValueKind != JsonValueKind.String
            || !Uri.TryCreate(value.GetString(), UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https"))
        {
            return Task.FromResult(AgentToolResult.Failure(call.Name, "invalid_url"));
        }
        if (!authorization.AllowsOpenUrl(uri))
        {
            return Task.FromResult(AgentToolResult.Failure(call.Name, "user_intent_required"));
        }
        return Task.FromResult(launcher.TryOpen(uri)
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
            {
                action = "open_url",
                url = uri.AbsoluteUri,
            }))
            : AgentToolResult.Failure(call.Name, "open_url_failed"));
    }
}
