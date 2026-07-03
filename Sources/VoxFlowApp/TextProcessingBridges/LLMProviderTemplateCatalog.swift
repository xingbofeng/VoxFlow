import Foundation

struct LLMProviderTemplate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let baseURL: String
    let defaultModel: String
    let apiKeyURL: URL?
    let requiresAPIKey: Bool
    let timeoutSeconds: Double

    var providerType: String {
        requiresAPIKey ? LLMProviderProviderType.openAICompatible : LLMProviderProviderType.openAICompatibleNoKey
    }
}

enum LLMProviderProviderType {
    static let openAICompatible = "openaiCompatible"
    static let openAICompatibleNoKey = "openaiCompatibleNoKey"
}

enum LLMProviderTemplateCatalog {
    static let customTemplateID = "custom"

    static let templates: [LLMProviderTemplate] = [
        LLMProviderTemplate(
            id: "google",
            displayName: "Google AI Studio",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            defaultModel: "",
            apiKeyURL: URL(string: "https://aistudio.google.com/apikey"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "groq",
            displayName: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://console.groq.com/keys"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "deepseek",
            displayName: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            defaultModel: "",
            apiKeyURL: URL(string: "https://platform.deepseek.com/api_keys"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "cerebras",
            displayName: "Cerebras",
            baseURL: "https://api.cerebras.ai/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://cloud.cerebras.ai/platform"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "nvidia",
            displayName: "NVIDIA NIM",
            baseURL: "https://integrate.api.nvidia.com/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://build.nvidia.com/settings/api-keys"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "mistral",
            displayName: "Mistral",
            baseURL: "https://api.mistral.ai/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://console.mistral.ai/api-keys"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "openrouter",
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://openrouter.ai/settings/keys"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "github",
            displayName: "GitHub Models",
            baseURL: "https://models.github.ai/inference",
            defaultModel: "",
            apiKeyURL: URL(string: "https://github.com/settings/tokens"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "cohere",
            displayName: "Cohere",
            baseURL: "https://api.cohere.com/compatibility/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://dashboard.cohere.com/api-keys"),
            requiresAPIKey: true,
            timeoutSeconds: 60
        ),
        LLMProviderTemplate(
            id: "cloudflare",
            displayName: "Cloudflare Workers AI",
            baseURL: "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://dash.cloudflare.com/profile/api-tokens"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "huggingface",
            displayName: "HuggingFace Router",
            baseURL: "https://router.huggingface.co/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://huggingface.co/settings/tokens"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "ollama-cloud",
            displayName: "Ollama Cloud",
            baseURL: "https://ollama.com/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://ollama.com/settings/keys"),
            requiresAPIKey: true,
            timeoutSeconds: 120
        ),
        LLMProviderTemplate(
            id: "ollama-local",
            displayName: "Ollama 本地",
            baseURL: "http://localhost:11434/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://ollama.com/download"),
            requiresAPIKey: false,
            timeoutSeconds: 120
        ),
        LLMProviderTemplate(
            id: "opencode",
            displayName: "OpenCode Zen",
            baseURL: "https://opencode.ai/zen/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://opencode.ai/auth"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "agnes",
            displayName: "Agnes AI",
            baseURL: "https://apihub.agnes-ai.com/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://platform.agnes-ai.com"),
            requiresAPIKey: true,
            timeoutSeconds: 60
        ),
        LLMProviderTemplate(
            id: "reka",
            displayName: "Reka",
            baseURL: "https://api.reka.ai/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://platform.reka.ai"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "siliconflow",
            displayName: "SiliconFlow",
            baseURL: "https://api.siliconflow.com/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://cloud.siliconflow.cn/account/ak"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "routeway",
            displayName: "Routeway",
            baseURL: "https://api.routeway.ai/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://routeway.ai"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "bazaarlink",
            displayName: "BazaarLink",
            baseURL: "https://bazaarlink.ai/api/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://bazaarlink.ai"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
        LLMProviderTemplate(
            id: "ainative",
            displayName: "AINative Studio",
            baseURL: "https://api.ainative.studio/api/v1",
            defaultModel: "",
            apiKeyURL: URL(string: "https://ainative.studio"),
            requiresAPIKey: true,
            timeoutSeconds: 30
        ),
    ]

    static func template(id: String) -> LLMProviderTemplate? {
        templates.first { $0.id == id }
    }

    static func catalogModelIDs(baseURL: String) -> [String] {
        guard let templateID = templateID(baseURL: baseURL) else { return [] }
        return catalogModelIDsByTemplateID[templateID] ?? []
    }

    static func shouldPreferCatalog(baseURL: String) -> Bool {
        guard let templateID = templateID(baseURL: baseURL) else { return false }
        return templateID != "ollama-local"
    }

