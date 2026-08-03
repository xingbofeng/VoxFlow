namespace VoxFlow.Windows.Application.Llm;

public enum LlmProviderType
{
    OpenAiCompatible,
}

public enum LlmProviderHealthStatus
{
    Unknown,
    Testing,
    Ok,
    Error,
}

public sealed class LlmProviderRecord
{
    public LlmProviderRecord(
        string id,
        string displayName,
        LlmProviderType providerType,
        Uri? baseUri,
        string? defaultModel,
        string? apiKeyRef,
        double temperature,
        int timeoutSeconds,
        bool enabled,
        bool isDefault,
        LlmProviderHealthStatus healthStatus,
        string? healthMessage,
        long? healthLatencyMs,
        long? healthCheckedAtUnixMs,
        LlmAgentCapabilityStatus agentCapabilityStatus,
        string? agentCapabilityMessage,
        long? agentCapabilityCheckedAtUnixMs,
        long createdAtUnixMs,
        long updatedAtUnixMs)
    {
        ValidateSingleLine(id, nameof(id));
        ValidateSingleLine(displayName, nameof(displayName));
        ValidateEnum(providerType, nameof(providerType));
        ValidateEndpoint(baseUri, nameof(baseUri));
        ValidateOptionalSingleLine(defaultModel, nameof(defaultModel));
        ValidateOptionalSingleLine(apiKeyRef, nameof(apiKeyRef));
        if (!double.IsFinite(temperature) || temperature is < 0 or > 2)
        {
            throw new ArgumentOutOfRangeException(nameof(temperature));
        }
        if (timeoutSeconds is < 1 or > 600)
        {
            throw new ArgumentOutOfRangeException(nameof(timeoutSeconds));
        }
        if (isDefault && !enabled)
        {
            throw new ArgumentException(
                "A disabled provider cannot be the default.",
                nameof(isDefault));
        }
        ValidateEnum(healthStatus, nameof(healthStatus));
        ValidateNullableTimestamp(healthLatencyMs, nameof(healthLatencyMs));
        ValidateNullableTimestamp(healthCheckedAtUnixMs, nameof(healthCheckedAtUnixMs));
        ValidateEnum(agentCapabilityStatus, nameof(agentCapabilityStatus));
        ValidateNullableTimestamp(
            agentCapabilityCheckedAtUnixMs,
            nameof(agentCapabilityCheckedAtUnixMs));
        ArgumentOutOfRangeException.ThrowIfNegative(createdAtUnixMs);
        if (updatedAtUnixMs < createdAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(updatedAtUnixMs));
        }

