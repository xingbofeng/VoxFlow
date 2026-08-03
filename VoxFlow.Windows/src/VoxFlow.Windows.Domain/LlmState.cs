using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum LlmProviderId
{
    [JsonStringEnumMemberName("openai")]
    OpenAI,
}

public enum LlmAvailability
{
    [JsonStringEnumMemberName("notConfigured")]
    NotConfigured,

    [JsonStringEnumMemberName("disabled")]
    Disabled,

    [JsonStringEnumMemberName("testing")]
    Testing,

    [JsonStringEnumMemberName("ready")]
    Ready,

    [JsonStringEnumMemberName("failed")]
    Failed,
}

public sealed record LlmState
{
    [JsonConstructor]
    public LlmState(
        LlmAvailability availability,
        string? model,
        VoxFlowErrorCode? errorCode)
    {
        if (availability == LlmAvailability.NotConfigured)
        {
            if (model is not null || errorCode is not null)
            {
                throw new ArgumentException(
                    "An unconfigured LLM cannot have a model or error.");
            }
        }
        else if (string.IsNullOrWhiteSpace(model))
        {
            throw new ArgumentException(
                "A configured LLM requires a model identifier.",
                nameof(model));
        }

        if (availability == LlmAvailability.Failed && errorCode is null)
        {
            throw new ArgumentException(
                "A failed LLM state requires a safe error code.",
                nameof(errorCode));
        }

        if (availability != LlmAvailability.Failed && errorCode is not null)
        {
            throw new ArgumentException(
                "Only a failed LLM state may carry an error code.",
                nameof(errorCode));
        }

        Availability = availability;
        Model = model;
        ErrorCode = errorCode;
    }

    public LlmAvailability Availability { get; }

    public string? Model { get; }

    public VoxFlowErrorCode? ErrorCode { get; }
}