    static func fallbackModelIDs(baseURL: String) -> [String] {
        catalogModelIDs(baseURL: baseURL)
    }

    static func isLoopbackBaseURL(_ baseURL: String) -> Bool {
        guard let components = URLComponents(string: baseURL),
              let host = components.host?.lowercased() else {
            return false
        }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    static func templateID(baseURL: String) -> String? {
        guard let components = URLComponents(string: baseURL),
              let host = components.host?.lowercased() else {
            return nil
        }
        let path = components.path.lowercased()
        if host == "generativelanguage.googleapis.com" {
            return "google"
        }
        if host == "api.groq.com" {
            return "groq"
        }
        if host == "api.deepseek.com" {
            return "deepseek"
        }
        if host == "api.cerebras.ai" {
            return "cerebras"
        }
        if host == "integrate.api.nvidia.com" {
            return "nvidia"
        }
        if host == "api.mistral.ai" {
            return "mistral"
        }
        if host == "openrouter.ai" {
            return "openrouter"
        }
        if host == "models.github.ai" {
            return "github"
        }
        if host == "api.cohere.com" || host == "api.cohere.ai" {
            return "cohere"
        }
        if host == "api.cloudflare.com", path.contains("/ai/v1") {
            return "cloudflare"
        }
        if host == "router.huggingface.co" {
            return "huggingface"
        }
        if host == "ollama.com" {
            return "ollama-cloud"
        }
        if ["localhost", "127.0.0.1", "::1"].contains(host),
           components.port == 11434,
           path == "/v1" {
            return "ollama-local"
        }
        if host == "opencode.ai" {
            return "opencode"
        }
        if host == "apihub.agnes-ai.com" {
            return "agnes"
        }
        if host == "api.reka.ai" {
            return "reka"
        }
        if host == "api.siliconflow.com" {
            return "siliconflow"
        }
        if host == "api.routeway.ai" {
            return "routeway"
        }
        if host == "bazaarlink.ai" {
            return "bazaarlink"
        }
        if host == "api.ainative.studio" {
            return "ainative"
        }
        return nil
    }

    private static let catalogModelIDsByTemplateID: [String: [String]] = [
        "google": [
            "gemini-3.5-flash",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemma-4-31b-it",
            "gemma-4-26b-a4b-it",
        ],
        "groq": [
            "openai/gpt-oss-120b",
            "openai/gpt-oss-20b",
            "llama-3.3-70b-versatile",
            "llama-3.1-8b-instant",
            "groq/compound",
            "groq/compound-mini",
            "openai/gpt-oss-safeguard-20b",
        ],
        "deepseek": [
            "deepseek-chat",
            "deepseek-reasoner",
        ],
        "cerebras": [
            "gpt-oss-120b",
            "zai-glm-4.7",
        ],
        "nvidia": [
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
            "nvidia/nemotron-3-nano-30b-a3b",
        ],
        "mistral": [
            "mistral-large-latest",
            "mistral-medium-latest",
            "mistral-small-latest",
            "magistral-medium-latest",
            "codestral-latest",
            "devstral-latest",
            "ministral-8b-latest",
        ],
        "openrouter": [
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
            "liquid/lfm-2.5-1.2b-thinking:free",
        ],
        "github": [
            "openai/gpt-4.1",
        ],
        "cohere": [
            "command-a-reasoning-08-2025",
            "command-a-03-2025",
            "command-r-plus-08-2024",
            "command-r-08-2024",
        ],
        "cloudflare": [
            "@cf/moonshotai/kimi-k2.6",
            "@cf/openai/gpt-oss-120b",
            "@cf/qwen/qwen3-30b-a3b-fp8",
            "@cf/deepseek-ai/deepseek-r1-distill-qwen-32b",
            "@cf/zai-org/glm-4.7-flash",
            "@cf/meta/llama-4-scout-17b-16e-instruct",
            "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
        ],
        "huggingface": [
            "deepseek-ai/DeepSeek-V4-Flash",
            "moonshotai/Kimi-K2.6",
            "Qwen/Qwen3-Coder-Next",
            "accounts/fireworks/models/llama-v3p3-70b-instruct",
        ],
        "ollama-cloud": [
            "qwen3-coder:480b",
            "qwen3-coder-next",
            "glm-4.7",
            "gpt-oss:120b",
            "gpt-oss:20b",
            "gemma4:31b",
        ],
        "opencode": [
            "deepseek-v4-flash-free",
            "big-pickle",
            "mimo-v2.5-free",
        ],
        "agnes": [
            "agnes-1.5-flash",
        ],
        "reka": [
            "reka-flash-3",
            "reka-edge-2603",
        ],
    ]
}
