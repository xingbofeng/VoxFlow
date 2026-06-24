import Foundation

protocol CapabilityModelDownloading: AnyObject, Sendable {
    func isInstalled(modelID: String) -> Bool
    func download(modelID: String, progress: @escaping @Sendable (Double, String) -> Void) async throws
}

final class EmptyCapabilityModelDownloader: CapabilityModelDownloading {
    func isInstalled(modelID: String) -> Bool { false }

    func download(modelID: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(1.0, "Model loaded")
    }
}

enum CapabilityModelID {
    static let systemDefaultTTS = "system.default.tts"
    static let systemDefaultTranslation = "system.default.translation"
    static let llmTranslation = "llm.configured.translation"
    static let kokoroTTS = "soniqo.kokoro-tts"
    static let qwen3TTS06B4Bit = "soniqo.qwen3-tts-0.6b-4bit"
    static let cosyVoice3 = "soniqo.cosyvoice3"
    static let madladTranslation = "soniqo.madlad-translation"

    static func isSystemDefault(_ id: String) -> Bool {
        id == systemDefaultTTS || id == systemDefaultTranslation
    }

    static func isBuiltInOption(_ id: String) -> Bool {
        isSystemDefault(id) || id == llmTranslation
    }
}

enum CapabilityModelKind: String, Sendable {
    case tts
    case translation
}

struct CapabilityModelDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let kind: CapabilityModelKind
    let displayName: String
    let subtitle: String
    let sizeDescription: String
    let memoryDescription: String
    let fallbackDescription: String
    let isRecommended: Bool
    var isInstalled: Bool
}

enum CapabilityModelCatalog {
    static func models(for kind: CapabilityModelKind) -> [CapabilityModelDescriptor] {
        switch kind {
        case .tts:
            return [
                CapabilityModelDescriptor(
                    id: CapabilityModelID.systemDefaultTTS,
                    kind: .tts,
                    displayName: "系统默认",
                    subtitle: "使用 Apple 系统朗读，不需要下载模型",
                    sizeDescription: "系统内置",
                    memoryDescription: "由系统管理",
                    fallbackDescription: "始终可用",
                    isRecommended: true,
                    isInstalled: true
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.kokoroTTS,
                    kind: .tts,
                    displayName: "Kokoro TTS",
                    subtitle: "轻量 CoreML 朗读模型，适合 HUD 快速朗读",
                    sizeDescription: "89 MB",
                    memoryDescription: "峰值约 200 MB",
                    fallbackDescription: "未下载时使用 Apple 系统朗读",
                    isRecommended: false,
                    isInstalled: false
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.qwen3TTS06B4Bit,
                    kind: .tts,
                    displayName: "Qwen3-TTS 0.6B 4-bit",
                    subtitle: "Soniqo Qwen3-TTS 基础模型，质量更高但体积更大",
                    sizeDescription: "1.7 GB",
                    memoryDescription: "峰值约 2 GB",
                    fallbackDescription: "未下载时使用 Apple 系统朗读",
                    isRecommended: false,
                    isInstalled: false
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.cosyVoice3,
                    kind: .tts,
                    displayName: "CosyVoice3",
                    subtitle: "多语种 TTS 模型，适合更自然的朗读候选",
                    sizeDescription: "1.2 GB",
                    memoryDescription: "峰值约 1.5 GB",
                    fallbackDescription: "未下载时使用 Apple 系统朗读",
                    isRecommended: false,
                    isInstalled: false
                ),
            ]
        case .translation:
            return [
                CapabilityModelDescriptor(
                    id: CapabilityModelID.systemDefaultTranslation,
                    kind: .translation,
                    displayName: "系统默认",
                    subtitle: "Apple 系统翻译暂不可用",
                    sizeDescription: "系统内置",
                    memoryDescription: "由系统管理",
                    fallbackDescription: "Apple 系统翻译暂不可用",
                    isRecommended: true,
                    isInstalled: true
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.llmTranslation,
                    kind: .translation,
                    displayName: "智能模型配置",
                    subtitle: "使用设置中配置的智能模型，将识别原文翻译为简体中文",
                    sizeDescription: "无需下载",
                    memoryDescription: "由智能模型服务管理",
                    fallbackDescription: "需要先在设置中配置智能模型服务",
                    isRecommended: false,
                    isInstalled: true
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.madladTranslation,
                    kind: .translation,
                    displayName: "Soniqo MADLAD",
                    subtitle: "本地翻译模型，识别原文固定翻译为简体中文",
                    sizeDescription: "约 1.7 GB",
                    memoryDescription: "本地 MLX 推理",
                    fallbackDescription: "未下载时使用已配置的智能模型",
                    isRecommended: false,
                    isInstalled: false
                ),
            ]
        }
    }
}

@MainActor
final class CapabilityModelViewModel: ObservableObject {
    private static let logger = AppLogger.general

    @Published private(set) var models: [CapabilityModelDescriptor]
    @Published private(set) var selectedModelID: String
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    let kind: CapabilityModelKind
    private let downloader: any CapabilityModelDownloading
    private let defaults: UserDefaults

