namespace VoxFlow.Windows.Application.Llm;

public sealed class LlmProviderTemplate
{
    public LlmProviderTemplate(
        string id,
        string displayName,
        string baseUrl,
        string defaultModel,
        Uri? apiKeyUri,
        bool requiresApiKey,
        int timeoutSeconds,
        bool isCustom = false)
    {
        ValidateSingleLine(id, nameof(id));
        ValidateSingleLine(displayName, nameof(displayName));
        ValidateOptionalSingleLine(baseUrl, nameof(baseUrl));
        ValidateOptionalSingleLine(defaultModel, nameof(defaultModel));
        if (!isCustom && string.IsNullOrWhiteSpace(baseUrl))
        {
            throw new ArgumentException(
                "A provider template requires a base URL.",
                nameof(baseUrl));
        }
        if (apiKeyUri is not null
            && (!apiKeyUri.IsAbsoluteUri
                || !string.Equals(
                    apiKeyUri.Scheme,
                    Uri.UriSchemeHttps,
                    StringComparison.OrdinalIgnoreCase)))
        {
            throw new ArgumentException(
                "The API key help link must use HTTPS.",
                nameof(apiKeyUri));
        }
        if (timeoutSeconds is < 1 or > 600)
        {
            throw new ArgumentOutOfRangeException(nameof(timeoutSeconds));
        }

        Id = id.Trim();
        DisplayName = displayName.Trim();
        BaseUrl = baseUrl.Trim();
        DefaultModel = defaultModel.Trim();
        ApiKeyUri = apiKeyUri;
        RequiresApiKey = requiresApiKey;
        TimeoutSeconds = timeoutSeconds;
        IsCustom = isCustom;
    }

    public string Id { get; }

    public string DisplayName { get; }

    public string BaseUrl { get; }

    public string DefaultModel { get; }

    public Uri? ApiKeyUri { get; }

    public bool RequiresApiKey { get; }

    public int TimeoutSeconds { get; }

    public bool IsCustom { get; }

    public LlmProviderType ProviderType => LlmProviderType.OpenAiCompatible;

    public bool EnablesExternalAgentRuntime => false;

    public override string ToString() =>
        $"LlmProviderTemplate {{ Id = {Id}, DisplayName = {DisplayName}, BaseUrl = {BaseUrl}, RequiresApiKey = {RequiresApiKey}, Secret = [REDACTED] }}";

    private static void ValidateOptionalSingleLine(
        string value,
        string parameterName)
    {
        ArgumentNullException.ThrowIfNull(value, parameterName);
        if (value.Contains('\r', StringComparison.Ordinal)
            || value.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "The value must be a single line.",
                parameterName);
        }
    }

    private static void ValidateSingleLine(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        ValidateOptionalSingleLine(value, parameterName);
    }
}

public static class LlmProviderTemplateCatalog
{
    public const string CustomTemplateId = "custom";

    private static readonly LlmProviderTemplate CustomTemplate = new(
        CustomTemplateId,
        "Custom",
        string.Empty,
        string.Empty,
        apiKeyUri: null,
        requiresApiKey: true,
        timeoutSeconds: 30,
        isCustom: true);

