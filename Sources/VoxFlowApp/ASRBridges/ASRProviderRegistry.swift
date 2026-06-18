import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
import VoxFlowProviderFunASR
import VoxFlowProviderNVIDIA
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice

enum ASRProviderID {
    static let appleSpeech = "apple_speech"
    static let funASR = "funasr"
    static let whisper = "whisper"
    static let qwen3 = "qwen3_asr"
    static let paraformer = "paraformer"
    static let senseVoice = "sense_voice"
    static let nvidiaNemotron = "nvidia_nemotron_3_5_asr_streaming_0_6b"
    static let groqWhisper = "groq_whisper"
    static let qwenCloudASR = "qwen_cloud_asr"
    static let mistralVoxtral = "mistral_voxtral"
    static let assemblyAI = "assemblyai"
    static let volcengineDoubao = "volcengine_doubao_asr"
    static let elevenLabsScribe = "elevenlabs_scribe"
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

enum ASRProviderLocalModelAction: Equatable {
    case none
    case download
    case delete
    case repair
}

enum ASRProviderRecordHealthStatus: String, Equatable {
    case ok
    case notInstalled = "not_installed"
    case repairRequired = "repair_required"
    case runtimeUnsupported = "runtime_unsupported"
    case hardwareUnsupported = "hardware_unsupported"
    case insufficientDisk = "insufficient_disk"
    case verificationRequired = "verification_required"
    case unavailable
}

struct ASRProviderExternalLinks: Equatable {
    let apiKeyTitle: String
    let apiKeyURL: URL
    let modelsTitle: String?
    let modelsURL: URL?
    let guideTitle: String?
    let guideURL: URL?

    init(
        apiKeyTitle: String = "获取 API 密钥",
        apiKeyURL: URL,
        modelsTitle: String? = "查看模型",
        modelsURL: URL? = nil,
        guideTitle: String? = nil,
        guideURL: URL? = nil
    ) {
        self.apiKeyTitle = apiKeyTitle
        self.apiKeyURL = apiKeyURL
        self.modelsTitle = modelsTitle
        self.modelsURL = modelsURL
        self.guideTitle = guideTitle
        self.guideURL = guideURL
    }
}

struct ASRProviderDescriptor: Equatable, Identifiable {
    let id: String
    let displayName: String
    let providerType: String
    let capabilities: ASRProviderCapabilities
    let tags: [String]
    let isAvailable: Bool
    let localModelAction: ASRProviderLocalModelAction
    let healthStatus: ASRProviderRecordHealthStatus
    let isDefault: Bool
    let statusMessage: String?
    let privacySummary: String
    let modelSize: ASRManager.ModelSize?
    let engineType: ASREngineType?
    let externalLinks: ASRProviderExternalLinks?

    var supportsLocalModelControls: Bool {
        [
            ASRProviderID.funASR,
            ASRProviderID.nvidiaNemotron,
            ASRProviderID.paraformer,
            ASRProviderID.qwen3,
            ASRProviderID.senseVoice,
            ASRProviderID.whisper,
        ].contains(id)
    }

    init(
        id: String,
        displayName: String,
        providerType: String,
        capabilities: ASRProviderCapabilities,
        tags: [String],
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction = .none,
        healthStatus: ASRProviderRecordHealthStatus? = nil,
        isDefault: Bool,
        statusMessage: String?,
        privacySummary: String,
        modelSize: ASRManager.ModelSize?,
        engineType: ASREngineType?,
        externalLinks: ASRProviderExternalLinks? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.providerType = providerType
        self.capabilities = capabilities
        self.tags = tags
        self.isAvailable = isAvailable
        self.localModelAction = localModelAction
        self.healthStatus = healthStatus ?? (isAvailable ? .ok : .unavailable)
        self.isDefault = isDefault
        self.statusMessage = statusMessage
        self.privacySummary = privacySummary
        self.modelSize = modelSize
        self.engineType = engineType
        self.externalLinks = externalLinks
    }
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
    private static let builtInProviderIDs: Set<String> = [
        ASRProviderID.appleSpeech,
        ASRProviderID.funASR,
        ASRProviderID.whisper,
        ASRProviderID.qwen3,
        ASRProviderID.paraformer,
        ASRProviderID.senseVoice,
        ASRProviderID.nvidiaNemotron,
        ASRProviderID.groqWhisper,
        ASRProviderID.qwenCloudASR,
        ASRProviderID.mistralVoxtral,
        ASRProviderID.assemblyAI,
        ASRProviderID.volcengineDoubao,
        ASRProviderID.elevenLabsScribe,
    ]