        Id = id.Trim();
        DisplayName = displayName.Trim();
        ProviderType = providerType;
        BaseUri = baseUri is null
            ? null
            : new Uri(baseUri.AbsoluteUri.TrimEnd('/'), UriKind.Absolute);
        DefaultModel = defaultModel?.Trim();
        ApiKeyRef = apiKeyRef?.Trim();
        Temperature = temperature;
        TimeoutSeconds = timeoutSeconds;
        Enabled = enabled;
        IsDefault = isDefault;
        HealthStatus = healthStatus;
        HealthMessage = healthMessage;
        HealthLatencyMs = healthLatencyMs;
        HealthCheckedAtUnixMs = healthCheckedAtUnixMs;
        AgentCapabilityStatus = agentCapabilityStatus;
        AgentCapabilityMessage = agentCapabilityMessage;
        AgentCapabilityCheckedAtUnixMs = agentCapabilityCheckedAtUnixMs;
        CreatedAtUnixMs = createdAtUnixMs;
        UpdatedAtUnixMs = updatedAtUnixMs;
    }

    public string Id { get; }

    public string DisplayName { get; }

    public LlmProviderType ProviderType { get; }

    public Uri? BaseUri { get; }

    public string? DefaultModel { get; }

    public string? ApiKeyRef { get; }

    public double Temperature { get; }

    public int TimeoutSeconds { get; }

    public bool Enabled { get; }

    public bool IsDefault { get; }

    public LlmProviderHealthStatus HealthStatus { get; }

    public string? HealthMessage { get; }

    public long? HealthLatencyMs { get; }

    public long? HealthCheckedAtUnixMs { get; }

    public LlmAgentCapabilityStatus AgentCapabilityStatus { get; }

    public string? AgentCapabilityMessage { get; }

    public long? AgentCapabilityCheckedAtUnixMs { get; }

    public long CreatedAtUnixMs { get; }

    public long UpdatedAtUnixMs { get; }

    public override string ToString() =>
        $"LlmProviderRecord {{ Id = {Id}, DisplayName = {DisplayName}, Enabled = {Enabled}, IsDefault = {IsDefault}, ApiKeyRef = [REDACTED] }}";

    private static void ValidateEndpoint(Uri? value, string parameterName)
    {
        if (value is null)
        {
            return;
        }
        if (!value.IsAbsoluteUri
            || (!string.Equals(value.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
                && !(string.Equals(value.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)
                    && value.IsLoopback)))
        {
            throw new ArgumentException(
                "A remote provider requires HTTPS; HTTP is allowed only for loopback hosts.",
                parameterName);
        }
    }

    private static void ValidateSingleLine(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (value.Contains('\r', StringComparison.Ordinal)
            || value.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException("The value must be a single line.", parameterName);
        }
    }

    private static void ValidateOptionalSingleLine(string? value, string parameterName)
    {
        if (value is null)
        {
            return;
        }
        ValidateSingleLine(value, parameterName);
    }

    private static void ValidateNullableTimestamp(long? value, string parameterName)
    {
        if (value is < 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
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

public sealed class LlmProviderHealthUpdate
{
    public LlmProviderHealthUpdate(
        LlmProviderHealthStatus status,
        string? safeMessage,
        long? latencyMs,
        long checkedAtUnixMs,
        long updatedAtUnixMs)
    {
        if (!Enum.IsDefined(status))
        {
            throw new ArgumentOutOfRangeException(nameof(status), status, null);
        }
        if (latencyMs is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(latencyMs));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(checkedAtUnixMs);
        if (updatedAtUnixMs < checkedAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(updatedAtUnixMs));
        }

        Status = status;
        SafeMessage = safeMessage;
        LatencyMs = latencyMs;
        CheckedAtUnixMs = checkedAtUnixMs;
        UpdatedAtUnixMs = updatedAtUnixMs;
    }

    public LlmProviderHealthStatus Status { get; }

    public string? SafeMessage { get; }

    public long? LatencyMs { get; }

    public long CheckedAtUnixMs { get; }

    public long UpdatedAtUnixMs { get; }
}

public sealed class LlmAgentCapabilityUpdate
{
    public LlmAgentCapabilityUpdate(
        LlmAgentCapabilityStatus status,
        string? safeMessage,
        long checkedAtUnixMs,
        long updatedAtUnixMs)
    {
        if (!Enum.IsDefined(status))
        {
            throw new ArgumentOutOfRangeException(nameof(status), status, null);
        }
        ArgumentOutOfRangeException.ThrowIfNegative(checkedAtUnixMs);
        if (updatedAtUnixMs < checkedAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(updatedAtUnixMs));
        }

        Status = status;
        SafeMessage = safeMessage;
        CheckedAtUnixMs = checkedAtUnixMs;
        UpdatedAtUnixMs = updatedAtUnixMs;
    }

    public LlmAgentCapabilityStatus Status { get; }

    public string? SafeMessage { get; }

    public long CheckedAtUnixMs { get; }

    public long UpdatedAtUnixMs { get; }
}

public interface ILlmProviderRepository
{
    IReadOnlyList<LlmProviderRecord> List();

    LlmProviderRecord? Get(string providerId);

    LlmProviderRecord? GetDefault();

    void Upsert(LlmProviderRecord provider);

    bool Delete(string providerId);

    bool SetEnabled(string providerId, bool enabled, long updatedAtUnixMs);

    bool SetDefault(string providerId, long updatedAtUnixMs);

    bool UpdateHealth(string providerId, LlmProviderHealthUpdate update);

    bool UpdateAgentCapability(string providerId, LlmAgentCapabilityUpdate update);
}