    init(
        kind: CapabilityModelKind,
        downloader: any CapabilityModelDownloading = SoniqoCapabilityModelDownloader(),
        defaults: UserDefaults = .standard
    ) {
        self.kind = kind
        self.downloader = downloader
        self.defaults = defaults
        Self.logger.debug("capability_model_vm_init_start kind=\(kind.rawValue)")
        let catalogModels = CapabilityModelCatalog.models(for: kind).map { model in
            var mutable = model
            mutable.isInstalled = CapabilityModelID.isBuiltInOption(model.id) || downloader.isInstalled(modelID: model.id)
            return mutable
        }
        let selectedModelID = Self.selectedModelID(
            kind: kind,
            models: catalogModels,
            defaults: defaults
        )
        self.models = Self.models(catalogModels, withSelectedFirst: selectedModelID)
        self.selectedModelID = selectedModelID
        Self.logger.info("capability_model_vm_init_success kind=\(kind.rawValue) models=\(models.count) selected=\(selectedModelID)")
    }

    func selectModel(id: String) {
        Self.logger.debug("capability_model_vm_select_model_start kind=\(kind.rawValue) id=\(id)")
        guard models.contains(where: { $0.id == id }) else {
            Self.logger.warning("capability_model_vm_select_model_skipped kind=\(kind.rawValue) id=\(id)")
            return
        }
        selectedModelID = id
        models = Self.models(models, withSelectedFirst: id)
        defaults.set(id, forKey: Self.selectedModelDefaultsKey(kind: kind))
        lastError = nil
        lastActionMessage = "已切换模型配置"
        Self.logger.info("capability_model_vm_select_model_success kind=\(kind.rawValue) id=\(id)")
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
        Self.logger.debug("capability_model_vm_clear_feedback kind=\(kind.rawValue)")
    }

    func downloadModel(id: String) async {
        guard !isDownloading else {
            Self.logger.debug("capability_model_vm_download_skipped kind=\(kind.rawValue) id=\(id) alreadyDownloading=true")
            return
        }
        guard models.contains(where: { $0.id == id }) else {
            Self.logger.warning("capability_model_vm_download_skipped kind=\(kind.rawValue) id=\(id) missingModel=true")
            return
        }
        guard !CapabilityModelID.isBuiltInOption(id) else {
            markInstalled(id: id, installed: true)
            lastError = nil
            lastActionMessage = "已切换内置模型"
            Self.logger.info("capability_model_vm_download_builtin kind=\(kind.rawValue) id=\(id)")
            return
        }
        Self.logger.info("capability_model_vm_download_start kind=\(kind.rawValue) id=\(id)")
        isDownloading = true
        downloadingModelID = id
        downloadProgress = nil
        lastError = nil
        lastActionMessage = nil
        defer {
            isDownloading = false
            downloadingModelID = nil
        }

        do {
            try await downloader.download(modelID: id) { [weak self] progress, _ in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            markInstalled(id: id, installed: true)
            downloadProgress = 1.0
            lastActionMessage = "本地模型下载完成"
            Self.logger.info("capability_model_vm_download_success kind=\(kind.rawValue) id=\(id)")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("capability_model_vm_download_failed kind=\(kind.rawValue) id=\(id) error=\(error.localizedDescription)")
        }
    }

    private func markInstalled(id: String, installed: Bool) {
        guard let index = models.firstIndex(where: { $0.id == id }) else {
            Self.logger.warning("capability_model_vm_mark_installed_skipped kind=\(kind.rawValue) id=\(id)")
            return
        }
        models[index].isInstalled = installed
        Self.logger.debug("capability_model_vm_mark_installed kind=\(kind.rawValue) id=\(id) installed=\(installed)")
    }

    nonisolated static func selectedModelID(kind: CapabilityModelKind, defaults: UserDefaults = .standard) -> String {
        selectedModelID(kind: kind, models: CapabilityModelCatalog.models(for: kind), defaults: defaults)
    }

    nonisolated static func setSelectedModelID(
        _ modelID: String,
        kind: CapabilityModelKind,
        defaults: UserDefaults = .standard
    ) {
        let models = CapabilityModelCatalog.models(for: kind)
        guard models.contains(where: { $0.id == modelID }) else { return }
        defaults.set(modelID, forKey: selectedModelDefaultsKey(kind: kind))
    }

    private nonisolated static func selectedModelID(
        kind: CapabilityModelKind,
        models: [CapabilityModelDescriptor],
        defaults: UserDefaults
    ) -> String {
        let fallbackModelID = models.first(where: \.isRecommended)?.id ?? models.first?.id ?? ""
        let storedModelID = defaults.string(forKey: selectedModelDefaultsKey(kind: kind))
        return models.contains { $0.id == storedModelID } ? storedModelID ?? fallbackModelID : fallbackModelID
    }

    private nonisolated static func models(
        _ models: [CapabilityModelDescriptor],
        withSelectedFirst selectedModelID: String
    ) -> [CapabilityModelDescriptor] {
        guard let selected = models.first(where: { $0.id == selectedModelID }) else {
            return models
        }
        return [selected] + models.filter { $0.id != selectedModelID }
    }

    private nonisolated static func selectedModelDefaultsKey(kind: CapabilityModelKind) -> String {
        "settings.capabilityModel.\(kind.rawValue).selectedModelID"
    }
}