    private static readonly LlmProviderTemplate[] MacTemplates =
    [
        new LlmProviderTemplate(
            "tencent-tokenhub",
            "Tencent Cloud TokenHub",
            "https://tokenhub.tencentmaas.com/v1",
            "deepseek-v4-flash",
            new Uri("https://cloud.tencent.com/document/product/1823/132247"),
            requiresApiKey: true,
            timeoutSeconds: 120),
        Template("google", "Google AI Studio", "https://generativelanguage.googleapis.com/v1beta/openai", "https://aistudio.google.com/apikey", true, 30),
        Template("groq", "Groq", "https://api.groq.com/openai/v1", "https://console.groq.com/keys", true, 30),
        Template("deepseek", "DeepSeek", "https://api.deepseek.com", "https://platform.deepseek.com/api_keys", true, 30),
        Template("cerebras", "Cerebras", "https://api.cerebras.ai/v1", "https://cloud.cerebras.ai/platform", true, 30),
        Template("nvidia", "NVIDIA NIM", "https://integrate.api.nvidia.com/v1", "https://build.nvidia.com/settings/api-keys", true, 30),
        Template("mistral", "Mistral", "https://api.mistral.ai/v1", "https://console.mistral.ai/api-keys", true, 30),
        Template("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "https://openrouter.ai/settings/keys", true, 30),
        Template("github", "GitHub Models", "https://models.github.ai/inference", "https://github.com/settings/tokens", true, 30),
        Template("cohere", "Cohere", "https://api.cohere.com/compatibility/v1", "https://dashboard.cohere.com/api-keys", true, 60),
        Template("cloudflare", "Cloudflare Workers AI", "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1", "https://dash.cloudflare.com/profile/api-tokens", true, 30),
        Template("huggingface", "HuggingFace Router", "https://router.huggingface.co/v1", "https://huggingface.co/settings/tokens", true, 30),
        Template("ollama-cloud", "Ollama Cloud", "https://ollama.com/v1", "https://ollama.com/settings/keys", true, 120),
        Template("ollama-local", "Ollama 本地", "http://localhost:11434/v1", "https://ollama.com/download", false, 120),
        Template("opencode", "OpenCode Zen", "https://opencode.ai/zen/v1", "https://opencode.ai/auth", true, 30),
        Template("agnes", "Agnes AI", "https://apihub.agnes-ai.com/v1", "https://platform.agnes-ai.com", true, 60),
        Template("reka", "Reka", "https://api.reka.ai/v1", "https://platform.reka.ai", true, 30),
        Template("siliconflow", "SiliconFlow", "https://api.siliconflow.com/v1", "https://cloud.siliconflow.cn/account/ak", true, 30),
        Template("routeway", "Routeway", "https://api.routeway.ai/v1", "https://routeway.ai", true, 30),
        Template("bazaarlink", "BazaarLink", "https://bazaarlink.ai/api/v1", "https://bazaarlink.ai", true, 30),
        Template("ainative", "AINative Studio", "https://api.ainative.studio/api/v1", "https://ainative.studio", true, 30),
    ];

    private static readonly IReadOnlyList<LlmProviderTemplate> CatalogOptions =
        new[] { CustomTemplate }.Concat(MacTemplates).ToArray();

    private static readonly IReadOnlyDictionary<string, IReadOnlyList<string>>
        FallbackModels = new Dictionary<string, IReadOnlyList<string>>(
            StringComparer.Ordinal)
        {
            ["tencent-tokenhub"] = Models(
                "deepseek-v4-flash"),
            ["google"] = Models(
                "gemini-3.5-flash",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemma-4-31b-it",
                "gemma-4-26b-a4b-it"),
            ["groq"] = Models(
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
                "llama-3.3-70b-versatile",
                "llama-3.1-8b-instant",
                "groq/compound",
                "groq/compound-mini",
                "openai/gpt-oss-safeguard-20b"),
            ["deepseek"] = Models(
                "deepseek-chat",
                "deepseek-reasoner"),
            ["cerebras"] = Models(
                "gpt-oss-120b",
                "zai-glm-4.7"),
            ["nvidia"] = Models(
                "deepseek-ai/deepseek-v4-pro",
                "deepseek-ai/deepseek-v4-flash",
                "minimaxai/minimax-m2.7",
                "mistralai/mistral-large-3-675b-instruct-2512",
                "moonshotai/kimi-k2.6",
                "z-ai/glm-5.1",
                "meta/llama-4-maverick-17b-128e-instruct",
                "meta/llama-3.3-70b-instruct",
                "meta/llama-3.1-70b-instruct",
                "nvidia/nemotron-3-super-120b-a12b",
                "nvidia/nemotron-3-nano-30b-a3b"),
            ["mistral"] = Models(
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest",
                "magistral-medium-latest",
                "codestral-latest",
                "devstral-latest",
                "ministral-8b-latest"),
            ["openrouter"] = Models(
                "qwen/qwen3-coder:free",
                "qwen/qwen3-next-80b-a3b-instruct:free",
                "openai/gpt-oss-120b:free",
                "openai/gpt-oss-20b:free",
                "meta-llama/llama-3.3-70b-instruct:free",
                "nvidia/nemotron-3-super-120b-a12b:free",
                "google/gemma-4-31b-it:free",
                "google/gemma-4-26b-a4b-it:free",
                "nvidia/nemotron-3-nano-30b-a3b:free",
                "nvidia/nemotron-nano-9b-v2:free",
                "meta-llama/llama-3.2-3b-instruct:free",
                "liquid/lfm-2.5-1.2b-instruct:free",
                "liquid/lfm-2.5-1.2b-thinking:free"),
            ["github"] = Models("openai/gpt-4.1"),
            ["cohere"] = Models(
                "command-a-reasoning-08-2025",
                "command-a-03-2025",
                "command-r-plus-08-2024",
                "command-r-08-2024"),
            ["cloudflare"] = Models(
                "@cf/moonshotai/kimi-k2.6",
                "@cf/openai/gpt-oss-120b",
                "@cf/qwen/qwen3-30b-a3b-fp8",
                "@cf/deepseek-ai/deepseek-r1-distill-qwen-32b",
                "@cf/zai-org/glm-4.7-flash",
                "@cf/meta/llama-4-scout-17b-16e-instruct",
                "@cf/meta/llama-3.3-70b-instruct-fp8-fast"),
            ["huggingface"] = Models(
                "deepseek-ai/DeepSeek-V4-Flash",
                "moonshotai/Kimi-K2.6",
                "Qwen/Qwen3-Coder-Next",
                "accounts/fireworks/models/llama-v3p3-70b-instruct"),
            ["ollama-cloud"] = Models(
                "qwen3-coder:480b",
                "qwen3-coder-next",
                "glm-4.7",
                "gpt-oss:120b",
                "gpt-oss:20b",
                "gemma4:31b"),
            ["opencode"] = Models(
                "deepseek-v4-flash-free",
                "big-pickle",
                "mimo-v2.5-free"),
            ["agnes"] = Models("agnes-1.5-flash"),
            ["reka"] = Models("reka-flash-3", "reka-edge-2603"),
        };

    public static IReadOnlyList<LlmProviderTemplate> Templates => MacTemplates;

    public static IReadOnlyList<LlmProviderTemplate> Options => CatalogOptions;

    public static LlmProviderTemplate? Find(string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        if (string.Equals(id, CustomTemplateId, StringComparison.Ordinal))
        {
            return CustomTemplate;
        }
        return MacTemplates.FirstOrDefault(template =>
            string.Equals(template.Id, id, StringComparison.Ordinal));
    }

    public static LlmProviderTemplate? Match(Uri baseUri)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        if (!baseUri.IsAbsoluteUri)
        {
            return null;
        }

        var host = baseUri.Host.ToLowerInvariant();
        var path = baseUri.AbsolutePath.TrimEnd('/').ToLowerInvariant();
        var id = host switch
        {
            "tokenhub.tencentmaas.com" => "tencent-tokenhub",
            "generativelanguage.googleapis.com" => "google",
            "api.groq.com" => "groq",
            "api.deepseek.com" => "deepseek",
            "api.cerebras.ai" => "cerebras",
            "integrate.api.nvidia.com" => "nvidia",
            "api.mistral.ai" => "mistral",
            "openrouter.ai" => "openrouter",
            "models.github.ai" => "github",
            "api.cohere.com" or "api.cohere.ai" => "cohere",
            "api.cloudflare.com" when path.Contains(
                "/ai/v1",
                StringComparison.Ordinal) => "cloudflare",
            "router.huggingface.co" => "huggingface",
            "ollama.com" => "ollama-cloud",
            "opencode.ai" => "opencode",
            "apihub.agnes-ai.com" => "agnes",
            "api.reka.ai" => "reka",
            "api.siliconflow.com" => "siliconflow",
            "api.routeway.ai" => "routeway",
            "bazaarlink.ai" => "bazaarlink",
            "api.ainative.studio" => "ainative",
            _ when baseUri.IsLoopback
                && baseUri.Port == 11434
                && path == "/v1" => "ollama-local",
            _ => null,
        };
        return id is null ? null : Find(id);
    }

