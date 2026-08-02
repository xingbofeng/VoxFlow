using System.Text.Json;
using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

/// <summary>
/// Interactive work that competes for the foreground workflow lease. Dictation
/// participates in mutual exclusion but continues to use its existing history
/// model instead of the workflow_tasks table.
/// </summary>
public enum InteractiveWorkflowKind
{
    [JsonStringEnumMemberName("dictation")]
    Dictation,

    [JsonStringEnumMemberName("selectionTranslation")]
    SelectionTranslation,

    [JsonStringEnumMemberName("selectionSummary")]
    SelectionSummary,

    [JsonStringEnumMemberName("agentCompose")]
    AgentCompose,

    [JsonStringEnumMemberName("screenshot")]
    Screenshot,
}

public enum WorkflowTaskKind
{
    [JsonStringEnumMemberName("selectionTranslation")]
    SelectionTranslation,

    [JsonStringEnumMemberName("selectionSummary")]
    SelectionSummary,

    [JsonStringEnumMemberName("agentCompose")]
    AgentCompose,
}

public enum WorkflowTaskStage
{
    [JsonStringEnumMemberName("capturingSelection")]
    CapturingSelection,

    [JsonStringEnumMemberName("recording")]
    Recording,

    [JsonStringEnumMemberName("transcribing")]
    Transcribing,

    [JsonStringEnumMemberName("collectingContext")]
    CollectingContext,

    [JsonStringEnumMemberName("processing")]
    Processing,

    [JsonStringEnumMemberName("waitingForUser")]
    WaitingForUser,

    [JsonStringEnumMemberName("operating")]
    Operating,

    [JsonStringEnumMemberName("outputting")]
    Outputting,

    [JsonStringEnumMemberName("completed")]
    Completed,
}

public enum WorkflowTaskStatus
{
    [JsonStringEnumMemberName("pending")]
    Pending,

    [JsonStringEnumMemberName("running")]
    Running,

    [JsonStringEnumMemberName("partiallyCompleted")]
    PartiallyCompleted,

    [JsonStringEnumMemberName("completed")]
    Completed,

    [JsonStringEnumMemberName("failed")]
    Failed,

    [JsonStringEnumMemberName("cancelled")]
    Cancelled,

    [JsonStringEnumMemberName("interrupted")]
    Interrupted,
}

public sealed class WorkflowTaskRecord
{
    public WorkflowTaskRecord(
        string id,
        WorkflowTaskKind kind,
        WorkflowTaskStage stage,
        WorkflowTaskStatus status,
        Guid generation,
        string? rawText,
        string? partialText,
        string? finalText,
        string? providerId,
        string? model,
        JsonElement? targetJson,
        JsonElement? contextJson,
        JsonElement? traceJson,
        JsonElement? outputJson,
        JsonElement? failureJson,
        JsonElement? warningsJson,
        long createdAtUnixMs,
        long updatedAtUnixMs,
        long? completedAtUnixMs)
    {
        ValidateSingleLine(id, nameof(id));
        ValidateEnum(kind, nameof(kind));
        ValidateEnum(stage, nameof(stage));
        ValidateEnum(status, nameof(status));
        if (generation == Guid.Empty)
        {
            throw new ArgumentException(
                "A non-empty workflow generation is required.",
                nameof(generation));
        }
        ValidateOptionalSingleLine(providerId, nameof(providerId));
        ValidateOptionalSingleLine(model, nameof(model));
        ArgumentOutOfRangeException.ThrowIfNegative(createdAtUnixMs);
        if (updatedAtUnixMs < createdAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(updatedAtUnixMs));
        }