    init(asrManager: ASRManager = ASRManager()) {
        self.asrManager = asrManager
    }

    func register(_ descriptor: ASRProviderDescriptor) {
        guard !Self.builtInProviderIDs.contains(descriptor.id) else { return }
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
            if let descriptor = descriptor(id: id) {
                throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
            }
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
        let qwenState = asrManager.qwen3StoredModelInstallationState(for: asrManager.qwen3ModelSize)
        let qwenPresentation = qwenLocalModelPresentation(
            size: asrManager.qwen3ModelSize,
            state: qwenState,
            isAvailable: Self.isReady(qwenState)
        )
        let qwenCoreDescriptor = qwen3CoreDescriptor(
            size: asrManager.qwen3ModelSize,
            state: qwenState
        )

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
            id: qwenCoreDescriptor.id.rawValue,
            displayName: qwenCoreDescriptor.displayName,
            providerType: "qwen3",
            capabilities: [.streaming, .local, .accurate, .multilingual, .punctuation],
            tags: ["本地", "离线"] + languageTags(from: qwenCoreDescriptor) + [asrManager.qwen3ModelSize.rawValue],
            isAvailable: qwenPresentation.isAvailable,
            localModelAction: qwenPresentation.localModelAction,
            healthStatus: qwenPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.qwen3,
            statusMessage: qwenPresentation.statusMessage,
            privacySummary: qwenPresentation.privacySummary,
            modelSize: asrManager.qwen3ModelSize,
            engineType: .qwen3
        )
        let funASRState = asrManager.funASRModelInstallationState(for: asrManager.funASRPrecision)
        let funASRCoreDescriptor = FunASRProviderDescriptor.descriptor(
            precision: FunASRModelVariant(precision: asrManager.funASRPrecision),
            modelInstallationState: Self.asrCoreInstallationState(from: funASRState)
        )
        let funASRPresentation = funASRLocalModelPresentation(
            state: funASRState,
            isAvailable: Self.isReady(funASRState)
        )
        let funASR = ASRProviderDescriptor(
            id: funASRCoreDescriptor.id.rawValue,
            displayName: funASRCoreDescriptor.displayName,
            providerType: "funasr",
            capabilities: [.streaming, .fileTranscription, .local, .accurate, .multilingual, .punctuation],
            tags: ["本地", "离线"] + languageTags(from: funASRCoreDescriptor) + [asrManager.funASRPrecision.rawValue],
            isAvailable: funASRPresentation.isAvailable,
            localModelAction: funASRPresentation.localModelAction,
            healthStatus: funASRPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.funASR,
            statusMessage: funASRPresentation.statusMessage,
            privacySummary: funASRPresentation.privacySummary,
            modelSize: nil,
            engineType: .funASR
        )
        let whisperPresentation = whisperLocalModelPresentation(
            variant: asrManager.whisperVariant,
            isAvailable: Self.isReady(asrManager.whisperModelInstallationState(for: asrManager.whisperVariant))
        )
        let whisper = ASRProviderDescriptor(
            id: ASRProviderID.whisper,
            displayName: "Whisper",
            providerType: "whisper",
            capabilities: [.fileTranscription, .local, .accurate, .multilingual],
            tags: ["本地", "离线", "非流式", "多语言", asrManager.whisperVariant.rawValue],
            isAvailable: whisperPresentation.isAvailable,
            localModelAction: whisperPresentation.localModelAction,
            healthStatus: whisperPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.whisper,
            statusMessage: whisperPresentation.statusMessage,
            privacySummary: whisperPresentation.privacySummary,
            modelSize: nil,
            engineType: .whisper
        )
        let senseVoiceState = asrManager.senseVoiceModelInstallationState()
        let senseVoiceCoreDescriptor = SenseVoiceProviderDescriptor.descriptor(
            modelInstallationState: Self.asrCoreInstallationState(from: senseVoiceState)
        )
        let senseVoicePresentation = senseVoiceLocalModelPresentation(
            state: senseVoiceState,
            isAvailable: Self.isReady(senseVoiceState)
        )
        let senseVoice = ASRProviderDescriptor(
            id: senseVoiceCoreDescriptor.id.rawValue,
            displayName: senseVoiceCoreDescriptor.displayName,
            providerType: "sensevoice",
            capabilities: [.fileTranscription, .local, .fast, .accurate, .multilingual],
            tags: ["本地", "离线", "非流式"] + languageTags(from: senseVoiceCoreDescriptor) + ["FP16"],
            isAvailable: senseVoicePresentation.isAvailable,
            localModelAction: senseVoicePresentation.localModelAction,
            healthStatus: senseVoicePresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.senseVoice,
            statusMessage: senseVoicePresentation.statusMessage,
            privacySummary: senseVoicePresentation.privacySummary,
            modelSize: nil,
            engineType: .senseVoice
        )
        let paraformerState = asrManager.paraformerModelInstallationState()
        let paraformerCoreDescriptor = VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: ASRProviderID.paraformer),
            displayName: "Paraformer Large zh",
            modelInstallationState: Self.asrCoreInstallationState(from: paraformerState),
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
            ],
            streamingSemantics: .rollingWindowConfirmedSegments
        )
        let paraformerPresentation = paraformerLocalModelPresentation(
            state: paraformerState,
            isAvailable: Self.isReady(paraformerState)
        )
        let paraformer = ASRProviderDescriptor(
            id: paraformerCoreDescriptor.id.rawValue,
            displayName: paraformerCoreDescriptor.displayName,
            providerType: "paraformer",
            capabilities: [.streaming, .fileTranscription, .local, .fast, .accurate, .punctuation],
            tags: ["本地", "离线"] + languageTags(from: paraformerCoreDescriptor) + ["0.22B", "INT8"],
            isAvailable: paraformerPresentation.isAvailable,
            localModelAction: paraformerPresentation.localModelAction,
            healthStatus: paraformerPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.paraformer,
            statusMessage: paraformerPresentation.statusMessage,
            privacySummary: paraformerPresentation.privacySummary,
            modelSize: nil,
            engineType: .paraformer
        )
        let nvidiaState = asrManager.nvidiaNemotronModelInstallationState()
        let nvidiaCoreDescriptor = NVIDIANemotronProviderDescriptor.descriptor(
            modelInstallationState: Self.asrCoreInstallationState(from: nvidiaState)
        )
        let nvidiaPresentation = nvidiaNemotronLocalModelPresentation(
            state: nvidiaState,
            isAvailable: Self.isReady(nvidiaState)
        )
        let nvidia = ASRProviderDescriptor(
            id: nvidiaCoreDescriptor.id.rawValue,
            displayName: nvidiaCoreDescriptor.displayName,
            providerType: "nvidiaNemotron",
            capabilities: [.streaming, .fileTranscription, .local, .accurate, .multilingual, .punctuation],
            tags: ["本地", "离线"] + languageTags(from: nvidiaCoreDescriptor) + ["0.6B", "CoreML"],
            isAvailable: nvidiaPresentation.isAvailable,
            localModelAction: nvidiaPresentation.localModelAction,
            healthStatus: nvidiaPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.nvidiaNemotron,
            statusMessage: nvidiaPresentation.statusMessage,
            privacySummary: nvidiaPresentation.privacySummary,
            modelSize: nil,
            engineType: .nvidiaNemotron
        )
        return [
            apple.id: apple,
            funASR.id: funASR,
            nvidia.id: nvidia,
            paraformer.id: paraformer,
            qwen.id: qwen,
            senseVoice.id: senseVoice,
            whisper.id: whisper,
        ].merging(onlineCatalogDescriptors()) { local, _ in local }
    }

    private func onlineCatalogDescriptors() -> [String: ASRProviderDescriptor] {
        let providers = [
            onlineDescriptor(
                id: ASRProviderID.groqWhisper,
                displayName: "Groq (Whisper)",
                providerType: "groq",
                capabilities: [.fileTranscription, .cloud, .fast, .accurate],
                tags: ["在线", "非流式", "快速", "准确", "Whisper"],
                statusMessage: "需要配置 API 密钥",
                privacySummary: "Groq Cloud 托管 Whisper 转写，适合低延迟文件识别。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://console.groq.com/keys")!,
                    modelsURL: URL(string: "https://console.groq.com/docs/speech-to-text")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.qwenCloudASR,
                displayName: "通义千问 ASR",
                providerType: "qwenCloudASR",
                capabilities: [.streaming, .fileTranscription, .cloud, .accurate, .multilingual, .punctuation],
                tags: ["在线", "实时", "准确", "中文", "多语言"],
                statusMessage: "需要配置 API 密钥",
                privacySummary: "阿里云百炼语音识别服务，支持实时和文件识别。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://bailian.console.aliyun.com/?tab=model#/api-key")!,
                    modelsURL: URL(string: "https://help.aliyun.com/zh/model-studio/developer-reference/paraformer-real-time-speech-recognition")!,
                    guideTitle: "配置指南",
                    guideURL: URL(string: "https://help.aliyun.com/zh/model-studio/developer-reference/paraformer-recorded-speech-recognition")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.mistralVoxtral,
                displayName: "Mistral",
                providerType: "mistral",
                capabilities: [.streaming, .fileTranscription, .cloud, .accurate, .multilingual],
                tags: ["在线", "实时", "准确", "Voxtral"],
                statusMessage: "需要配置 API 密钥",
                privacySummary: "Mistral Voxtral 音频转写服务，支持文件和实时转写。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://console.mistral.ai/api-keys")!,
                    modelsURL: URL(string: "https://docs.mistral.ai/studio-api/audio/speech_to_text")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.assemblyAI,
                displayName: "AssemblyAI",
                providerType: "assemblyAI",
                capabilities: [.streaming, .fileTranscription, .cloud, .accurate, .multilingual],
                tags: ["在线", "准确", "多语言"],
                statusMessage: "需要配置 API 密钥",
                privacySummary: "企业级语音识别服务，适合会议、媒体和长音频转写。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://www.assemblyai.com/dashboard/signup")!,
                    modelsURL: URL(string: "https://www.assemblyai.com/products/speech-to-text")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.volcengineDoubao,
                displayName: "火山引擎（豆包语音）",
                providerType: "volcengineDoubao",
                capabilities: [.streaming, .cloud, .fast, .accurate, .punctuation],
                tags: ["在线", "实时", "准确", "中文"],
                statusMessage: "需要配置 API 密钥",
                privacySummary: "火山引擎豆包语音识别服务，适合中文实时转写场景。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey")!,
                    modelsTitle: nil,
                    guideTitle: "配置指南",
                    guideURL: URL(string: "https://www.volcengine.com/docs/82379/1520757")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.elevenLabsScribe,
                displayName: "ElevenLabs",
                providerType: "elevenLabs",
                capabilities: [.streaming, .fileTranscription, .cloud, .accurate, .multilingual],
                tags: ["在线", "实时", "多语言"],
                statusMessage: "需要配置 API 密钥",
                privacySummary: "ElevenLabs Scribe 语音转文字，支持多语言和实时识别。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://elevenlabs.io/app/settings/api-keys")!,
                    modelsURL: URL(string: "https://elevenlabs.io/docs/overview/capabilities/speech-to-text")!
                )
            ),
        ]
        return Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    private func onlineDescriptor(
        id: String,
        displayName: String,
        providerType: String,
        capabilities: ASRProviderCapabilities,
        tags: [String],
        statusMessage: String,
        privacySummary: String,
        links: ASRProviderExternalLinks
    ) -> ASRProviderDescriptor {
        ASRProviderDescriptor(
            id: id,
            displayName: displayName,
            providerType: providerType,
            capabilities: capabilities,
            tags: tags,
            isAvailable: false,
            localModelAction: .none,
            healthStatus: .unavailable,
            isDefault: false,
            statusMessage: statusMessage,
            privacySummary: privacySummary,
            modelSize: nil,
            engineType: nil,
            externalLinks: links
        )
    }

    private func qwen3CoreDescriptor(
        size: ASRManager.ModelSize,
        state: ModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        let coreState = Self.asrCoreInstallationState(from: state)
        return Qwen3ProviderDescriptor.descriptor(modelInstallationState: coreState)
    }

    private static func isReady(_ state: ModelInstallationState) -> Bool {
        if case .ready = state {
            return true
        }
        return false
    }

    private func languageTags(from descriptor: VoxFlowASRCore.ASRProviderDescriptor) -> [String] {
        descriptor.supportedLanguages.map { language in
            switch language.bcp47Tag.lowercased() {
            case let tag where tag.hasPrefix("zh"):
                return "中文"
            case let tag where tag.hasPrefix("en"):
                return "English"
            default:
                return language.bcp47Tag
            }
        }
    }

    private static func asrCoreInstallationState(
        from state: ModelInstallationState
    ) -> VoxFlowASRCore.ASRModelInstallationState {
        switch state {
        case .ready:
            return .ready
        case .downloading(let progress), .paused(let progress):
            return .downloading(progress: progress.fractionCompleted ?? 0)
        case .verifying:
            return .verifying
        case .extracting, .compiling:
            return .compiling
        case .warmingUp, .canaryTesting:
            return .prewarming
        case .corrupt:
            return .corrupt
        case .runtimeUnsupported(let reason):
            return .runtimeUnsupported(reason: reason)
        case .hardwareUnsupported(let reason):
            return .hardwareUnsupported(reason: reason)
        case .failed(let message):
            return .failed(message: message)
        case .notInstalled,
             .insufficientDisk:
            return .notInstalled
        }
    }

    private func qwenLocalModelPresentation(
        size: ASRManager.ModelSize,
        state: ModelInstallationState,
        isAvailable: Bool
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        switch state {
        case .ready where isAvailable:
            return (
                true,
                .delete,
                .ok,
                "本地模型已就绪",
                "语音仅在本机处理，不会上传。"
            )
        case .corrupt(let reason):
            return (
                false,
                .repair,
                .repairRequired,
                "模型损坏，需要修复：\(reason)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
            )
        case .runtimeUnsupported(let reason):
            return (
                false,
                .none,
                .runtimeUnsupported,
                "运行时不支持：\(reason)",
                "当前设备或运行时暂不可用。语音仅在本机处理，不会上传。"
            )
        case .hardwareUnsupported(let reason):
            return (
                false,
                .none,
                .hardwareUnsupported,
                "硬件不支持：\(reason)",
                "当前设备暂不可用。语音仅在本机处理，不会上传。"
            )
        case .insufficientDisk:
            return (
                false,
                .none,
                .insufficientDisk,
                "磁盘空间不足",
                "请释放磁盘空间后再下载模型。语音仅在本机处理，不会上传。"
            )
        default:
            return (
                false,
                .download,
                .notInstalled,
                "尚未安装本地模型",
                "请先下载模型，或选择已有的模型文件夹。语音仅在本机处理，不会上传。"
            )
        }
    }

    private func whisperLocalModelPresentation(
        variant: ASRManager.WhisperVariant,
        isAvailable: Bool
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        guard ASRManager.isWhisperRuntimeSupported(variant: variant) else {
            return (
                false,
                .none,
                .runtimeUnsupported,
                ASRManager.whisperRuntimeUnsupportedMessage(for: variant),
                "当前 Whisper \(variant.rawValue) 本地运行时暂不可用。语音仅在本机处理，不会上传。"
            )
        }
        if isAvailable {
            return (
                true,
                .delete,
                .ok,
                "本地模型已就绪",
                "Whisper \(variant.rawValue) 多语言离线识别。"
            )
        }
        return (
            false,
            .download,
            .notInstalled,
            "尚未安装本地模型",
            "Whisper \(variant.rawValue) 多语言离线识别。"
        )
    }

    private func funASRLocalModelPresentation(
        state: ModelInstallationState,
        isAvailable: Bool
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        switch state {
        case .ready where isAvailable:
            return (
                true,
                .delete,
                .ok,
                "本地模型已就绪",
                "FunASR Nano \(asrManager.funASRPrecision.rawValue) 中文/English 离线识别。"
            )
        case .corrupt(let reason):
            return (
                false,
                .repair,
                .repairRequired,
                "模型损坏，需要修复：\(reason)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
            )
        case .runtimeUnsupported(let reason):
            return (
                false,
                .none,
                .runtimeUnsupported,
                "运行时不支持：\(reason)",
                "当前设备或运行时暂不可用。语音仅在本机处理，不会上传。"
            )
        case .hardwareUnsupported(let reason):
            return (
                false,
                .none,
                .hardwareUnsupported,
                "硬件不支持：\(reason)",
                "当前设备暂不可用。语音仅在本机处理，不会上传。"
            )
        case .insufficientDisk:
            return (
                false,
                .none,
                .insufficientDisk,
                "磁盘空间不足",
                "请释放磁盘空间后再下载模型。语音仅在本机处理，不会上传。"
            )
        default:
            return (
                false,
                .download,
                .notInstalled,
                "尚未安装本地模型",
                "FunASR Nano \(asrManager.funASRPrecision.rawValue) 中文/English 离线识别。"
            )
        }
    }

    private func paraformerLocalModelPresentation(
        state: ModelInstallationState,
        isAvailable: Bool
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        switch state {
        case .ready where isAvailable:
            return (true, .delete, .ok, "本地模型已就绪", "Paraformer Large zh 中文离线识别。语音仅在本机处理，不会上传。")
        case .corrupt(let reason):
            return (false, .repair, .repairRequired, "模型损坏，需要修复：\(reason)", "模型需要修复后才能使用。语音仅在本机处理，不会上传。")
        case .failed(let message):
            return (false, .repair, .repairRequired, "模型准备失败：\(message)", "模型需要修复后才能使用。语音仅在本机处理，不会上传。")
        default:
            return (false, .download, .notInstalled, "尚未安装本地模型", "Paraformer Large zh 中文离线识别。语音仅在本机处理，不会上传。")
        }
    }

    private func nvidiaNemotronLocalModelPresentation(
        state: ModelInstallationState,
        isAvailable: Bool
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        switch state {
        case .ready where isAvailable:
            return (true, .delete, .ok, "本地模型已就绪", "NVIDIA Nemotron 0.6B CoreML 多语言流式离线识别。")
        case .runtimeUnsupported(let reason):
            return (false, .none, .runtimeUnsupported, "运行时不支持：\(reason)", "当前设备暂不可用。语音仅在本机处理，不会上传。")
        case .hardwareUnsupported(let reason):
            return (false, .none, .hardwareUnsupported, "硬件不支持：\(reason)", "当前设备暂不可用。语音仅在本机处理，不会上传。")
        case .corrupt(let reason):
            return (false, .repair, .repairRequired, "模型损坏，需要修复：\(reason)", "模型需要修复后才能使用。语音仅在本机处理，不会上传。")
        case .failed(let message):
            return (false, .repair, .repairRequired, "模型准备失败：\(message)", "模型需要修复后才能使用。语音仅在本机处理，不会上传。")
        default:
            return (false, .download, .notInstalled, "尚未安装本地模型", "NVIDIA Nemotron 0.6B CoreML 多语言流式离线识别。")
        }
    }

    private func senseVoiceLocalModelPresentation(
        state: ModelInstallationState,
        isAvailable: Bool
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        switch state {
        case .ready where isAvailable:
            return (
                true,
                .delete,
                .ok,
                "本地模型已就绪",
                "中文/English 离线识别，录音结束后在本机完成推理。"
            )
        case .corrupt(let reason):
            return (
                false,
                .repair,
                .repairRequired,
                "模型损坏，需要修复：\(reason)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
            )
        case .runtimeUnsupported(let reason):
            return (
                false,
                .none,
                .runtimeUnsupported,
                "运行时不支持：\(reason)",
                "当前设备或运行时暂不可用。语音仅在本机处理，不会上传。"
            )
        case .hardwareUnsupported(let reason):
            return (
                false,
                .none,
                .hardwareUnsupported,
                "硬件不支持：\(reason)",
                "当前设备暂不可用。语音仅在本机处理，不会上传。"
            )
        case .insufficientDisk:
            return (
                false,
                .none,
                .insufficientDisk,
                "磁盘空间不足",
                "请释放磁盘空间后再下载模型。语音仅在本机处理，不会上传。"
            )
        default:
            return (
                false,
                .download,
                .notInstalled,
                "尚未安装本地模型",
                "中文/English 离线识别，录音结束后在本机完成推理。"
            )
        }
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
