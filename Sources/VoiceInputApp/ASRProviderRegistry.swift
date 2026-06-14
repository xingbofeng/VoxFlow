import Foundation

enum ASRProviderID {
    static let appleSpeech = "apple_speech"
    static let qwen3 = "qwen3_asr"
}

struct ASRProviderCapabilities: OptionSet, Hashable {
    let rawValue: Int

    static let streaming = ASRProviderCapabilities(rawValue: 1 << 0)
    static let fileTranscription = ASRProviderCapabilities(rawValue: 1 << 1)
    static let local = ASRProviderCapabilities(rawValue: 1 << 2)
    static let cloud = ASRProviderCapabilities(rawValue: 1 << 3)
    static let fast = ASRProviderCapabilities(rawValue: 1 << 4)
    static let accurate = ASRProviderCapabilities(rawValue: 1 << 5)
    static let multilingual = ASRProviderCapabilities(rawValue: 1 << 6)
    static let punctuation = ASRProviderCapabilities(rawValue: 1 << 7)

    var identifiers: [String] {
        Self.orderedDefinitions.compactMap { definition in
            contains(definition.capability) ? definition.id : nil
        }
    }

    static let orderedDefinitions: [(capability: ASRProviderCapabilities, id: String, title: String)] = [
        (.streaming, "streaming", "实时"),
        (.fileTranscription, "fileTranscription", "文件"),
        (.local, "local", "本地"),
        (.cloud, "cloud", "云端"),
        (.fast, "fast", "快速"),
        (.accurate, "accurate", "高准确"),
        (.multilingual, "multilingual", "多语言"),
        (.punctuation, "punctuation", "标点"),
    ]
}

struct ASRProviderDescriptor: Equatable, Identifiable {
    let id: String
    let displayName: String
    let providerType: String
    let capabilities: ASRProviderCapabilities
    let tags: [String]
    let isAvailable: Bool
    let isDefault: Bool
    let statusMessage: String?
    let privacySummary: String
    let modelSize: ASRManager.ModelSize?
    let engineType: ASREngineType?
}

struct ASRProviderFilter: Equatable {
    var requiredCapabilities: ASRProviderCapabilities = []
    var tags: Set<String> = []
    var availableOnly = false

    func matches(_ descriptor: ASRProviderDescriptor) -> Bool {
        if availableOnly && !descriptor.isAvailable {
            return false
        }
        if !descriptor.capabilities.isSuperset(of: requiredCapabilities) {
            return false
        }
        if !tags.isEmpty && !tags.isSubset(of: Set(descriptor.tags)) {
            return false
        }
        return true
    }
}

final class ASRProviderRegistry {
    private let asrManager: ASRManager
    private var customDescriptors: [String: ASRProviderDescriptor] = [:]

    init(asrManager: ASRManager = ASRManager()) {
        self.asrManager = asrManager
    }

    func register(_ descriptor: ASRProviderDescriptor) {
        customDescriptors[descriptor.id] = descriptor
    }

    func descriptors(matching filter: ASRProviderFilter = ASRProviderFilter()) -> [ASRProviderDescriptor] {
        builtInDescriptors()
            .merging(customDescriptors) { _, custom in custom }
            .values
            .sorted { lhs, rhs in
                if lhs.id == ASRProviderID.appleSpeech { return true }
                if rhs.id == ASRProviderID.appleSpeech { return false }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            .filter(filter.matches)
    }

    func descriptor(id: String) -> ASRProviderDescriptor? {
        descriptors().first { $0.id == id }
    }

    func makeEngine(providerID: String) throws -> ASREngine {
        guard let descriptor = descriptor(id: providerID),
              let engineType = descriptor.engineType else {
            throw ASRProviderRegistryError.providerNotFound
        }
        guard descriptor.isAvailable else {
            throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
        }
        return asrManager.makeEngine(type: engineType)
    }

    func defaultProvider() throws -> ASRProviderDescriptor {
        let preferredID = asrManager.effectiveSelectedEngineType.providerID
        if let descriptor = descriptor(id: preferredID), descriptor.isAvailable {
            return descriptor
        }
        guard let apple = descriptor(id: ASRProviderID.appleSpeech) else {
            throw ASRProviderRegistryError.providerNotFound
        }
        return apple
    }

    func selectDefaultProvider(id: String) throws {
        guard let descriptor = descriptor(id: id),
              let engineType = descriptor.engineType else {
            throw ASRProviderRegistryError.providerNotFound
        }
        guard descriptor.isAvailable else {
            throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
        }
        guard asrManager.selectEngine(engineType) else {
            throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
        }
    }

    func fallbackChain(startingAt providerID: String) -> [ASRProviderDescriptor] {
        var chain: [ASRProviderDescriptor] = []
        if let selected = descriptor(id: providerID), selected.isAvailable {
            chain.append(selected)
        }
        if providerID != ASRProviderID.appleSpeech,
           let apple = descriptor(id: ASRProviderID.appleSpeech),
           apple.isAvailable {
            chain.append(apple)
        }
        return chain
    }

    private func builtInDescriptors() -> [String: ASRProviderDescriptor] {
        let selectedID = asrManager.selectedEngineType.providerID
        let qwenAvailable = asrManager.isQwen3ModelAvailable
        let qwenMessage = qwenAvailable
            ? "本地模型已就绪"
            : "尚未安装本地模型"
        let qwenPrivacySummary = qwenAvailable
            ? "语音仅在本机处理，不会上传。"
            : "请先下载模型，或选择已有的模型文件夹。语音仅在本机处理，不会上传。"

        let apple = ASRProviderDescriptor(
            id: ASRProviderID.appleSpeech,
            displayName: "系统自带",
            providerType: "appleSpeech",
            capabilities: [.streaming, .cloud, .fast, .multilingual, .punctuation],
            tags: ["系统", "流式", "多语言"],
            isAvailable: true,
            isDefault: selectedID == ASRProviderID.appleSpeech,
            statusMessage: "系统语音识别可用",
            privacySummary: "使用系统语音识别能力，可能依赖 Apple 服务。",
            modelSize: nil,
            engineType: .apple
        )
        let qwen = ASRProviderDescriptor(
            id: ASRProviderID.qwen3,
            displayName: "Qwen3-ASR",
            providerType: "qwen3",
            capabilities: [.streaming, .local, .accurate, .multilingual, .punctuation],
            tags: ["本地", "离线", "多语言", asrManager.qwen3ModelSize.rawValue],
            isAvailable: qwenAvailable,
            isDefault: selectedID == ASRProviderID.qwen3,
            statusMessage: qwenMessage,
            privacySummary: qwenPrivacySummary,
            modelSize: asrManager.qwen3ModelSize,
            engineType: .qwen3
        )
        return [
            apple.id: apple,
            qwen.id: qwen,
        ]
    }
}

enum ASRProviderRegistryError: LocalizedError {
    case providerNotFound
    case providerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .providerNotFound:
            return "ASR Provider 不存在。"
        case .providerUnavailable(let name):
            return "\(name) 当前不可用。"
        }
    }
}
