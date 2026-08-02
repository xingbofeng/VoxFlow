using System.Text.Json.Serialization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public static class BuiltinAgentSidecarProtocol
{
    public const int CurrentSchemaVersion = 1;
}

public sealed class BuiltinAgentSidecarProviderConfig
{
    [JsonConstructor]
    public BuiltinAgentSidecarProviderConfig(
        string providerId,
        string baseUrl,
        string model,
        string apiKey,
        int timeoutSeconds)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);
        ArgumentException.ThrowIfNullOrWhiteSpace(baseUrl);
        ArgumentException.ThrowIfNullOrWhiteSpace(model);
        ArgumentNullException.ThrowIfNull(apiKey);
        if (timeoutSeconds is < 1 or > 600)
        {
            throw new ArgumentOutOfRangeException(nameof(timeoutSeconds));
        }

        ProviderId = providerId;
        BaseUrl = baseUrl;
        Model = model;
        ApiKey = apiKey;
        TimeoutSeconds = timeoutSeconds;
    }

    public string ProviderId { get; }

    public string BaseUrl { get; }

    public string Model { get; }

    public string ApiKey { get; }

    public int TimeoutSeconds { get; }

    public override string ToString() =>
        $"BuiltinAgentSidecarProviderConfig {{ ProviderId = {ProviderId}, Model = {Model}, ApiKey = [REDACTED] }}";
}

public sealed class BuiltinAgentSidecarContentPart
{
    [JsonConstructor]
    public BuiltinAgentSidecarContentPart(string text, string type = "text")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        if (!string.Equals(type, "text", StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "Only text content parts are supported.",
                nameof(type));
        }

        Type = type;
        Text = text;
    }

    public string Type { get; }

    public string Text { get; }
}

public sealed class BuiltinAgentSidecarLoopLimits
{
    [JsonConstructor]
    public BuiltinAgentSidecarLoopLimits(
        int maxSteps = 12,
        int maxToolCalls = 10,
        int maxRepeatedToolCalls = 2)
    {
        if (maxSteps <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxSteps));
        }
        if (maxToolCalls <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxToolCalls));
        }
        if (maxRepeatedToolCalls <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxRepeatedToolCalls));
        }

        MaxSteps = maxSteps;
        MaxToolCalls = maxToolCalls;
        MaxRepeatedToolCalls = maxRepeatedToolCalls;
    }

    public int MaxSteps { get; }

    public int MaxToolCalls { get; }

    public int MaxRepeatedToolCalls { get; }
}

public sealed class BuiltinAgentSidecarRunRequest
{
    [JsonConstructor]
    public BuiltinAgentSidecarRunRequest(
        string taskId,
        string instruction,
        BuiltinAgentSidecarProviderConfig provider,
        IReadOnlyList<BuiltinAgentSidecarContentPart> content,
        BuiltinAgentSidecarLoopLimits limits,
        string? workspaceDirectory = null,
        int schemaVersion = BuiltinAgentSidecarProtocol.CurrentSchemaVersion)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(schemaVersion);
        ArgumentException.ThrowIfNullOrWhiteSpace(taskId);
        ArgumentException.ThrowIfNullOrWhiteSpace(instruction);
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(content);
        ArgumentNullException.ThrowIfNull(limits);
        if (content.Count == 0)
        {
            throw new ArgumentException(
                "A sidecar request requires at least one content part.",
                nameof(content));
        }

        SchemaVersion = schemaVersion;
        TaskId = taskId;
        Instruction = instruction;
        WorkspaceDirectory = string.IsNullOrWhiteSpace(workspaceDirectory)
            ? null
            : Path.GetFullPath(workspaceDirectory);
        Provider = provider;
        Content = Array.AsReadOnly(content.ToArray());
        Limits = limits;
    }

    public int SchemaVersion { get; }

    public string TaskId { get; }

    public string Instruction { get; }

    public string? WorkspaceDirectory { get; }

    public BuiltinAgentSidecarProviderConfig Provider { get; }

    public IReadOnlyList<BuiltinAgentSidecarContentPart> Content { get; }

    public BuiltinAgentSidecarLoopLimits Limits { get; }

    public override string ToString() =>
        $"BuiltinAgentSidecarRunRequest {{ SchemaVersion = {SchemaVersion}, TaskId = {TaskId}, Provider = {Provider.ProviderId} }}";
}

public sealed class BuiltinAgentSidecarEvent
{
    [JsonConstructor]
    public BuiltinAgentSidecarEvent(
        string @event,
        int schemaVersion = BuiltinAgentSidecarProtocol.CurrentSchemaVersion,
        int? step = null,
        string? text = null,
        AgentToolCall? toolCall = null,
        string? toolName = null,
        AgentToolResult? result = null,
        string? summary = null,
        string? reason = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(schemaVersion);
        ArgumentException.ThrowIfNullOrWhiteSpace(@event);

        SchemaVersion = schemaVersion;
        Event = @event;
        Step = step;
        Text = text;
        ToolCall = toolCall;
        ToolName = toolName;
        Result = result;
        Summary = summary;
        Reason = reason;
    }

    public int SchemaVersion { get; }

    [JsonPropertyName("event")]
    public string Event { get; }

    public int? Step { get; }

    public string? Text { get; }

    public AgentToolCall? ToolCall { get; }

    public string? ToolName { get; }

    public AgentToolResult? Result { get; }

    public string? Summary { get; }

    public string? Reason { get; }

    [JsonIgnore]
    public SchemaCompatibility SchemaCompatibility =>
        SchemaVersion switch
        {
            < BuiltinAgentSidecarProtocol.CurrentSchemaVersion => SchemaCompatibility.Legacy,
            BuiltinAgentSidecarProtocol.CurrentSchemaVersion => SchemaCompatibility.Current,
            > BuiltinAgentSidecarProtocol.CurrentSchemaVersion => SchemaCompatibility.Newer,
        };

    public override string ToString() =>
        $"BuiltinAgentSidecarEvent {{ SchemaVersion = {SchemaVersion}, Event = {Event} }}";
}
