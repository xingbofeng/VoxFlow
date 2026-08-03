using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Llm;

public enum LlmMessageRole
{
    System,
    User,
    Assistant,
    Tool,
}

public enum LlmModelDiscoverySource
{
    Remote,
    CatalogFallback,
    ManualOnly,
}

public enum LlmConnectionTestStatus
{
    Succeeded,
    Failed,
}

public enum LlmAgentCapabilityStatus
{
    Unknown,
    Supported,
    Unsupported,
    Error,
}

/// <summary>
/// A request-scoped immutable provider snapshot. Consumers resolve it once at
/// task start so changing the default provider cannot reroute an in-flight
/// request. Secret-bearing diagnostics are always redacted.
/// </summary>
public sealed class LlmProviderClientConfiguration
{
    public LlmProviderClientConfiguration(
        string providerId,
        Uri baseUri,
        string model,
        string? apiKey,
        double temperature,
        TimeSpan timeout)
    {
        ValidateSingleLine(providerId, nameof(providerId));
        ArgumentNullException.ThrowIfNull(baseUri);
        ValidateSingleLine(model, nameof(model));
        if (!baseUri.IsAbsoluteUri
            || (!string.Equals(
                    baseUri.Scheme,
                    Uri.UriSchemeHttps,
                    StringComparison.OrdinalIgnoreCase)
                && !(string.Equals(
                        baseUri.Scheme,
                        Uri.UriSchemeHttp,
                        StringComparison.OrdinalIgnoreCase)
                    && baseUri.IsLoopback)))
        {
            throw new ArgumentException(
                "A remote provider requires HTTPS; HTTP is allowed only for loopback hosts.",
                nameof(baseUri));
        }

        if (!double.IsFinite(temperature) || temperature is < 0 or > 2)
        {
            throw new ArgumentOutOfRangeException(nameof(temperature));
        }
        if (timeout < TimeSpan.FromSeconds(1)
            || timeout > TimeSpan.FromSeconds(600))
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        ProviderId = providerId.Trim();
        BaseUri = new Uri(baseUri.AbsoluteUri.TrimEnd('/'), UriKind.Absolute);
        Model = model.Trim();
        ApiKey = apiKey;
        Temperature = temperature;
        Timeout = timeout;
    }

    public string ProviderId { get; }

    public Uri BaseUri { get; }

    public string Model { get; }

    public string? ApiKey { get; }

    public double Temperature { get; }

    public TimeSpan Timeout { get; }

    public override string ToString() =>
        $"LlmProviderClientConfiguration {{ ProviderId = {ProviderId}, Endpoint = {BaseUri.Host}, Model = {Model}, ApiKey = [REDACTED] }}";

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
}

public sealed class LlmChatMessage
{
    public LlmChatMessage(LlmMessageRole role, string content)
    {
        if (!Enum.IsDefined(role))
        {
            throw new ArgumentOutOfRangeException(nameof(role), role, null);
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(content);

        Role = role;
        Content = content;
    }

    public LlmMessageRole Role { get; }

    public string Content { get; }
}

public sealed class LlmCompletionRequest
{
    public LlmCompletionRequest(
        IReadOnlyList<LlmChatMessage> messages,
        int? maxOutputTokens = null)
    {
        ArgumentNullException.ThrowIfNull(messages);
        if (messages.Count == 0)
        {
            throw new ArgumentException(
                "A completion request requires at least one message.",
                nameof(messages));
        }
        if (maxOutputTokens is <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxOutputTokens));
        }

        Messages = Array.AsReadOnly(messages.ToArray());
        MaxOutputTokens = maxOutputTokens;
    }

    public IReadOnlyList<LlmChatMessage> Messages { get; }

    public int? MaxOutputTokens { get; }

    public override string ToString() =>
        $"LlmCompletionRequest {{ MessageCount = {Messages.Count}, MaxOutputTokens = {MaxOutputTokens} }}";
}

public sealed class LlmCompletionResponse
{
    public LlmCompletionResponse(
        string text,
        string providerId,
        string model,
        AgentTokenUsage? tokenUsage)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);
        ArgumentException.ThrowIfNullOrWhiteSpace(model);

        Text = text;
        ProviderId = providerId;
        Model = model;
        TokenUsage = tokenUsage;
    }

    public string Text { get; }

    public string ProviderId { get; }

    public string Model { get; }

    public AgentTokenUsage? TokenUsage { get; }

    public override string ToString() =>
        $"LlmCompletionResponse {{ ProviderId = {ProviderId}, Model = {Model}, TextLength = {Text.Length} }}";
}

