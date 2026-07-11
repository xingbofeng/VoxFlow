using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Llm;

public sealed record LlmProviderSettings
{
    public LlmProviderSettings(
        LlmProviderId provider,
        Uri baseUri,
        string model,
        bool Enabled)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        ArgumentException.ThrowIfNullOrWhiteSpace(model);
        if (!baseUri.IsAbsoluteUri
            || !string.Equals(baseUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("An HTTPS LLM base URL is required.", nameof(baseUri));
        }

        Provider = provider;
        BaseUri = NormalizeBaseUri(baseUri);
        Model = model.Trim();
        this.Enabled = Enabled;
    }

    public LlmProviderId Provider { get; }

    public Uri BaseUri { get; }

    public string Model { get; }

    public bool Enabled { get; }

    private static Uri NormalizeBaseUri(Uri value) =>
        new(value.AbsoluteUri.TrimEnd('/'), UriKind.Absolute);
}

public interface ILlmProviderSettingsStore
{
    ValueTask<LlmProviderSettings?> LoadAsync(
        LlmProviderId provider,
        CancellationToken cancellationToken);

    ValueTask SaveAsync(
        LlmProviderSettings settings,
        CancellationToken cancellationToken);

    ValueTask DeleteAsync(
        LlmProviderId provider,
        CancellationToken cancellationToken);
}
