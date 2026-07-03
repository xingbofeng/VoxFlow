import AppKit

enum LLMProviderIconResource {
    static func resourceName(templateID: String) -> String? {
        switch templateID {
        case "google":
            return "LLMProviderGoogle"
        case "groq":
            return "LLMProviderGroq"
        case "deepseek":
            return "LLMProviderDeepSeek"
        case "cerebras":
            return "LLMProviderCerebras"
        case "nvidia":
            return "LLMProviderNVIDIA"
        case "mistral":
            return "LLMProviderMistral"
        case "openrouter":
            return "LLMProviderOpenRouter"
        case "github":
            return "LLMProviderGitHub"
        case "cohere":
            return "LLMProviderCohere"
        case "cloudflare":
            return "LLMProviderCloudflare"
        case "huggingface":
            return "LLMProviderHuggingFace"
        case "ollama-cloud", "ollama-local":
            return "LLMProviderOllama"
        case "opencode":
            return "LLMProviderOpenCode"
        case "agnes":
            return "LLMProviderAgnes"
        case "reka":
            return "LLMProviderReka"
        case "siliconflow":
            return "LLMProviderSiliconFlow"
        case "routeway":
            return "LLMProviderRouteway"
        case "bazaarlink":
            return "LLMProviderBazaarLink"
        case "ainative":
            return "LLMProviderAINative"
        default:
            return nil
        }
    }

    static func resourceName(provider: LLMProviderRecord) -> String? {
        if let templateID = LLMProviderTemplateCatalog.templateID(baseURL: provider.baseURL),
           let resourceName = resourceName(templateID: templateID) {
            return resourceName
        }
        return nil
    }

    static func resourceName(displayName: String) -> String? {
        let normalized = displayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        if normalized.contains("google") {
            return "LLMProviderGoogle"
        }
        if normalized.contains("groq") {
            return "LLMProviderGroq"
        }
        if normalized.contains("deepseek") {
            return "LLMProviderDeepSeek"
        }
        if normalized.contains("cerebras") {
            return "LLMProviderCerebras"
        }
        if normalized.contains("nvidia") || normalized.contains("nim") {
            return "LLMProviderNVIDIA"
        }
        if normalized.contains("mistral") {
            return "LLMProviderMistral"
        }
        if normalized.contains("openrouter") {
            return "LLMProviderOpenRouter"
        }
        if normalized.contains("github") {
            return "LLMProviderGitHub"
        }
        if normalized.contains("cohere") {
            return "LLMProviderCohere"
        }
        if normalized.contains("cloudflare") {
            return "LLMProviderCloudflare"
        }
        if normalized.contains("huggingface") {
            return "LLMProviderHuggingFace"
        }
        if normalized.contains("ollama") {
            return "LLMProviderOllama"
        }
        if normalized.contains("opencode") {
            return "LLMProviderOpenCode"
        }
        if normalized.contains("agnes") {
            return "LLMProviderAgnes"
        }
        if normalized.contains("reka") {
            return "LLMProviderReka"
        }
        if normalized.contains("siliconflow") {
            return "LLMProviderSiliconFlow"
        }
        if normalized.contains("routeway") {
            return "LLMProviderRouteway"
        }
        if normalized.contains("bazaarlink") {
            return "LLMProviderBazaarLink"
        }
        if normalized.contains("ainative") {
            return "LLMProviderAINative"
        }
        return nil
    }

    static func load(resourceName: String) -> NSImage? {
        guard let url = VoxFlowAppResourceBundle.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            AppLogger.general.warning("LLMProviderIcon load failed resource=\(resourceName)")
            return nil
        }
        image.isTemplate = true
        return image
    }

    static func load(templateID: String) -> NSImage? {
        guard let resourceName = resourceName(templateID: templateID) else { return nil }
        return load(resourceName: resourceName)
    }

    static func load(provider: LLMProviderRecord) -> NSImage? {
        guard let resourceName = resourceName(provider: provider) else { return nil }
        return load(resourceName: resourceName)
    }
}

enum AgentProviderIconResource {
    static func resourceName(providerID: String) -> String? {
        switch providerID {
        case "voxflow-agent":
            return "LLMProviderAINative"
        case "codex":
            return "AgentProviderCodex"
        case "opencode":
            return "AgentProviderOpenCode"
        case "claude":
            return "AgentProviderClaudeCode"
        case "codebuddy":
            return "AgentProviderCodeBuddy"
        case "pi":
            return "AgentProviderPi"
        default:
            return nil
        }
    }
}