public sealed class LlmStreamUpdate
{
    public LlmStreamUpdate(
        string deltaText,
        string accumulatedText,
        bool isFinal,
        AgentTokenUsage? tokenUsage)
    {
        ArgumentNullException.ThrowIfNull(deltaText);
        ArgumentNullException.ThrowIfNull(accumulatedText);
        if (isFinal && string.IsNullOrWhiteSpace(accumulatedText))
        {
            throw new ArgumentException(
                "A final stream update requires accumulated text.",
                nameof(accumulatedText));
        }

        DeltaText = deltaText;
        AccumulatedText = accumulatedText;
        IsFinal = isFinal;
        TokenUsage = tokenUsage;
    }

    public string DeltaText { get; }

    public string AccumulatedText { get; }

    public bool IsFinal { get; }

    public AgentTokenUsage? TokenUsage { get; }

    public override string ToString() =>
        $"LlmStreamUpdate {{ IsFinal = {IsFinal}, DeltaLength = {DeltaText.Length}, AccumulatedLength = {AccumulatedText.Length} }}";
}

public sealed class LlmModelDescriptor
{
    public LlmModelDescriptor(
        string id,
        string? displayName,
        string? ownedBy)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        Id = id.Trim();
        DisplayName = displayName;
        OwnedBy = ownedBy;
    }

    public string Id { get; }

    public string? DisplayName { get; }

    public string? OwnedBy { get; }
}

public sealed class LlmModelDiscoveryResult
{
    public LlmModelDiscoveryResult(
        IReadOnlyList<LlmModelDescriptor> models,
        LlmModelDiscoverySource source,
        string? safeMessage = null)
    {
        ArgumentNullException.ThrowIfNull(models);
        if (!Enum.IsDefined(source))
        {
            throw new ArgumentOutOfRangeException(nameof(source), source, null);
        }

        Models = Array.AsReadOnly(models.ToArray());
        Source = source;
        SafeMessage = safeMessage;
    }

    public IReadOnlyList<LlmModelDescriptor> Models { get; }

    public LlmModelDiscoverySource Source { get; }

    public string? SafeMessage { get; }
}

public sealed class LlmConnectionTestResult
{
    public LlmConnectionTestResult(
        LlmConnectionTestStatus status,
        long? latencyMs,
        string? safeMessage)
    {
        if (!Enum.IsDefined(status))
        {
            throw new ArgumentOutOfRangeException(nameof(status), status, null);
        }
        if (latencyMs is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(latencyMs));
        }

        Status = status;
        LatencyMs = latencyMs;
        SafeMessage = safeMessage;
    }

    public LlmConnectionTestStatus Status { get; }

    public long? LatencyMs { get; }

    public string? SafeMessage { get; }

    public bool Succeeded => Status == LlmConnectionTestStatus.Succeeded;
}

public sealed class LlmAgentCapabilityTestResult
{
    public LlmAgentCapabilityTestResult(
        LlmAgentCapabilityStatus status,
        string? safeMessage)
    {
        if (!Enum.IsDefined(status))
        {
            throw new ArgumentOutOfRangeException(nameof(status), status, null);
        }

        Status = status;
        SafeMessage = safeMessage;
    }

    public LlmAgentCapabilityStatus Status { get; }

    public string? SafeMessage { get; }

    public bool IsSupported => Status == LlmAgentCapabilityStatus.Supported;
}

public interface ILlmCompletionClient
{
    ValueTask<LlmCompletionResponse> CompleteAsync(
        LlmProviderClientConfiguration configuration,
        LlmCompletionRequest request,
        CancellationToken cancellationToken);
}

public interface ILlmStreamingClient
{
    IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
        LlmProviderClientConfiguration configuration,
        LlmCompletionRequest request,
        CancellationToken cancellationToken);
}

public interface ILlmModelDiscoveryClient
{
    ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken);
}

public interface ILlmConnectionTester
{
    ValueTask<LlmConnectionTestResult> TestConnectionAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken);
}

public interface ILlmAgentCapabilityTester
{
    ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken);
}

public interface ILlmProviderClient
    : ILlmCompletionClient,
      ILlmStreamingClient,
      ILlmModelDiscoveryClient,
      ILlmConnectionTester,
      ILlmAgentCapabilityTester;

public interface IDefaultLlmProviderResolver
{
    ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
        CancellationToken cancellationToken);
}
