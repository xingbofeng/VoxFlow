using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.Tests;

public sealed class LlmProviderTemplateCatalogTests
{
    public static TheoryData<string, string, string, string, bool, int> MacTemplates => new()
    {
        { "google", "Google AI Studio", "https://generativelanguage.googleapis.com/v1beta/openai", "https://aistudio.google.com/apikey", true, 30 },
        { "groq", "Groq", "https://api.groq.com/openai/v1", "https://console.groq.com/keys", true, 30 },
        { "deepseek", "DeepSeek", "https://api.deepseek.com", "https://platform.deepseek.com/api_keys", true, 30 },
        { "cerebras", "Cerebras", "https://api.cerebras.ai/v1", "https://cloud.cerebras.ai/platform", true, 30 },
        { "nvidia", "NVIDIA NIM", "https://integrate.api.nvidia.com/v1", "https://build.nvidia.com/settings/api-keys", true, 30 },
        { "mistral", "Mistral", "https://api.mistral.ai/v1", "https://console.mistral.ai/api-keys", true, 30 },
        { "openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "https://openrouter.ai/settings/keys", true, 30 },
        { "github", "GitHub Models", "https://models.github.ai/inference", "https://github.com/settings/tokens", true, 30 },
        { "cohere", "Cohere", "https://api.cohere.com/compatibility/v1", "https://dashboard.cohere.com/api-keys", true, 60 },
        { "cloudflare", "Cloudflare Workers AI", "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1", "https://dash.cloudflare.com/profile/api-tokens", true, 30 },
        { "huggingface", "HuggingFace Router", "https://router.huggingface.co/v1", "https://huggingface.co/settings/tokens", true, 30 },
        { "ollama-cloud", "Ollama Cloud", "https://ollama.com/v1", "https://ollama.com/settings/keys", true, 120 },
        { "ollama-local", "Ollama 本地", "http://localhost:11434/v1", "https://ollama.com/download", false, 120 },
        { "opencode", "OpenCode Zen", "https://opencode.ai/zen/v1", "https://opencode.ai/auth", true, 30 },
        { "agnes", "Agnes AI", "https://apihub.agnes-ai.com/v1", "https://platform.agnes-ai.com", true, 60 },
        { "reka", "Reka", "https://api.reka.ai/v1", "https://platform.reka.ai", true, 30 },
        { "siliconflow", "SiliconFlow", "https://api.siliconflow.com/v1", "https://cloud.siliconflow.cn/account/ak", true, 30 },
        { "routeway", "Routeway", "https://api.routeway.ai/v1", "https://routeway.ai", true, 30 },
        { "bazaarlink", "BazaarLink", "https://bazaarlink.ai/api/v1", "https://bazaarlink.ai", true, 30 },
        { "ainative", "AINative Studio", "https://api.ainative.studio/api/v1", "https://ainative.studio", true, 30 },
    };

    [Theory]
    [MemberData(nameof(MacTemplates))]
    public void Windows_catalog_matches_every_current_mac_template_field(
        string id,
        string displayName,
        string baseUrl,
        string apiKeyUrl,
        bool requiresApiKey,
        int timeoutSeconds)
    {
        var template = Assert.IsType<LlmProviderTemplate>(
            LlmProviderTemplateCatalog.Find(id));

        Assert.Equal(displayName, template.DisplayName);
        Assert.Equal(baseUrl, template.BaseUrl);
        Assert.Equal(string.Empty, template.DefaultModel);
        Assert.Equal(new Uri(apiKeyUrl), template.ApiKeyUri);
        Assert.Equal(requiresApiKey, template.RequiresApiKey);
        Assert.Equal(timeoutSeconds, template.TimeoutSeconds);
        Assert.False(template.IsCustom);
    }

    [Fact]
    public void Catalog_adds_TokenHub_to_the_mac_ids_and_keeps_a_separate_custom_option()
    {
        var expectedIds = new[] { "tencent-tokenhub" }
            .Concat(MacTemplates.Select(row => (string)row[0]))
            .ToArray();
        var actualIds = LlmProviderTemplateCatalog.Templates
            .Select(template => template.Id)
            .ToArray();

        Assert.Equal(expectedIds, actualIds);
        Assert.Equal(actualIds.Length, actualIds.Distinct(StringComparer.Ordinal).Count());
        Assert.Equal(21, actualIds.Length);
        var custom = Assert.IsType<LlmProviderTemplate>(
            LlmProviderTemplateCatalog.Find(
                LlmProviderTemplateCatalog.CustomTemplateId));
        Assert.True(custom.IsCustom);
        Assert.Equal("Custom", custom.DisplayName);
        Assert.Equal(string.Empty, custom.BaseUrl);
        Assert.Null(custom.ApiKeyUri);
        Assert.Equal(30, custom.TimeoutSeconds);
        Assert.Equal(22, LlmProviderTemplateCatalog.Options.Count);
    }

    [Fact]
    public void TokenHub_template_uses_the_documented_compatible_endpoint()
    {
        var template = Assert.IsType<LlmProviderTemplate>(
            LlmProviderTemplateCatalog.Find("tencent-tokenhub"));

        Assert.Equal("https://tokenhub.tencentmaas.com/v1", template.BaseUrl);
        Assert.Equal("deepseek-v4-flash", template.DefaultModel);
        Assert.True(template.RequiresApiKey);
        Assert.Equal(
            new[] { "deepseek-v4-flash" },
            LlmProviderTemplateCatalog.FallbackModelIds(new Uri(template.BaseUrl)));
    }

    [Fact]
    public void Loopback_http_is_allowed_but_remote_http_is_rejected()
    {
        Assert.Equal(
            new Uri("http://localhost:11434/v1"),
            LlmProviderEndpoint.Normalize(" http://localhost:11434/v1/ "));
        Assert.Equal(
            new Uri("http://127.0.0.1:31415/v1"),
            LlmProviderEndpoint.Normalize("http://127.0.0.1:31415/v1"));
        Assert.Equal(
            new Uri("http://[::1]:11434/v1"),
            LlmProviderEndpoint.Normalize("http://[::1]:11434/v1"));
        Assert.True(LlmProviderEndpoint.IsLoopback(
            new Uri("https://localhost:11434/v1")));
        Assert.Equal(
            new Uri("https://example.com/v1"),
            LlmProviderEndpoint.Normalize("https://example.com/v1/"));

        Assert.Throws<ArgumentException>(() =>
            LlmProviderEndpoint.Normalize("http://example.com/v1"));
        Assert.Throws<ArgumentException>(() =>
            LlmProviderEndpoint.Normalize("ftp://localhost/v1"));
    }

    [Fact]
    public void OpenCode_Zen_is_only_an_OpenAI_compatible_service_template()
    {
        var template = Assert.IsType<LlmProviderTemplate>(
            LlmProviderTemplateCatalog.Find("opencode"));

        Assert.Equal("OpenCode Zen", template.DisplayName);
        Assert.Equal("https://opencode.ai/zen/v1", template.BaseUrl);
        Assert.Equal(LlmProviderType.OpenAiCompatible, template.ProviderType);
        Assert.False(template.EnablesExternalAgentRuntime);
    }
}
