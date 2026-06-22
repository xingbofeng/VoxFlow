import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
import VoxFlowProviderFunASR
import VoxFlowProviderNVIDIA
import VoxFlowProviderOmnilingual
import VoxFlowProviderParakeet
import VoxFlowProviderParaformer
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
    static let parakeetStreaming = "parakeet_streaming"
    static let omnilingualASR = "omnilingual_asr"
    static let groqWhisper = "groq_whisper"
    static let tencentCloudASR = "tencent_cloud_asr"
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

    var simpleFilterTags: [String] {
        var tags: [String] = []
        if contains(.fast) {
            tags.append("快速")
        }
        if contains(.accurate) {
            tags.append("准确")
        }
        return tags
    }
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
            ASRProviderID.parakeetStreaming,
            ASRProviderID.omnilingualASR,
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

private extension ASRProviderDescriptor {
    func replacingStatusMessage(_ statusMessage: String) -> ASRProviderDescriptor {
        ASRProviderDescriptor(
            id: id,
            displayName: displayName,
            providerType: providerType,
            capabilities: capabilities,
            tags: tags,
            isAvailable: isAvailable,
            localModelAction: localModelAction,
            healthStatus: healthStatus,
            isDefault: isDefault,
            statusMessage: statusMessage,
            privacySummary: privacySummary,
            modelSize: modelSize,
            engineType: engineType,
            externalLinks: externalLinks
        )
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
        let searchableTags = Set(
            descriptor.tags
                + descriptor.capabilities.simpleFilterTags
                + ASRProviderTagPresentation.cardTags(for: descriptor)
        )
        if !tags.isEmpty && !tags.isSubset(of: searchableTags) {
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
        ASRProviderID.parakeetStreaming,
        ASRProviderID.omnilingualASR,
        ASRProviderID.groqWhisper,
        ASRProviderID.tencentCloudASR,
        ASRProviderID.qwenCloudASR,
        ASRProviderID.mistralVoxtral,
        ASRProviderID.assemblyAI,
        ASRProviderID.volcengineDoubao,
        ASRProviderID.elevenLabsScribe,
    ]
    private static let localProviderDisplayOrder = [
        ASRProviderID.appleSpeech,
        ASRProviderID.qwen3,
        ASRProviderID.funASR,
        ASRProviderID.nvidiaNemotron,
        ASRProviderID.parakeetStreaming,
        ASRProviderID.omnilingualASR,
        ASRProviderID.paraformer,
        ASRProviderID.senseVoice,
        ASRProviderID.whisper,
    ]
    private static let onlineProviderDisplayOrder = [
        ASRProviderID.groqWhisper,
        ASRProviderID.tencentCloudASR,
        ASRProviderID.qwenCloudASR,
        ASRProviderID.volcengineDoubao,
        ASRProviderID.mistralVoxtral,
        ASRProviderID.assemblyAI,
        ASRProviderID.elevenLabsScribe,
    ]
    private static let providerDisplayRank: [String: Int] = {
        let localRanks = localProviderDisplayOrder.enumerated().map { ($0.element, $0.offset) }
        let onlineRanks = onlineProviderDisplayOrder.enumerated().map { ($0.element, 10_000 + $0.offset) }
        return Dictionary(uniqueKeysWithValues: localRanks + onlineRanks)
    }()

    init(asrManager: ASRManager = ASRManager()) {
        self.asrManager = asrManager
    }

    func register(_ descriptor: ASRProviderDescriptor) {
        guard !Self.builtInProviderIDs.contains(descriptor.id) else { return }
        customDescriptors[descriptor.id] = descriptor
    }

    func descriptors(matching filter: ASRProviderFilter = ASRProviderFilter()) -> [ASRProviderDescriptor] {
        let result = builtInDescriptors()
            .merging(customDescriptors) { _, custom in custom }
            .values
            .sorted { lhs, rhs in
                let lhsRank = Self.providerDisplayRank[lhs.id] ?? Self.fallbackDisplayRank(for: lhs)
                let rhsRank = Self.providerDisplayRank[rhs.id] ?? Self.fallbackDisplayRank(for: rhs)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            .filter(filter.matches)
        AppLogger.general.debug(
            "ASR descriptors prepared: total=\(result.count), filterAvailableOnly=\(filter.availableOnly)"
        )
        return result
    }

    func offlineDescriptors() -> [ASRProviderDescriptor] {
        descriptors().filter { descriptor in
            descriptor.id == ASRProviderID.appleSpeech || descriptor.capabilities.contains(.local)
        }
    }

    func descriptor(id: String) -> ASRProviderDescriptor? {
        descriptors().first { $0.id == id }
    }

    func makeEngine(providerID: String) throws -> ASREngine {
        AppLogger.general.info("Create ASR engine from provider: \(providerID)")
        guard let descriptor = descriptor(id: providerID),
              let engineType = descriptor.engineType else {
            AppLogger.general.warning("Provider not found for engine creation: \(providerID)")
            throw ASRProviderRegistryError.providerNotFound
        }
        guard descriptor.isAvailable else {
            AppLogger.general.warning("Provider unavailable for engine creation: \(providerID)")
            throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
        }
        AppLogger.general.info("Provider available for engine creation: \(providerID)")
        return asrManager.makeEngine(type: engineType)
    }

    func defaultProvider() throws -> ASRProviderDescriptor {
        let preferredID = asrManager.effectiveSelectedEngineType.providerID
        if let descriptor = descriptor(id: preferredID), descriptor.isAvailable {
            AppLogger.general.debug("Default provider resolved to selected: \(preferredID)")
            return descriptor
        }
        guard let apple = descriptor(id: ASRProviderID.appleSpeech) else {
            AppLogger.general.error("Default provider fallback failed: apple speech descriptor missing")
            throw ASRProviderRegistryError.providerNotFound
        }
        AppLogger.general.info("Default provider fallback to apple speech")
        return apple
    }

    func selectDefaultProvider(id: String) throws {
        AppLogger.general.info("selectDefaultProvider requested: \(id)")
        guard let descriptor = descriptor(id: id),
              let engineType = descriptor.engineType else {
            if let descriptor = descriptor(id: id) {
                AppLogger.general.warning("Default provider unavailable: \(id)")
                throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
            }
            AppLogger.general.warning("Default provider not found: \(id)")
            throw ASRProviderRegistryError.providerNotFound
        }
        guard descriptor.isAvailable else {
            AppLogger.general.warning("Default provider not available for selection: \(descriptor.displayName)")
            throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
        }
        guard asrManager.selectEngine(engineType) else {
            AppLogger.general.warning("Failed to select default provider engine type: \(engineType.rawValue)")
            throw ASRProviderRegistryError.providerUnavailable(descriptor.displayName)
        }
        AppLogger.general.info("Default provider selected: \(descriptor.displayName)")
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
        AppLogger.general.debug(
            "ASR fallback chain: \(chain.map(\.displayName).joined(separator: ","))"
        )
        return chain
    }

    private static func fallbackDisplayRank(for descriptor: ASRProviderDescriptor) -> Int {
        if descriptor.tags.contains("在线") || descriptor.externalLinks != nil {
            return 10_000
        }
        if descriptor.tags.contains("本地") || descriptor.tags.contains("离线") {
            return 1_000
        }
        return 5_000
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
            capabilities: [.streaming, .fast, .multilingual, .punctuation],
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
        let whisperState = asrManager.whisperModelInstallationState(for: asrManager.whisperVariant)
        let whisperPresentation = whisperLocalModelPresentation(
            variant: asrManager.whisperVariant,
            state: whisperState,
            isAvailable: Self.isReady(whisperState)
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
            capabilities: [.streaming, .fileTranscription, .local, .fast, .accurate, .multilingual],
            tags: ["本地", "离线"] + languageTags(from: senseVoiceCoreDescriptor) + ["FP16"],
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
        let paraformerCoreDescriptor = ParaformerProviderDescriptor.descriptor(
            modelInstallationState: Self.asrCoreInstallationState(from: paraformerState)
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
        let parakeetState = asrManager.parakeetModelInstallationState()
        let parakeetCoreDescriptor = ParakeetProviderDescriptor.descriptor(
            modelInstallationState: Self.asrCoreInstallationState(from: parakeetState)
        )
        let parakeetPresentation = speechSwiftLocalModelPresentation(
            state: parakeetState,
            isAvailable: Self.isReady(parakeetState),
            readySummary: "Parakeet EOU 120M CoreML 英文/欧洲语种流式离线识别。",
            missingSummary: "Parakeet EOU 120M CoreML 英文/欧洲语种流式离线识别。语音仅在本机处理，不会上传。"
        )
        let parakeet = ASRProviderDescriptor(
            id: parakeetCoreDescriptor.id.rawValue,
            displayName: parakeetCoreDescriptor.displayName,
            providerType: "parakeetStreaming",
            capabilities: [.streaming, .local, .fast, .multilingual, .punctuation],
            tags: ["本地", "离线"] + languageTags(from: parakeetCoreDescriptor) + ["120M", "CoreML"],
            isAvailable: parakeetPresentation.isAvailable,
            localModelAction: parakeetPresentation.localModelAction,
            healthStatus: parakeetPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.parakeetStreaming,
            statusMessage: parakeetPresentation.statusMessage,
            privacySummary: parakeetPresentation.privacySummary,
            modelSize: nil,
            engineType: .parakeetStreaming
        )
        let omnilingualState = asrManager.omnilingualModelInstallationState()
        let omnilingualCoreDescriptor = OmnilingualProviderDescriptor.descriptor(
            modelInstallationState: Self.asrCoreInstallationState(from: omnilingualState)
        )
        let omnilingualPresentation = speechSwiftLocalModelPresentation(
            state: omnilingualState,
            isAvailable: Self.isReady(omnilingualState),
            readySummary: "Omnilingual ASR 300M CoreML 超多语言离线转写。",
            missingSummary: "Omnilingual ASR 300M CoreML 超多语言离线转写，适合文件/实验场景。语音仅在本机处理，不会上传。"
        )
        let omnilingual = ASRProviderDescriptor(
            id: omnilingualCoreDescriptor.id.rawValue,
            displayName: omnilingualCoreDescriptor.displayName,
            providerType: "omnilingualASR",
            capabilities: [.fileTranscription, .local, .multilingual],
            tags: ["本地", "离线", "非流式"] + languageTags(from: omnilingualCoreDescriptor) + ["300M", "CoreML"],
            isAvailable: omnilingualPresentation.isAvailable,
            localModelAction: omnilingualPresentation.localModelAction,
            healthStatus: omnilingualPresentation.healthStatus,
            isDefault: selectedID == ASRProviderID.omnilingualASR,
            statusMessage: omnilingualPresentation.statusMessage,
            privacySummary: omnilingualPresentation.privacySummary,
            modelSize: nil,
            engineType: .omnilingualASR
        )
        let localDescriptors = [
            apple,
            funASR,
            nvidia,
            parakeet,
            omnilingual,
            paraformer,
            qwen,
            senseVoice,
            whisper,
        ].map { applyingSelectedUnavailableRecovery(to: $0) }
        return Dictionary(uniqueKeysWithValues: localDescriptors.map { ($0.id, $0) })
            .merging(onlineCatalogDescriptors()) { local, _ in local }
    }

    private func applyingSelectedUnavailableRecovery(
        to descriptor: ASRProviderDescriptor
    ) -> ASRProviderDescriptor {
        guard descriptor.isDefault,
              !descriptor.isAvailable,
              let selectedEngineType = descriptor.engineType,
              let notice = asrManager.selectionFallbackNotice,
              notice.selectedEngineType == selectedEngineType else {
            return descriptor
        }
        let baseMessage = descriptor.statusMessage ?? "\(descriptor.displayName) 当前不可用"
        let recoveryMessage = "\(baseMessage)。请下载、修复或重新选择模型。"
        return descriptor.replacingStatusMessage(recoveryMessage)
    }

    private func onlineCatalogDescriptors() -> [String: ASRProviderDescriptor] {
        let selectedID = asrManager.selectedEngineType.providerID
        let groqAvailable = asrManager.canSelectEngine(.groqWhisper)
        let tencentAvailable = asrManager.canSelectEngine(.tencentCloud)
        let aliyunAvailable = asrManager.canSelectEngine(.aliyunDashScope)
        let providers = [
            onlineDescriptor(
                id: ASRProviderID.groqWhisper,
                displayName: "Groq（免费）",
                providerType: "groq",
                capabilities: [.fileTranscription, .cloud, .fast, .accurate],
                tags: ["在线", "非流式", "快速", "准确", "Whisper"],
                isAvailable: groqAvailable,
                isDefault: selectedID == ASRProviderID.groqWhisper,
                engineType: .groqWhisper,
                statusMessage: groqAvailable ? "已配置，可用于云端听写" : "需要配置 API 密钥",
                privacySummary: "Groq Cloud 托管 Whisper 转写，适合低延迟文件识别。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://console.groq.com/keys")!,
                    modelsURL: URL(string: "https://console.groq.com/docs/speech-to-text")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.tencentCloudASR,
                displayName: "腾讯云",
                providerType: "tencentCloudASR",
                capabilities: [.streaming, .cloud, .accurate, .punctuation],
                tags: ["在线", "实时", "准确", "中文"],
                isAvailable: tencentAvailable,
                isDefault: selectedID == ASRProviderID.tencentCloudASR,
                engineType: tencentAvailable ? .tencentCloud : nil,
                statusMessage: tencentAvailable
                    ? "已配置，可用于实时云端听写"
                    : "需要配置 AppID、SecretId 和 SecretKey",
                privacySummary: "腾讯云实时语音识别会把录音流式发送到腾讯云，适合中文普通话实时听写。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://console.cloud.tencent.com/cam/capi")!,
                    modelsTitle: nil,
                    guideTitle: "官方文档",
                    guideURL: URL(string: "https://cloud.tencent.com/document/product/1093/48982")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.qwenCloudASR,
                displayName: "阿里云",
                providerType: "qwenCloudASR",
                capabilities: [.streaming, .cloud, .accurate, .multilingual, .punctuation],
                tags: ["在线", "实时", "准确", "中文", "多语言"],
                isAvailable: aliyunAvailable,
                isDefault: selectedID == ASRProviderID.qwenCloudASR,
                engineType: aliyunAvailable ? .aliyunDashScope : nil,
                statusMessage: aliyunAvailable
                    ? "已配置，可用于实时云端听写"
                    : "请先配置百炼访问密钥",
                privacySummary: "阿里云百炼 DashScope 实时语音识别会把录音流式发送到阿里云，适合中文和多语言实时听写。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://bailian.console.aliyun.com/?tab=model#/api-key")!,
                    modelsURL: URL(string: "https://help.aliyun.com/zh/model-studio/real-time-speech-recognition-user-guide")!,
                    guideTitle: "配置指南",
                    guideURL: URL(string: "https://help.aliyun.com/zh/model-studio/websocket-for-paraformer-real-time-service")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.volcengineDoubao,
                displayName: "火山云",
                providerType: "volcengineDoubao",
                capabilities: [.streaming, .cloud, .fast, .accurate, .punctuation],
                tags: ["在线", "实时", "准确", "中文"],
                statusMessage: "暂未支持",
                privacySummary: "火山云语音识别接入尚未实现，暂不能选择。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey")!,
                    modelsTitle: nil,
                    guideTitle: "配置指南",
                    guideURL: URL(string: "https://www.volcengine.com/docs/82379/1520757")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.mistralVoxtral,
                displayName: "Mistral",
                providerType: "mistral",
                capabilities: [.streaming, .fileTranscription, .cloud, .accurate, .multilingual],
                tags: ["在线", "实时", "准确", "Voxtral"],
                statusMessage: "暂未支持",
                privacySummary: "Mistral Voxtral 接入尚未实现，暂不能选择。",
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
                statusMessage: "暂未支持",
                privacySummary: "AssemblyAI 接入尚未实现，暂不能选择。",
                links: ASRProviderExternalLinks(
                    apiKeyURL: URL(string: "https://www.assemblyai.com/dashboard/signup")!,
                    modelsURL: URL(string: "https://www.assemblyai.com/products/speech-to-text")!
                )
            ),
            onlineDescriptor(
                id: ASRProviderID.elevenLabsScribe,
                displayName: "ElevenLabs",
                providerType: "elevenLabs",
                capabilities: [.streaming, .fileTranscription, .cloud, .accurate, .multilingual],
                tags: ["在线", "实时", "多语言"],
                statusMessage: "暂未支持",
                privacySummary: "ElevenLabs Scribe 接入尚未实现，暂不能选择。",
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
        isAvailable: Bool = false,
        isDefault: Bool = false,
        engineType: ASREngineType? = nil,
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
            isAvailable: isAvailable,
            localModelAction: .none,
            healthStatus: isAvailable ? .ok : .unavailable,
            isDefault: isDefault,
            statusMessage: statusMessage,
            privacySummary: privacySummary,
            modelSize: nil,
            engineType: engineType,
            externalLinks: links
        )
    }

    private func qwen3CoreDescriptor(
        size: ASRManager.ModelSize,
        state: ModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        let coreState = Self.asrCoreInstallationState(from: state)
        return Qwen3ProviderDescriptor.descriptor(
            modelInstallationState: coreState,
            variant: Qwen3ModelVariant(size: size)
        )
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
        case .verifying, .deleting(_):
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
        case .deleting(_):
            return (
                false,
                .none,
                .notInstalled,
                "正在删除本地模型...",
                "删除完成前无法使用该模型。语音仅在本机处理，不会上传。"
            )
        case .failed(let message):
            return (
                false,
                .repair,
                .repairRequired,
                "模型准备失败：\(message)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
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
        state: ModelInstallationState,
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
        switch state {
        case .deleting(_):
            return (
                false,
                .none,
                .notInstalled,
                "正在删除本地模型...",
                "删除完成前无法使用 Whisper \(variant.rawValue)。语音仅在本机处理，不会上传。"
            )
        case .failed(let message):
            return (
                false,
                .repair,
                .repairRequired,
                "模型准备失败：\(message)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
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
                "Whisper \(variant.rawValue) 多语言离线识别。"
            )
        }
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
        case .deleting(_):
            return (
                false,
                .none,
                .notInstalled,
                "正在删除本地模型...",
                "删除完成前无法使用 FunASR。语音仅在本机处理，不会上传。"
            )
        case .failed(let message):
            return (
                false,
                .repair,
                .repairRequired,
                "模型准备失败：\(message)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
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
        case .deleting(_):
            return (false, .none, .notInstalled, "正在删除本地模型...", "删除完成前无法使用 Paraformer。语音仅在本机处理，不会上传。")
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
        case .deleting(_):
            return (false, .none, .notInstalled, "正在删除本地模型...", "删除完成前无法使用 NVIDIA Nemotron。语音仅在本机处理，不会上传。")
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

    private func speechSwiftLocalModelPresentation(
        state: ModelInstallationState,
        isAvailable: Bool,
        readySummary: String,
        missingSummary: String
    ) -> (
        isAvailable: Bool,
        localModelAction: ASRProviderLocalModelAction,
        healthStatus: ASRProviderRecordHealthStatus,
        statusMessage: String,
        privacySummary: String
    ) {
        switch state {
        case .ready where isAvailable:
            return (true, .delete, .ok, "本地模型已就绪", readySummary)
        case .deleting(_):
            return (false, .none, .notInstalled, "正在删除本地模型...", "删除完成前无法使用该模型。语音仅在本机处理，不会上传。")
        case .runtimeUnsupported(let reason):
            return (false, .none, .runtimeUnsupported, "运行时不支持：\(reason)", "当前设备暂不可用。语音仅在本机处理，不会上传。")
        case .hardwareUnsupported(let reason):
            return (false, .none, .hardwareUnsupported, "硬件不支持：\(reason)", "当前设备暂不可用。语音仅在本机处理，不会上传。")
        case .corrupt(let reason):
            return (false, .repair, .repairRequired, "模型损坏，需要修复：\(reason)", "模型需要修复后才能使用。语音仅在本机处理，不会上传。")
        case .failed(let message):
            return (false, .repair, .repairRequired, "模型准备失败：\(message)", "模型需要修复后才能使用。语音仅在本机处理，不会上传。")
        default:
            return (false, .download, .notInstalled, "尚未安装本地模型", missingSummary)
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
        case .deleting(_):
            return (
                false,
                .none,
                .notInstalled,
                "正在删除本地模型...",
                "删除完成前无法使用 SenseVoice。语音仅在本机处理，不会上传。"
            )
        case .failed(let message):
            return (
                false,
                .repair,
                .repairRequired,
                "模型准备失败：\(message)",
                "模型需要修复后才能使用。语音仅在本机处理，不会上传。"
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
            return "该语音模型服务不存在。"
        case .providerUnavailable(let name):
            return "\(name) 当前不可用。"
        }
    }
}