        var terminal = IsTerminalStatus(status);
        if (terminal && completedAtUnixMs is null)
        {
            throw new ArgumentException(
                "A terminal workflow task requires a completion timestamp.",
                nameof(completedAtUnixMs));
        }
        if (!terminal && completedAtUnixMs is not null)
        {
            throw new ArgumentException(
                "An active workflow task cannot have a completion timestamp.",
                nameof(completedAtUnixMs));
        }
        if (completedAtUnixMs < createdAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(completedAtUnixMs));
        }
        if (status == WorkflowTaskStatus.Completed
            && stage != WorkflowTaskStage.Completed)
        {
            throw new ArgumentException(
                "A completed workflow must use the completed stage.",
                nameof(stage));
        }
        if (!terminal && stage == WorkflowTaskStage.Completed)
        {
            throw new ArgumentException(
                "An active workflow cannot use the completed stage.",
                nameof(stage));
        }

        Id = id.Trim();
        Kind = kind;
        Stage = stage;
        Status = status;
        Generation = generation;
        RawText = rawText;
        PartialText = partialText;
        FinalText = finalText;
        ProviderId = providerId?.Trim();
        Model = model?.Trim();
        TargetJson = CloneJson(targetJson, nameof(targetJson));
        ContextJson = CloneJson(contextJson, nameof(contextJson));
        TraceJson = CloneJson(traceJson, nameof(traceJson));
        OutputJson = CloneJson(outputJson, nameof(outputJson));
        FailureJson = CloneJson(failureJson, nameof(failureJson));
        WarningsJson = CloneJson(warningsJson, nameof(warningsJson));
        CreatedAtUnixMs = createdAtUnixMs;
        UpdatedAtUnixMs = updatedAtUnixMs;
        CompletedAtUnixMs = completedAtUnixMs;
    }

    public string Id { get; }

    public WorkflowTaskKind Kind { get; }

    public WorkflowTaskStage Stage { get; }

    public WorkflowTaskStatus Status { get; }

    public Guid Generation { get; }

    public string? RawText { get; }

    public string? PartialText { get; }

    public string? FinalText { get; }

    public string? ProviderId { get; }

    public string? Model { get; }

    public JsonElement? TargetJson { get; }

    public JsonElement? ContextJson { get; }

    public JsonElement? TraceJson { get; }

    public JsonElement? OutputJson { get; }

    public JsonElement? FailureJson { get; }

    public JsonElement? WarningsJson { get; }

    public long CreatedAtUnixMs { get; }

    public long UpdatedAtUnixMs { get; }

    public long? CompletedAtUnixMs { get; }

    public bool IsTerminal => IsTerminalStatus(Status);

    public override string ToString() =>
        $"WorkflowTaskRecord {{ Id = {Id}, Kind = {Kind}, Stage = {Stage}, Status = {Status}, Text = [REDACTED], Json = [REDACTED] }}";

    public static bool IsTerminalStatus(WorkflowTaskStatus status) => status is
        WorkflowTaskStatus.PartiallyCompleted
        or WorkflowTaskStatus.Completed
        or WorkflowTaskStatus.Failed
        or WorkflowTaskStatus.Cancelled
        or WorkflowTaskStatus.Interrupted;

    private static JsonElement? CloneJson(
        JsonElement? value,
        string parameterName)
    {
        if (value is null)
        {
            return null;
        }
        if (value.Value.ValueKind == JsonValueKind.Undefined)
        {
            throw new ArgumentException(
                "A defined JSON value is required.",
                parameterName);
        }
        return value.Value.Clone();
    }

    private static void ValidateOptionalSingleLine(
        string? value,
        string parameterName)
    {
        if (value is not null)
        {
            ValidateSingleLine(value, parameterName);
        }
    }

    private static void ValidateSingleLine(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (value.Contains('\r', StringComparison.Ordinal)
            || value.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "The value must be a single line.",
                parameterName);
        }
    }

    private static void ValidateEnum<T>(T value, string parameterName)
        where T : struct, Enum
    {
        if (!Enum.IsDefined(value))
        {
            throw new ArgumentOutOfRangeException(parameterName, value, null);
        }
    }
}
