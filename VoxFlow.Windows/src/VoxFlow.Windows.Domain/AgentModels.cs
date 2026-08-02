using System.Text.Json;
using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum SchemaCompatibility
{
    Legacy,
    Current,
    Newer,
}

public static class AgentTraceSchema
{
    public const int CurrentVersion = 1;

    public static SchemaCompatibility Classify(int schemaVersion) =>
        schemaVersion switch
        {
            < CurrentVersion => SchemaCompatibility.Legacy,
            CurrentVersion => SchemaCompatibility.Current,
            > CurrentVersion => SchemaCompatibility.Newer,
        };
}

public enum AgentExecutionMode
{
    [JsonStringEnumMemberName("builtinAgent")]
    BuiltinAgent,
}

public enum AgentActionEventKind
{
    [JsonStringEnumMemberName("turnStarted")]
    TurnStarted,

    [JsonStringEnumMemberName("modelDelta")]
    ModelDelta,

    [JsonStringEnumMemberName("planUpdated")]
    PlanUpdated,

    [JsonStringEnumMemberName("toolRequested")]
    ToolRequested,

    [JsonStringEnumMemberName("toolProgress")]
    ToolProgress,

    [JsonStringEnumMemberName("toolResolved")]
    ToolResolved,

    [JsonStringEnumMemberName("tokenUsageUpdated")]
    TokenUsageUpdated,

    [JsonStringEnumMemberName("turnCompleted")]
    TurnCompleted,

    [JsonStringEnumMemberName("warning")]
    Warning,

    [JsonStringEnumMemberName("error")]
    Error,
}

public enum AgentArtifactKind
{
    [JsonStringEnumMemberName("file")]
    File,

    [JsonStringEnumMemberName("directory")]
    Directory,
}

public sealed class AgentTokenUsage
{
    [JsonConstructor]
    public AgentTokenUsage(
        int? inputTokens,
        int? outputTokens,
        int? totalTokens)
    {
        ValidateNullableCount(inputTokens, nameof(inputTokens));
        ValidateNullableCount(outputTokens, nameof(outputTokens));
        ValidateNullableCount(totalTokens, nameof(totalTokens));

        InputTokens = inputTokens;
        OutputTokens = outputTokens;
        TotalTokens = totalTokens;
    }

    public int? InputTokens { get; }

    public int? OutputTokens { get; }

    public int? TotalTokens { get; }

    private static void ValidateNullableCount(int? value, string parameterName)
    {
        if (value is < 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }
}

public sealed class AgentArtifact
{
    [JsonConstructor]
    public AgentArtifact(
        string id,
        AgentArtifactKind kind,
        string path,
        string? summary,
        long? updatedAtUnixMs)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ValidateEnum(kind, nameof(kind));
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (updatedAtUnixMs is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(updatedAtUnixMs));
        }

        Id = id;
        Kind = kind;
        Path = path;
        Summary = summary;
        UpdatedAtUnixMs = updatedAtUnixMs;
    }

    public string Id { get; }

    public AgentArtifactKind Kind { get; }

    public string Path { get; }

    public string? Summary { get; }

    public long? UpdatedAtUnixMs { get; }

    public override string ToString() => $"AgentArtifact {{ Id = {Id}, Kind = {Kind} }}";

    private static void ValidateEnum<T>(T value, string parameterName)
        where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}

public sealed class AgentScreenContextMetadata
{
    [JsonConstructor]
    public AgentScreenContextMetadata(
        string? appName,
        string? processName,
        string? windowTitle,
        IReadOnlyList<string>? sources,
        IReadOnlyList<string>? warnings,
        long? capturedAtUnixMs)
    {
        if (capturedAtUnixMs is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(capturedAtUnixMs));
        }

        AppName = appName;
        ProcessName = processName;
        WindowTitle = windowTitle;
        Sources = Freeze(sources);
        Warnings = Freeze(warnings);
        CapturedAtUnixMs = capturedAtUnixMs;
    }

    public string? AppName { get; }

    public string? ProcessName { get; }

    public string? WindowTitle { get; }

    public IReadOnlyList<string> Sources { get; }

    public IReadOnlyList<string> Warnings { get; }

    public long? CapturedAtUnixMs { get; }

    private static IReadOnlyList<string> Freeze(IReadOnlyList<string>? values) =>
        Array.AsReadOnly((values ?? []).ToArray());
}

public sealed class AgentActionEvent
{
    [JsonConstructor]
    public AgentActionEvent(
        string id,
        AgentActionEventKind kind,
        string title,
        string? detail,
        long timestampUnixMs,
        long? elapsedMs,
        string? toolName,
        bool isFailure)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        if (!Enum.IsDefined(kind))
        {
            throw new ArgumentOutOfRangeException(nameof(kind), kind, null);
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        ArgumentOutOfRangeException.ThrowIfNegative(timestampUnixMs);
        if (elapsedMs is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(elapsedMs));
        }

        Id = id;
        Kind = kind;
        Title = title;
        Detail = detail;
        TimestampUnixMs = timestampUnixMs;
        ElapsedMs = elapsedMs;
        ToolName = toolName;
        IsFailure = isFailure;
    }

    public string Id { get; }

    public AgentActionEventKind Kind { get; }

    public string Title { get; }

    public string? Detail { get; }

    public long TimestampUnixMs { get; }

    public long? ElapsedMs { get; }

    public string? ToolName { get; }

    public bool IsFailure { get; }

    public override string ToString() =>
        $"AgentActionEvent {{ Id = {Id}, Kind = {Kind}, IsFailure = {IsFailure} }}";
}

