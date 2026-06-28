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

    static func requiresDownload(_ id: String) -> Bool {
        !isBuiltInOption(id)
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
                    displayName: L10n.localize("model.capability.tts_system_default_name", comment: ""),
                    subtitle: L10n.localize("model.capability.tts_system_default_subtitle", comment: ""),
                    sizeDescription: L10n.localize("model.capability.tts_system_default_size", comment: ""),
                    memoryDescription: L10n.localize("model.capability.tts_system_default_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.tts_system_default_fallback", comment: ""),
                    isRecommended: true,
                    isInstalled: true
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.kokoroTTS,
                    kind: .tts,
                    displayName: "Kokoro TTS",
                    subtitle: L10n.localize("model.capability.tts_kokoro_subtitle", comment: ""),
                    sizeDescription: "89 MB",
                    memoryDescription: L10n.localize("model.capability.tts_kokoro_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.tts_kokoro_fallback", comment: ""),
                    isRecommended: false,
                    isInstalled: false
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.qwen3TTS06B4Bit,
                    kind: .tts,
                    displayName: "Qwen3-TTS 0.6B 4-bit",
                    subtitle: L10n.localize("model.capability.tts_qwen3_subtitle", comment: ""),
                    sizeDescription: "1.7 GB",
                    memoryDescription: L10n.localize("model.capability.tts_qwen3_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.tts_qwen3_fallback", comment: ""),
                    isRecommended: false,
                    isInstalled: false
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.cosyVoice3,
                    kind: .tts,
                    displayName: "CosyVoice3",
                    subtitle: L10n.localize("model.capability.tts_cosy_subtitle", comment: ""),
                    sizeDescription: "1.2 GB",
                    memoryDescription: L10n.localize("model.capability.tts_cosy_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.tts_cosy_fallback", comment: ""),
                    isRecommended: false,
                    isInstalled: false
                ),
            ]
        case .translation:
            return [
                CapabilityModelDescriptor(
                    id: CapabilityModelID.systemDefaultTranslation,
                    kind: .translation,
                    displayName: L10n.localize("model.capability.translation_system_default_name", comment: ""),
                    subtitle: L10n.localize("model.capability.translation_system_default_subtitle", comment: ""),
                    sizeDescription: L10n.localize("model.capability.translation_system_default_size", comment: ""),
                    memoryDescription: L10n.localize("model.capability.translation_system_default_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.translation_system_default_fallback", comment: ""),
                    isRecommended: true,
                    isInstalled: true
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.llmTranslation,
                    kind: .translation,
                    displayName: L10n.localize("model.capability.translation_llm_config_name", comment: ""),
                    subtitle: L10n.localize("model.capability.translation_llm_config_subtitle", comment: ""),
                    sizeDescription: L10n.localize("model.capability.translation_llm_config_size", comment: ""),
                    memoryDescription: L10n.localize("model.capability.translation_llm_config_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.translation_llm_config_fallback", comment: ""),
                    isRecommended: false,
                    isInstalled: true
                ),
                CapabilityModelDescriptor(
                    id: CapabilityModelID.madladTranslation,
                    kind: .translation,
                    displayName: "Soniqo MADLAD",
                    subtitle: L10n.localize("model.capability.translation_madlad_subtitle", comment: ""),
                    sizeDescription: L10n.localize("model.capability.translation_madlad_size", comment: ""),
                    memoryDescription: L10n.localize("model.capability.translation_madlad_memory", comment: ""),
                    fallbackDescription: L10n.localize("model.capability.translation_madlad_fallback", comment: ""),
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
    private var llmTranslationAvailable: Bool

    init(
        kind: CapabilityModelKind,
        downloader: any CapabilityModelDownloading = SoniqoCapabilityModelDownloader(),
        defaults: UserDefaults = .standard,
        llmTranslationAvailable: Bool = false
    ) {
        self.kind = kind
        self.downloader = downloader
        self.defaults = defaults
        self.llmTranslationAvailable = llmTranslationAvailable
        Self.logger.debug("capability_model_vm_init_start kind=\(kind.rawValue)")
        let catalogModels = Self.models(
            kind: kind,
            isModelInstalled: { CapabilityModelID.isBuiltInOption($0) || downloader.isInstalled(modelID: $0) },
            llmTranslationAvailable: llmTranslationAvailable
        )
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
        guard let model = models.first(where: { $0.id == id }) else {
            Self.logger.warning("capability_model_vm_select_model_skipped kind=\(kind.rawValue) id=\(id)")
            return
        }
        guard Self.isSelectable(model) else {
            lastActionMessage = nil
            lastError = L10n.localize("model.capability.config_required_error", comment: "")
            Self.logger.warning("capability_model_vm_select_model_unavailable kind=\(kind.rawValue) id=\(id)")
            return
        }
        selectedModelID = id
        models = Self.models(models, withSelectedFirst: id)
        defaults.set(id, forKey: Self.selectedModelDefaultsKey(kind: kind))
        if kind == .translation {
            defaults.set(Self.translationDefaultMigrationVersion, forKey: Self.translationDefaultMigrationKey)
        }
        lastError = nil
        lastActionMessage = L10n.localize("model.capability.action_switch_model_config", comment: "")
        Self.logger.info("capability_model_vm_select_model_success kind=\(kind.rawValue) id=\(id)")
    }

    func setLLMTranslationAvailable(_ available: Bool) {
        guard kind == .translation else { return }
        guard llmTranslationAvailable != available else { return }
        llmTranslationAvailable = available
        let catalogModels = Self.models(
            kind: kind,
            isModelInstalled: { CapabilityModelID.isBuiltInOption($0) || downloader.isInstalled(modelID: $0) },
            llmTranslationAvailable: available
        )
        let selectedModelID = Self.selectedModelID(
            kind: kind,
            models: catalogModels,
            defaults: defaults
        )
        self.models = Self.models(catalogModels, withSelectedFirst: selectedModelID)
        self.selectedModelID = selectedModelID
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
        if id == CapabilityModelID.llmTranslation,
           models.first(where: { $0.id == id })?.isInstalled != true {
            lastActionMessage = nil
            lastError = L10n.localize("model.capability.config_required_error", comment: "")
            Self.logger.info("capability_model_vm_download_llm_unavailable kind=\(kind.rawValue) id=\(id)")
            return
        }
        guard CapabilityModelID.requiresDownload(id) else {
            markInstalled(id: id, installed: true)
            lastError = nil
            lastActionMessage = L10n.localize("model.capability.action_switch_builtin_model", comment: "")
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
            lastActionMessage = L10n.localize("model.capability.action_download_completed", comment: "")
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

    nonisolated static func selectedModelID(
        kind: CapabilityModelKind,
        defaults: UserDefaults = .standard,
        llmTranslationAvailable: Bool
    ) -> String {
        selectedModelID(
            kind: kind,
            models: models(
                kind: kind,
                isModelInstalled: { CapabilityModelID.isBuiltInOption($0) },
                llmTranslationAvailable: llmTranslationAvailable
            ),
            defaults: defaults
        )
    }

    nonisolated static func setSelectedModelID(
        _ modelID: String,
        kind: CapabilityModelKind,
        defaults: UserDefaults = .standard
    ) {
        let models = CapabilityModelCatalog.models(for: kind)
        guard models.contains(where: { $0.id == modelID }) else { return }
        defaults.set(modelID, forKey: selectedModelDefaultsKey(kind: kind))
        // 用户明确选择翻译模型时同步写入迁移标记
        if kind == .translation {
            defaults.set(translationDefaultMigrationVersion, forKey: translationDefaultMigrationKey)
        }
    }

    private nonisolated static func selectedModelID(
        kind: CapabilityModelKind,
        models: [CapabilityModelDescriptor],
        defaults: UserDefaults
    ) -> String {
        let fallbackModelID = models.first(where: \.isRecommended)?.id ?? models.first?.id ?? ""
        // 翻译类型执行默认迁移
        if kind == .translation {
            _ = migrateTranslationDefault(defaults: defaults)
        }
        let storedModelID = defaults.string(forKey: selectedModelDefaultsKey(kind: kind))
        guard let storedModelID,
              let storedModel = models.first(where: { $0.id == storedModelID }) else {
            return fallbackModelID
        }
        return isSelectable(storedModel) ? storedModelID : fallbackModelID
    }

    nonisolated static func models(
        kind: CapabilityModelKind,
        isModelInstalled: (String) -> Bool,
        llmTranslationAvailable: Bool
    ) -> [CapabilityModelDescriptor] {
        CapabilityModelCatalog.models(for: kind).map { model in
            var mutable = model
            if model.id == CapabilityModelID.llmTranslation {
                mutable.isInstalled = llmTranslationAvailable
            } else {
                mutable.isInstalled = CapabilityModelID.isSystemDefault(model.id) || isModelInstalled(model.id)
            }
            return mutable
        }
    }

    nonisolated static func isSelectable(_ model: CapabilityModelDescriptor) -> Bool {
        model.id != CapabilityModelID.llmTranslation || model.isInstalled
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

    // MARK: - Translation default migration

    nonisolated private static let translationDefaultMigrationKey = "settings.capabilityModel.translation.defaultMigrationVersion"
    nonisolated private static let translationDefaultMigrationVersion = 1

    /// 迁移旧版本默认值：旧 llm.configured.translation 一次性迁移到
    /// system.default.translation。MADLAD 保留。写入迁移标记后不再重复执行。
    /// - Returns: 迁移后的 modelID，或 nil 表示无需迁移。
    nonisolated static func migrateTranslationDefault(
        defaults: UserDefaults = .standard
    ) -> String? {
        let migrationVersion = defaults.integer(forKey: translationDefaultMigrationKey)
        guard migrationVersion < translationDefaultMigrationVersion else {
            return nil
        }
        let storedModelID = defaults.string(forKey: selectedModelDefaultsKey(kind: .translation))
        guard let storedModelID else {
            // 从未保存过选择：无需迁移，写入版本标记后返回 nil
            defaults.set(translationDefaultMigrationVersion, forKey: translationDefaultMigrationKey)
            return nil
        }
        guard storedModelID == CapabilityModelID.llmTranslation else {
            // MADLAD 或已明确选择的模型：保留，写入版本标记
            defaults.set(translationDefaultMigrationVersion, forKey: translationDefaultMigrationKey)
            return nil
        }
        // 旧默认智能模型 → 系统默认
        defaults.set(CapabilityModelID.systemDefaultTranslation, forKey: selectedModelDefaultsKey(kind: .translation))
        defaults.set(translationDefaultMigrationVersion, forKey: translationDefaultMigrationKey)
        return CapabilityModelID.systemDefaultTranslation
    }
}