    public static IReadOnlyList<string> FallbackModelIds(Uri baseUri)
    {
        var template = Match(baseUri);
        return template is not null
            && FallbackModels.TryGetValue(template.Id, out var models)
                ? models
                : Array.Empty<string>();
    }

    private static LlmProviderTemplate Template(
        string id,
        string displayName,
        string baseUrl,
        string apiKeyUrl,
        bool requiresApiKey,
        int timeoutSeconds) => new(
        id,
        displayName,
        baseUrl,
        string.Empty,
        new Uri(apiKeyUrl, UriKind.Absolute),
        requiresApiKey,
        timeoutSeconds);

    private static IReadOnlyList<string> Models(params string[] values) =>
        Array.AsReadOnly(values);
}

public static class LlmProviderEndpoint
{
    public static Uri Normalize(string baseUrl)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(baseUrl);
        if (!Uri.TryCreate(baseUrl.Trim(), UriKind.Absolute, out var parsed)
            || string.IsNullOrWhiteSpace(parsed.Host))
        {
            throw new ArgumentException(
                "A valid absolute provider base URL is required.",
                nameof(baseUrl));
        }
        if (!string.IsNullOrEmpty(parsed.UserInfo)
            || !string.IsNullOrEmpty(parsed.Query)
            || !string.IsNullOrEmpty(parsed.Fragment))
        {
            throw new ArgumentException(
                "Provider base URLs cannot contain user info, a query, or a fragment.",
                nameof(baseUrl));
        }

        var https = string.Equals(
            parsed.Scheme,
            Uri.UriSchemeHttps,
            StringComparison.OrdinalIgnoreCase);
        var loopbackHttp = string.Equals(
                parsed.Scheme,
                Uri.UriSchemeHttp,
                StringComparison.OrdinalIgnoreCase)
            && IsLoopback(parsed);
        if (!https && !loopbackHttp)
        {
            throw new ArgumentException(
                "Remote providers require HTTPS; HTTP is allowed only for loopback hosts.",
                nameof(baseUrl));
        }

        var builder = new UriBuilder(parsed)
        {
            Fragment = string.Empty,
            Query = string.Empty,
        };
        if (builder.Path.Length > 1)
        {
            builder.Path = builder.Path.TrimEnd('/');
        }
        const string chatSuffix = "/chat/completions";
        if (builder.Path.EndsWith(
            chatSuffix,
            StringComparison.OrdinalIgnoreCase))
        {
            builder.Path = builder.Path[..^chatSuffix.Length];
        }
        return builder.Uri;
    }

    public static bool IsLoopback(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);
        return uri.IsAbsoluteUri && uri.IsLoopback;
    }
}