public sealed class AgentActionTrace
{
    [JsonConstructor]
    public AgentActionTrace(
        string providerId,
        AgentExecutionMode executionMode,
        WorkflowTaskStatus status,
        string userInstruction,
        long startedAtUnixMs,
        int schemaVersion = AgentTraceSchema.CurrentVersion,
        AgentScreenContextMetadata? screenContext = null,
        IReadOnlyList<AgentActionEvent>? events = null,
        string? resultSummary = null,
        string? model = null,
        AgentTokenUsage? tokenUsage = null,
        IReadOnlyList<AgentArtifact>? artifacts = null,
        long? completedAtUnixMs = null,
        string? failureReason = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(schemaVersion);
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);
        ValidateEnum(executionMode, nameof(executionMode));
        ValidateEnum(status, nameof(status));
        ArgumentException.ThrowIfNullOrWhiteSpace(userInstruction);
        ArgumentOutOfRangeException.ThrowIfNegative(startedAtUnixMs);
        if (completedAtUnixMs is < 0 || completedAtUnixMs < startedAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(completedAtUnixMs));
        }

        SchemaVersion = schemaVersion;
        ProviderId = providerId;
        ExecutionMode = executionMode;
        Status = status;
        UserInstruction = userInstruction;
        ScreenContext = screenContext;
        Events = Array.AsReadOnly((events ?? []).ToArray());
        ResultSummary = resultSummary;
        Model = model;
        TokenUsage = tokenUsage;
        Artifacts = Array.AsReadOnly((artifacts ?? []).ToArray());
        StartedAtUnixMs = startedAtUnixMs;
        CompletedAtUnixMs = completedAtUnixMs;
        FailureReason = failureReason;
    }

    public int SchemaVersion { get; }

    public string ProviderId { get; }

    public AgentExecutionMode ExecutionMode { get; }

    public WorkflowTaskStatus Status { get; }

    public string UserInstruction { get; }

    public AgentScreenContextMetadata? ScreenContext { get; }

    public IReadOnlyList<AgentActionEvent> Events { get; }

    public string? ResultSummary { get; }

    public string? Model { get; }

    public AgentTokenUsage? TokenUsage { get; }

    public IReadOnlyList<AgentArtifact> Artifacts { get; }

    public long StartedAtUnixMs { get; }

    public long? CompletedAtUnixMs { get; }

    public string? FailureReason { get; }

    [JsonIgnore]
    public SchemaCompatibility SchemaCompatibility =>
        AgentTraceSchema.Classify(SchemaVersion);

    public override string ToString() =>
        $"AgentActionTrace {{ SchemaVersion = {SchemaVersion}, ProviderId = {ProviderId}, Status = {Status} }}";

    private static void ValidateEnum<T>(T value, string parameterName)
        where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}

public sealed class AgentToolCall
{
    [JsonConstructor]
    public AgentToolCall(string id, string name, JsonElement arguments)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        if (arguments.ValueKind != JsonValueKind.Object)
        {
            throw new ArgumentException(
                "Tool arguments must be a JSON object.",
                nameof(arguments));
        }

        Id = id;
        Name = name;
        Arguments = arguments.Clone();
    }

    public string Id { get; }

    public string Name { get; }

    public JsonElement Arguments { get; }

    public override string ToString() => $"AgentToolCall {{ Id = {Id}, Name = {Name} }}";
}

public sealed class AgentToolError
{
    [JsonConstructor]
    public AgentToolError(string code, string? message = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(code);
        Code = code;
        Message = message;
    }

    public string Code { get; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Message { get; }
}

public sealed class AgentToolResult
{
    [JsonConstructor]
    public AgentToolResult(
        bool ok,
        string toolName,
        JsonElement? result = null,
        AgentToolError? error = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(toolName);
        if (ok && error is not null)
        {
            throw new ArgumentException(
                "A successful tool result cannot contain an error.",
                nameof(error));
        }
        if (!ok && error is null)
        {
            throw new ArgumentException(
                "A failed tool result requires an error.",
                nameof(error));
        }
        if (result is { ValueKind: not JsonValueKind.Object and not JsonValueKind.Array
            and not JsonValueKind.String and not JsonValueKind.Number
            and not JsonValueKind.True and not JsonValueKind.False
            and not JsonValueKind.Null })
        {
            throw new ArgumentException("The tool result contains invalid JSON.", nameof(result));
        }

        Ok = ok;
        ToolName = toolName;
        Result = result?.Clone();
        Error = error;
    }

    public bool Ok { get; }

    public string ToolName { get; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonElement? Result { get; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public AgentToolError? Error { get; }

    public static AgentToolResult Success(
        string toolName,
        JsonElement? result = null) => new(true, toolName, result);

    public static AgentToolResult Failure(
        string toolName,
        string code,
        string? message = null) => new(
            false,
            toolName,
            error: new AgentToolError(code, message));

    public override string ToString() =>
        $"AgentToolResult {{ Ok = {Ok}, ToolName = {ToolName}, ErrorCode = {Error?.Code} }}";
}
