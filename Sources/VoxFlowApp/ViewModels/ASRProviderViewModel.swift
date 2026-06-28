import Combine
import Foundation
import VoxFlowModelStore
import VoxFlowProviderAliyunDashScope
import VoxFlowProviderFunASR
import VoxFlowProviderGroq
import VoxFlowProviderNVIDIA
import VoxFlowProviderOmnilingual
import VoxFlowProviderParakeet
import VoxFlowProviderParaformer
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderTencentCloud
import VoxFlowProviderWhisper

enum ASRProviderScope: String, CaseIterable, Identifiable {
    case all
    case offline
    case online

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return L10n.localize("asr.provider.scope.all", comment: "All ASR providers scope")
        case .online:
            return L10n.localize("asr.provider.scope.online", comment: "Online ASR providers scope")
        case .offline:
            return L10n.localize("asr.provider.scope.offline", comment: "Offline ASR providers scope")
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .online:
            return "cloud"
        case .offline:
            return "externaldrive"
        }
    }

    func matches(_ descriptor: ASRProviderDescriptor) -> Bool {
        switch self {
        case .all:
            return true
        case .online:
            return Self.isOnlineProvider(descriptor)
        case .offline:
            return !Self.isOnlineProvider(descriptor)
        }
    }

    func sort(_ descriptors: [ASRProviderDescriptor]) -> [ASRProviderDescriptor] {
        guard self == .online else { return descriptors }
        let rank = Dictionary(
            uniqueKeysWithValues: [
                ASRProviderID.groqWhisper,
                ASRProviderID.tencentCloudASR,
                ASRProviderID.qwenCloudASR,
                ASRProviderID.volcengineDoubao,
                ASRProviderID.mistralVoxtral,
                ASRProviderID.assemblyAI,
                ASRProviderID.elevenLabsScribe,
            ].enumerated().map { ($0.element, $0.offset) }
        )
        return descriptors.sorted {
            (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max)
        }
    }

    private static func isOnlineProvider(_ descriptor: ASRProviderDescriptor) -> Bool {
        descriptor.capabilities.contains(.cloud)
            || descriptor.externalLinks != nil
            || descriptor.tags.contains("在线")
            || descriptor.tags.contains { $0.localizedCaseInsensitiveCompare("online") == .orderedSame }
    }
}

enum GroqASRConfigurationError: LocalizedError {
    case invalidHTTPSURL
    case emptyModel
    case unsupportedModel

    var errorDescription: String? {
        switch self {
        case .invalidHTTPSURL:
            return "Groq 地址必须是有效的 HTTPS URL。"
        case .emptyModel:
            return "Groq 模型不能为空。"
        case .unsupportedModel:
            return "Groq 仅支持 Whisper 转写模型。"
        }
    }
}

enum TencentCloudASRConfigurationError: LocalizedError {
    case emptyAppID
    case emptySecretID
    case emptySecretKey
    case emptyEngineModelType

    var errorDescription: String? {
        switch self {
        case .emptyAppID:
            return "腾讯云 AppID 不能为空。"
        case .emptySecretID:
            return "腾讯云 SecretId 不能为空。"
        case .emptySecretKey:
            return "腾讯云 SecretKey 不能为空。"
        case .emptyEngineModelType:
            return "腾讯云识别引擎不能为空。"
        }
    }
}

enum AliyunDashScopeASRConfigurationError: LocalizedError {
    case emptyAPIKey
    case emptyModel

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "阿里云百炼访问密钥不能为空。"
        case .emptyModel:
            return "阿里云百炼识别模型不能为空。"
        }
    }
}

struct GroqASRModelOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private struct ModelDownloadOperation: Equatable, Sendable {
    let id = UUID()
    let providerID: String
    let qwenModelSize: ASRManager.ModelSize?
}

@MainActor
final class ASRProviderViewModel: ObservableObject {
    private static let logger = AppLogger.general
    private static let downloadLogger = AppLogger.modelDownload

    static let storedGroqAPIKeyMask = String(repeating: "•", count: 12)
    static let storedTencentSecretMask = String(repeating: "•", count: 12)
    static let storedAliyunDashScopeAPIKeyMask = String(repeating: "•", count: 12)
    static let supportedGroqModels: [GroqASRModelOption] = [
        GroqASRModelOption(id: "whisper-large-v3-turbo", title: "Whisper Large V3 Turbo"),
        GroqASRModelOption(id: "whisper-large-v3", title: "Whisper Large V3"),
    ]

    @Published private(set) var providers: [ASRProviderDescriptor] = []
    @Published private(set) var selectedTags: Set<String> = []
    @Published private(set) var providerScope: ASRProviderScope = .all
    @Published private(set) var downloadProgress: ModelDownloadProgressViewState?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadingProviderID: String? = nil
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published var groqAPIKeyInput = ""
    @Published var groqBaseURLInput = GroqCloudASRClient.defaultBaseURL
    @Published var groqModelInput = GroqCloudASRClient.defaultModel
    @Published private(set) var isTestingGroq = false
    @Published var tencentAppIDInput = ""
    @Published var tencentSecretIDInput = ""
    @Published var tencentSecretKeyInput = ""
    @Published var tencentEngineModelTypeInput = TencentRealtimeASRConfiguration.defaultEngineModelType
    @Published private(set) var isTestingTencentCloud = false
    @Published var aliyunDashScopeAPIKeyInput = ""
    @Published var aliyunDashScopeModelInput = AliyunDashScopeRealtimeASRConfiguration.defaultModel
    @Published var aliyunDashScopeVocabularyIDInput = ""
    @Published private(set) var isTestingAliyunDashScope = false

    private let environment: any AppServiceProviding
    private let asrManager: ASRManager
    private let configurationService: ASRProviderConfigurationService
    private let registry: ASRProviderRegistry
    private let downloader: any Qwen3ModelDownloading
    private let sherpaModelDownloader: any SherpaASRModelDownloading
    private let senseVoiceModelDownloader: any SenseVoiceModelDownloading
    private let whisperKitModelDownloader: any WhisperKitModelDownloading
    private let paraformerModelDownloader: any ParaformerModelDownloading
    private let nvidiaNemotronModelDownloader: any NVIDIANemotronModelDownloading
    private let parakeetModelDownloader: any ParakeetModelDownloading
    private let omnilingualModelDownloader: any OmnilingualModelDownloading
    private let qwenReadinessPreparer: any Qwen3ModelReadinessPreparing
    private let fileManager: FileManager
    private var cancellables = Set<AnyCancellable>()
    private var providerRecordPersistenceTask: Task<Void, Never>?
    private var activeDownloadOperation: ModelDownloadOperation?
    private var cleanupRequestedDownloadIDs = Set<UUID>()
    private var previousDownloadProgressBytes: Int64?
    private var previousDownloadProgressDate: Date?
    private var lastDownloadLogDate: Date?
    private var lastDownloadLogProgress: Double?
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        asrManager: ASRManager? = nil,
        registry: ASRProviderRegistry? = nil,
        downloader: any Qwen3ModelDownloading = Qwen3ModelDownloader.live(),
        sherpaModelDownloader: any SherpaASRModelDownloading = SherpaASRModelDownloader(),
        senseVoiceModelDownloader: any SenseVoiceModelDownloading = SenseVoiceModelDownloader(),
        whisperKitModelDownloader: any WhisperKitModelDownloading = WhisperKitModelDownloader(),
        paraformerModelDownloader: any ParaformerModelDownloading = ParaformerModelDownloader(),
        nvidiaNemotronModelDownloader: any NVIDIANemotronModelDownloading = NVIDIANemotronModelDownloader(),
        parakeetModelDownloader: any ParakeetModelDownloading = ParakeetModelDownloader(),
        omnilingualModelDownloader: any OmnilingualModelDownloading = OmnilingualModelDownloader(),
        qwenReadinessPreparer: any Qwen3ModelReadinessPreparing = Qwen3ModelReadinessPreparer(),
        fileManager: FileManager = .default
    ) {
        let resolvedASRManager = asrManager ?? ASRManager(
            credentialStore: environment.credentialStore,
            settingsRepository: environment.settingsRepository
        )
        self.environment = environment
        self.asrManager = resolvedASRManager
        configurationService = ASRProviderConfigurationService(asrManager: resolvedASRManager)
        self.registry = registry ?? ASRProviderRegistry(asrManager: resolvedASRManager)
        self.downloader = downloader
        self.sherpaModelDownloader = sherpaModelDownloader
        self.senseVoiceModelDownloader = senseVoiceModelDownloader
        self.whisperKitModelDownloader = whisperKitModelDownloader
        self.paraformerModelDownloader = paraformerModelDownloader
        self.nvidiaNemotronModelDownloader = nvidiaNemotronModelDownloader
        self.parakeetModelDownloader = parakeetModelDownloader
        self.omnilingualModelDownloader = omnilingualModelDownloader
        self.qwenReadinessPreparer = qwenReadinessPreparer
        self.fileManager = fileManager
        Self.logger.debug("asr_provider_vm_init")
        syncGroqConfigurationInputsFromManager()
        let tencentCredentials = resolvedASRManager.storedTencentCloudCredentials()
        tencentAppIDInput = tencentCredentials.appID
        tencentSecretIDInput = tencentCredentials.secretID
        tencentSecretKeyInput = tencentCredentials.secretKey.isEmpty ? "" : Self.storedTencentSecretMask
        tencentEngineModelTypeInput = TencentRealtimeASRConfiguration.defaultEngineModelType
        aliyunDashScopeAPIKeyInput = resolvedASRManager.isAliyunDashScopeConfigured
            ? Self.storedAliyunDashScopeAPIKeyMask
            : ""
        aliyunDashScopeModelInput = AliyunDashScopeRealtimeASRConfiguration.defaultModel
        aliyunDashScopeVocabularyIDInput = resolvedASRManager.aliyunDashScopeVocabularyID
        refreshProviders(persistRecords: false)
        // 监听菜单栏等外部途径切换模型后的 UserDefaults 变化
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProviders(persistRecords: false)
            }
            .store(in: &cancellables)
    }

    var visibleProviders: [ASRProviderDescriptor] {
        pinCurrentProviderFirst(providerScope.sort(scopedProviders().filter { descriptor in
            ASRProviderFilter(tags: selectedTags).matches(descriptor)
        }))
    }

    var availableTags: [String] {
        let scopedTagSet = Set(scopedProviders().flatMap { descriptor in
            ASRProviderTagPresentation.cardTags(for: descriptor)
        })
        return ASRProviderTagPresentation.approvedCardTags
            .filter { $0 != .online && $0 != .offline }
            .map { $0.localizedTitle }
            .filter { scopedTagSet.contains($0) }
    }

    private func scopedProviders() -> [ASRProviderDescriptor] {
        switch providerScope {
        case .all:
            return providers
        case .offline:
            return registry.offlineDescriptors()
        case .online:
            return providers.filter(providerScope.matches)
        }
    }

    var selectedQwenModelSize: ASRManager.ModelSize {
        asrManager.qwen3ModelSize
    }

    var qwenModelPath: String? {
        asrManager.qwen3ModelPath
    }

    var selectedFunASRPrecision: ASRManager.FunASRPrecision { asrManager.funASRPrecision }
    var selectedWhisperVariant: ASRManager.WhisperVariant { asrManager.whisperVariant }
    var hasStoredGroqAPIKey: Bool { asrManager.isGroqConfigured }
    var hasStoredTencentCloudCredentials: Bool { asrManager.isTencentCloudConfigured }
    var hasStoredAliyunDashScopeAPIKey: Bool { asrManager.isAliyunDashScopeConfigured }
    var supportedGroqModels: [GroqASRModelOption] { Self.supportedGroqModels }

    func groqAPIKeyForEditing() -> String {
        hasStoredGroqAPIKey ? Self.storedGroqAPIKeyMask : ""
    }

    func storedGroqAPIKeyForEditing() -> String {
        asrManager.storedGroqAPIKey()
    }

    func isMaskedGroqAPIKey(text: String) -> Bool {
        !text.isEmpty && text == Self.storedGroqAPIKeyMask
    }

    func isMaskedTencentSecret(text: String) -> Bool {
        !text.isEmpty && text == Self.storedTencentSecretMask
    }

    func isMaskedAliyunDashScopeAPIKey(text: String) -> Bool {
        !text.isEmpty && text == Self.storedAliyunDashScopeAPIKeyMask
    }

    func aliyunDashScopeAPIKeyForEditing() -> String {
        hasStoredAliyunDashScopeAPIKey ? Self.storedAliyunDashScopeAPIKeyMask : ""
    }

    func storedAliyunDashScopeAPIKeyForEditing() -> String {
        asrManager.storedAliyunDashScopeAPIKey()
    }

    func storedTencentCloudCredentialsForEditing() -> (appID: String, secretID: String, secretKey: String) {
        asrManager.storedTencentCloudCredentials()
    }

    func saveGroqConfiguration() {
        Self.logger.debug("asr_provider_vm_save_groq_start model=\(groqModelInput) baseURLLen=\(groqBaseURLInput.count) keyMasked=\(isMaskedGroqAPIKey(text: groqAPIKeyInput))")
        do {
            apply(
                try configurationService.saveGroqConfiguration(
                    apiKeyInput: groqAPIKeyInput,
                    baseURLInput: groqBaseURLInput,
                    modelInput: groqModelInput,
                    apiKeyMask: Self.storedGroqAPIKeyMask,
                    supportedModels: Self.supportedGroqModels
                )
            )
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已保存 Groq 配置"
            Self.logger.info("asr_provider_vm_save_groq_success configured=\(hasStoredGroqAPIKey)")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_save_groq_failed error=\(error.localizedDescription)")
        }
    }

    func testGroqConnection() async {
        guard !isTestingGroq else {
            Self.logger.debug("asr_provider_vm_test_groq_skipped alreadyTesting=true")
            return
        }
        Self.logger.debug("asr_provider_vm_test_groq_start model=\(groqModelInput)")
        isTestingGroq = true
        defer { isTestingGroq = false }
        do {
            apply(
                try configurationService.saveGroqConfiguration(
                    apiKeyInput: groqAPIKeyInput,
                    baseURLInput: groqBaseURLInput,
                    modelInput: groqModelInput,
                    apiKeyMask: Self.storedGroqAPIKeyMask,
                    supportedModels: Self.supportedGroqModels
                )
            )
            let result = try await configurationService.testGroqConnection()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = result.message
            Self.logger.info("asr_provider_vm_test_groq_success messageLen=\(result.message.count)")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_test_groq_failed error=\(error.localizedDescription)")
        }
    }

    func deleteGroqAPIKey() {
        Self.logger.debug("asr_provider_vm_delete_groq_key_start")
        do {
            try configurationService.deleteGroqAPIKey()
            groqAPIKeyInput = ""
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已删除 Groq 访问密钥"
            Self.logger.info("asr_provider_vm_delete_groq_key_success")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_delete_groq_key_failed error=\(error.localizedDescription)")
        }
    }

    func saveTencentCloudConfiguration() {
        Self.logger.debug("asr_provider_vm_save_tencent_start appIDLen=\(tencentAppIDInput.count) secretIDLen=\(tencentSecretIDInput.count) secretMasked=\(isMaskedTencentSecret(text: tencentSecretKeyInput))")
        do {
            apply(
                try configurationService.saveTencentCloudConfiguration(
                    appIDInput: tencentAppIDInput,
                    secretIDInput: tencentSecretIDInput,
                    secretKeyInput: tencentSecretKeyInput,
                    secretMask: Self.storedTencentSecretMask
                )
            )
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已保存腾讯云配置"
            Self.logger.info("asr_provider_vm_save_tencent_success configured=\(hasStoredTencentCloudCredentials)")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_save_tencent_failed error=\(error.localizedDescription)")
        }
    }

    func testTencentCloudConnection() async {
        guard !isTestingTencentCloud else {
            Self.logger.debug("asr_provider_vm_test_tencent_skipped alreadyTesting=true")
            return
        }
        Self.logger.debug("asr_provider_vm_test_tencent_start engine=\(tencentEngineModelTypeInput)")
        isTestingTencentCloud = true
        defer { isTestingTencentCloud = false }
        do {
            apply(
                try configurationService.saveTencentCloudConfiguration(
                    appIDInput: tencentAppIDInput,
                    secretIDInput: tencentSecretIDInput,
                    secretKeyInput: tencentSecretKeyInput,
                    secretMask: Self.storedTencentSecretMask
                )
            )
            let result = try await configurationService.testTencentCloudConnection()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = result.message
            Self.logger.info("asr_provider_vm_test_tencent_success messageLen=\(result.message.count)")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_test_tencent_failed error=\(error.localizedDescription)")
        }
    }

    func deleteTencentCloudCredentials() {
        Self.logger.debug("asr_provider_vm_delete_tencent_credentials_start")
        do {
            try configurationService.deleteTencentCloudCredentials()
            tencentAppIDInput = ""
            tencentSecretIDInput = ""
            tencentSecretKeyInput = ""
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已删除腾讯云凭据"
            Self.logger.info("asr_provider_vm_delete_tencent_credentials_success")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_delete_tencent_credentials_failed error=\(error.localizedDescription)")
        }
    }

    func saveAliyunDashScopeConfiguration() {
        Self.logger.debug("asr_provider_vm_save_aliyun_start model=\(aliyunDashScopeModelInput) keyMasked=\(isMaskedAliyunDashScopeAPIKey(text: aliyunDashScopeAPIKeyInput))")
        do {
            apply(
                try configurationService.saveAliyunDashScopeConfiguration(
                    apiKeyInput: aliyunDashScopeAPIKeyInput,
                    apiKeyMask: Self.storedAliyunDashScopeAPIKeyMask,
                    vocabularyIDInput: aliyunDashScopeVocabularyIDInput
                )
            )
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已保存阿里云百炼配置"
            Self.logger.info("asr_provider_vm_save_aliyun_success configured=\(hasStoredAliyunDashScopeAPIKey)")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_save_aliyun_failed error=\(error.localizedDescription)")
        }
    }

    func testAliyunDashScopeConnection() async {
        guard !isTestingAliyunDashScope else {
            Self.logger.debug("asr_provider_vm_test_aliyun_skipped alreadyTesting=true")
            return
        }
        Self.logger.debug("asr_provider_vm_test_aliyun_start model=\(aliyunDashScopeModelInput)")
        isTestingAliyunDashScope = true
        defer { isTestingAliyunDashScope = false }
        do {
            apply(
                try configurationService.saveAliyunDashScopeConfiguration(
                    apiKeyInput: aliyunDashScopeAPIKeyInput,
                    apiKeyMask: Self.storedAliyunDashScopeAPIKeyMask,
                    vocabularyIDInput: aliyunDashScopeVocabularyIDInput
                )
            )
            let result = try await configurationService.testAliyunDashScopeConnection()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = result.message
            Self.logger.info("asr_provider_vm_test_aliyun_success messageLen=\(result.message.count)")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_test_aliyun_failed error=\(error.localizedDescription)")
        }
    }

    func deleteAliyunDashScopeAPIKey() {
        Self.logger.debug("asr_provider_vm_delete_aliyun_key_start")
        do {
            try configurationService.deleteAliyunDashScopeAPIKey()
            aliyunDashScopeAPIKeyInput = ""
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已删除阿里云百炼访问密钥"
            Self.logger.info("asr_provider_vm_delete_aliyun_key_success")
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_delete_aliyun_key_failed error=\(error.localizedDescription)")
        }
    }

    private func apply(_ state: GroqASRConfigurationInputState) {
        groqAPIKeyInput = state.apiKeyInput
        groqBaseURLInput = state.baseURLInput
        groqModelInput = state.modelInput
    }

    private func apply(_ state: TencentCloudASRConfigurationInputState) {
        tencentAppIDInput = state.appIDInput
        tencentSecretIDInput = state.secretIDInput
        tencentSecretKeyInput = state.secretKeyInput
        tencentEngineModelTypeInput = state.engineModelTypeInput
    }

    private func apply(_ state: AliyunDashScopeASRConfigurationInputState) {
        aliyunDashScopeAPIKeyInput = state.apiKeyInput
        aliyunDashScopeModelInput = state.modelInput
        aliyunDashScopeVocabularyIDInput = state.vocabularyIDInput
    }

    func sherpaVariant(for id: String) -> SherpaASRModelVariant? {
        switch id {
        case ASRProviderID.funASR:
            return asrManager.funASRModelVariant
        default:
            return nil
        }
    }

    func whisperKitVariant(for id: String) -> WhisperKitModelVariant? {
        id == ASRProviderID.whisper ? asrManager.whisperModelVariant : nil
    }

    func selectFunASRPrecision(_ precision: ASRManager.FunASRPrecision, selectingProvider: Bool = false) {
        Self.logger.debug("asr_provider_vm_select_funasr_precision precision=\(precision.rawValue) selectingProvider=\(selectingProvider)")
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.funASR)
        }
        asrManager.funASRPrecision = precision
        configurationDidChange()
    }

    func selectWhisperVariant(_ variant: ASRManager.WhisperVariant, selectingProvider: Bool = false) {
        Self.logger.debug("asr_provider_vm_select_whisper_variant variant=\(variant.rawValue) selectingProvider=\(selectingProvider)")
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.whisper)
        }
        guard ASRManager.isWhisperRuntimeSupported(variant: variant) else {
            lastActionMessage = nil
            lastError = ASRManager.whisperRuntimeUnsupportedMessage(for: variant)
            Self.logger.warning("asr_provider_vm_select_whisper_variant_rejected variant=\(variant.rawValue)")
            return
        }
        asrManager.whisperVariant = variant
        configurationDidChange()
    }

    func selectQwenModelSize(_ size: ASRManager.ModelSize, selectingProvider: Bool = false) {
        Self.logger.debug("asr_provider_vm_select_qwen_model_size size=\(size.rawValue) selectingProvider=\(selectingProvider)")
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.qwen3)
        }
        asrManager.qwen3ModelSize = size
        configurationDidChange()
    }

    func selectProviderForConfiguration(id: String) {
        guard let fallbackEngine = fallbackEngine(for: id) else {
            Self.logger.warning("asr_provider_vm_select_provider_for_configuration_skipped id=\(id)")
            return
        }
        Self.logger.info("asr_provider_vm_select_provider_for_configuration id=\(id) engine=\(fallbackEngine.rawValue)")
        asrManager.selectedEngineType = fallbackEngine
    }

    private func configurationDidChange() {
        refreshProviders(persistRecords: false)
        scheduleProviderRecordPersistence()
        lastError = nil
        lastActionMessage = "已切换模型配置"
    }

    func load() {
        Self.logger.debug("asr_provider_vm_load_start")
        syncGroqConfigurationInputsFromManager()
        refreshProviders(persistRecords: true)
        hasLoaded = lastError == nil
        Self.logger.debug("asr_provider_vm_load_done hasLoaded=\(hasLoaded) providers=\(providers.count)")
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            Self.logger.debug("asr_provider_vm_load_if_needed_skip")
            return
        }
        Self.logger.debug("asr_provider_vm_load_if_needed_execute")
        load()
    }

    private func refreshProviders(persistRecords: Bool) {
        Self.logger.debug("asr_provider_vm_refresh_providers_start persistRecords=\(persistRecords)")
        do {
            providers = registry.descriptors()
            if persistRecords {
                try persistProviderRecords()
            }
            lastError = nil
            Self.logger.info("asr_provider_vm_refresh_providers_success providers=\(providers.count) persistRecords=\(persistRecords)")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_refresh_providers_failed persistRecords=\(persistRecords) error=\(error.localizedDescription)")
        }
    }

    private func syncGroqConfigurationInputsFromManager() {
        groqBaseURLInput = asrManager.groqBaseURL
        groqModelInput = Self.supportedGroqModels.contains { $0.id == asrManager.groqModel }
            ? asrManager.groqModel
            : GroqCloudASRClient.defaultModel
        if asrManager.isGroqConfigured,
           groqAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            groqAPIKeyInput = Self.storedGroqAPIKeyMask
        }
    }

    private func scheduleProviderRecordPersistence() {
        providerRecordPersistenceTask?.cancel()
        providerRecordPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let self, !Task.isCancelled else { return }
                try self.persistProviderRecords()
                Self.logger.debug("asr_provider_vm_scheduled_persist_success")
            } catch is CancellationError {
            } catch {
                self?.lastError = error.localizedDescription
                Self.logger.error("asr_provider_vm_scheduled_persist_failed error=\(error.localizedDescription)")
            }
        }
    }

    func toggleTag(_ tag: String) {
        guard availableTags.contains(tag) else {
            selectedTags.remove(tag)
            Self.logger.warning("asr_provider_vm_toggle_tag_removed_unavailable tag=\(tag)")
            return
        }
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
        Self.logger.debug("asr_provider_vm_toggle_tag tag=\(tag) selectedCount=\(selectedTags.count)")
    }

    func selectProviderScope(_ scope: ASRProviderScope) {
        providerScope = scope
        selectedTags.formIntersection(availableTags)
        Self.logger.info("asr_provider_vm_select_provider_scope scope=\(scope.rawValue) selectedTags=\(selectedTags.count)")
    }

    private func pinCurrentProviderFirst(_ descriptors: [ASRProviderDescriptor]) -> [ASRProviderDescriptor] {
        descriptors.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isDefault != rhs.element.isDefault {
                    return lhs.element.isDefault
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func selectDefaultProvider(id: String) {
        Self.logger.debug("asr_provider_vm_select_default_provider_start id=\(id)")
        do {
            try registry.selectDefaultProvider(id: id)
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = nil
            Self.logger.info("asr_provider_vm_select_default_provider_success id=\(id)")
        } catch {
            let message = error.localizedDescription
            load()
            lastError = message
            Self.logger.error("asr_provider_vm_select_default_provider_failed id=\(id) error=\(message)")
        }
    }

    func setQwenModelPath(_ path: String) {
        Self.logger.debug("asr_provider_vm_set_qwen_model_path_start pathLen=\(path.count)")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard downloader.supportedModelExists(at: url, fileManager: fileManager) else {
            lastError = "所选目录不是可用的 Qwen3-ASR 模型。"
            Self.logger.warning("asr_provider_vm_set_qwen_model_path_rejected")
            return
        }
        asrManager.qwen3ModelPath = path
        load()
        lastError = nil
        lastActionMessage = "已设置本地模型目录"
        Self.logger.info("asr_provider_vm_set_qwen_model_path_success")
    }

    func downloadQwenModel() async {
        await downloadModel(id: ASRProviderID.qwen3)
    }

    private func modelPath(id: String) -> String? {
        switch id {
        case ASRProviderID.qwen3:
            return asrManager.qwen3ModelPath(for: asrManager.qwen3ModelSize)
                ?? asrManager.qwen3ModelPath
        case ASRProviderID.funASR:
            if case let .ready(installation) = asrManager.funASRModelInstallationState(
                for: asrManager.funASRPrecision
            ) {
                return installation.installedRoot.path
            }
            return asrManager.funASRModelDirectoryURL(for: asrManager.funASRPrecision).path
        case ASRProviderID.whisper:
            if case let .ready(installation) = asrManager.whisperModelInstallationState(
                for: asrManager.whisperVariant
            ) {
                return installation.installedRoot.path
            }
            return asrManager.whisperModelDirectoryURL(for: asrManager.whisperVariant).path
        case ASRProviderID.senseVoice:
            if case let .ready(installation) = asrManager.senseVoiceModelInstallationState() {
                return installation.installedRoot.path
            }
            return asrManager.senseVoiceModelDirectoryURL().path
        case ASRProviderID.paraformer:
            if case let .ready(installation) = asrManager.paraformerModelInstallationState() {
                return installation.installedRoot.path
            }
            return asrManager.paraformerModelDirectoryURL().path
        case ASRProviderID.nvidiaNemotron:
            if case let .ready(installation) = asrManager.nvidiaNemotronModelInstallationState() {
                return installation.installedRoot.path
            }
            return asrManager.nvidiaNemotronModelDirectoryURL().path
        case ASRProviderID.parakeetStreaming:
            if case let .ready(installation) = asrManager.parakeetModelInstallationState() {
                return installation.installedRoot.path
            }
            return asrManager.parakeetModelDirectoryURL().path
        case ASRProviderID.omnilingualASR:
            if case let .ready(installation) = asrManager.omnilingualModelInstallationState() {
                return installation.installedRoot.path
            }
            return asrManager.omnilingualModelDirectoryURL().path
        default: return nil
        }
    }

    private func fallbackEngine(for id: String) -> ASREngineType? {
        switch id {
        case ASRProviderID.qwen3: return .qwen3
        case ASRProviderID.funASR: return .funASR
        case ASRProviderID.whisper: return .whisper
        case ASRProviderID.senseVoice: return .senseVoice
        case ASRProviderID.paraformer: return .paraformer
        case ASRProviderID.nvidiaNemotron: return .nvidiaNemotron
        case ASRProviderID.parakeetStreaming: return .parakeetStreaming
        case ASRProviderID.omnilingualASR: return .omnilingualASR
        case ASRProviderID.groqWhisper: return .groqWhisper
        case ASRProviderID.tencentCloudASR: return .tencentCloud
        case ASRProviderID.qwenCloudASR: return .aliyunDashScope
        default: return nil
        }
    }

    func localModelSizeSummary(providerID: String) -> String {
        if let bytes = expectedLocalModelDownloadBytes(providerID: providerID) {
            return "约 \(ModelDownloadProgressViewState.formatBytes(bytes))"
        }
        if let specification = localModelSpecification(providerID: providerID) {
            return "\(specification)，下载时检测"
        }
        return "下载时检测"
    }

    private func beginDownloadTracking(providerID: String) {
        previousDownloadProgressBytes = nil
        previousDownloadProgressDate = nil
        lastDownloadLogDate = nil
        lastDownloadLogProgress = nil
        let totalBytes = expectedLocalModelDownloadBytes(providerID: providerID)
        Self.downloadLogger.info(
            "model_download_started provider=\(providerID) totalBytes=\(totalBytes.map(String.init) ?? "unknown")"
        )
    }

    private func finishDownloadTracking(providerID: String) {
        Self.downloadLogger.info("model_download_completed provider=\(providerID)")
        previousDownloadProgressBytes = nil
        previousDownloadProgressDate = nil
        lastDownloadLogDate = nil
        lastDownloadLogProgress = nil
    }

    private func failDownloadTracking(providerID: String, error: Error) {
        Self.downloadLogger.error(
            "model_download_failed provider=\(providerID) error=\(error.localizedDescription)"
        )
    }

    private func setDownloadProgress(
        operation: ModelDownloadOperation,
        providerID: String,
        componentName: String,
        statusText: String,
        fractionCompleted: Double?,
        bytesWritten: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        guard activeDownloadOperation == operation else {
            Self.logger.debug(
                "asr_provider_vm_download_progress_ignored_stale id=\(providerID)"
            )
            return
        }
        let resolvedTotalBytes = totalBytes ?? expectedLocalModelDownloadBytes(providerID: providerID)
        let resolvedBytesWritten = bytesWritten ?? fractionCompleted.flatMap { fraction in
            resolvedTotalBytes.map { Int64((Double($0) * min(1, max(0, fraction))).rounded()) }
        }
        let now = Date()
        let speed = downloadSpeedBytesPerSecond(bytesWritten: resolvedBytesWritten, now: now)
        let state = ModelDownloadProgressViewState(
            providerID: providerID,
            componentName: componentName,
            statusText: statusText,
            fractionCompleted: fractionCompleted,
            bytesWritten: resolvedBytesWritten,
            totalBytes: resolvedTotalBytes,
            totalModelBytes: expectedLocalModelDownloadBytes(providerID: providerID),
            speedBytesPerSecond: speed
        )
        downloadProgress = state
        persistDownloadProgress(operation: operation, state: state)
        logDownloadProgressIfNeeded(state, now: now)
        previousDownloadProgressBytes = resolvedBytesWritten
        previousDownloadProgressDate = now
    }

    private func persistDownloadProgress(
        operation: ModelDownloadOperation,
        state: ModelDownloadProgressViewState
    ) {
        let bytesWritten = state.bytesWritten ?? 0
        let progress = ModelDownloadProgress(
            bytesWritten: bytesWritten,
            totalBytes: state.totalBytes ?? state.totalModelBytes,
            componentID: ModelComponentID(rawValue: state.componentName)
        )
        if state.providerID == ASRProviderID.qwen3, let qwenModelSize = operation.qwenModelSize {
            asrManager.markQwen3ModelDownloading(for: qwenModelSize, progress: progress)
            return
        }
        guard let engineType = fallbackEngine(for: state.providerID) else {
            return
        }
        asrManager.markModelDownloading(for: engineType, progress: progress)
    }

    private func downloadSpeedBytesPerSecond(bytesWritten: Int64?, now: Date) -> Int64? {
        guard let bytesWritten,
              let previousBytes = previousDownloadProgressBytes,
              let previousDate = previousDownloadProgressDate else {
            return nil
        }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0.5, bytesWritten > previousBytes else {
            return nil
        }
        return Int64(Double(bytesWritten - previousBytes) / elapsed)
    }

    private func logDownloadProgressIfNeeded(
        _ state: ModelDownloadProgressViewState,
        now: Date
    ) {
        let progress = state.progressValue ?? 0
        let shouldLogByTime = lastDownloadLogDate.map { now.timeIntervalSince($0) >= 10 } ?? true
        let shouldLogByProgress = lastDownloadLogProgress.map { progress - $0 >= 0.05 } ?? true
        guard shouldLogByTime || shouldLogByProgress || progress >= 1 else {
            return
        }
        lastDownloadLogDate = now
        lastDownloadLogProgress = progress
        Self.downloadLogger.info(
            "model_download_progress provider=\(state.providerID) component=\(state.componentName) bytesWritten=\(state.bytesWritten.map(String.init) ?? "unknown") totalBytes=\(state.totalBytes.map(String.init) ?? "unknown") fraction=\(String(format: "%.4f", progress)) speedBps=\(state.speedBytesPerSecond.map(String.init) ?? "unknown")"
        )
    }

    private func expectedLocalModelDownloadBytes(providerID: String) -> Int64? {
        switch providerID {
        case ASRProviderID.qwen3:
            return downloader.expectedDownloadBytes(for: asrManager.qwen3ModelSize)
        case ASRProviderID.whisper:
            switch asrManager.whisperVariant {
            case .turbo:
                return 632_000_000
            case .largeV3:
                return 947_000_000
            }
        case ASRProviderID.funASR:
            switch asrManager.funASRPrecision {
            case .int8:
                return 841_730_611
            case .fp32:
                return 1_317_656_544
            }
        case ASRProviderID.senseVoice:
            return 1_649_994_200
        case ASRProviderID.paraformer:
            return 653_174_435
        case ASRProviderID.nvidiaNemotron:
            return 642_196_943
        case ASRProviderID.parakeetStreaming:
            return 118_097_523
        case ASRProviderID.omnilingualASR:
            return 326_905_047
        default:
            return nil
        }
    }

    private func localModelSpecification(providerID: String) -> String? {
        switch providerID {
        case ASRProviderID.funASR:
            return "Qwen3 0.6B \(asrManager.funASRPrecision.rawValue.uppercased())"
        case ASRProviderID.senseVoice:
            return "SenseVoice Small FP16"
        case ASRProviderID.paraformer:
            return "Paraformer Large zh INT8"
        case ASRProviderID.nvidiaNemotron:
            return "Nemotron 0.6B CoreML INT8"
        case ASRProviderID.parakeetStreaming:
            return "Parakeet 120M CoreML INT8"
        case ASRProviderID.omnilingualASR:
            return "Omnilingual 300M CoreML INT8"
        default:
            return nil
        }
    }

    func downloadModel(id: String) async {
        guard !isDownloading else {
            Self.logger.debug("asr_provider_vm_download_model_skipped alreadyDownloading=true id=\(id)")
            return
        }
        Self.logger.info("asr_provider_vm_download_model_start id=\(id)")
        let operation = ModelDownloadOperation(
            providerID: id,
            qwenModelSize: id == ASRProviderID.qwen3 ? asrManager.qwen3ModelSize : nil
        )
        activeDownloadOperation = operation
        isDownloading = true
        downloadingProviderID = id
        downloadProgress = nil
        lastError = nil
        beginDownloadTracking(providerID: id)
        defer {
            if activeDownloadOperation == operation {
                activeDownloadOperation = nil
                isDownloading = false
                downloadingProviderID = nil
            }
        }

        do {
            if id == ASRProviderID.qwen3 {
                let modelSize = operation.qwenModelSize ?? asrManager.qwen3ModelSize
                let coordinator = SettingsQwenModelDownloadCoordinator(
                    asrManager: asrManager,
                    downloader: downloader,
                    readinessPreparer: qwenReadinessPreparer,
                    fileManager: fileManager
                )
                let installedURL = try await coordinator.downloadQwen3Model(size: modelSize) { [weak self] progress in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: progress.fileName,
                        statusText: "下载 \(progress.fileName)",
                        fractionCompleted: progress.overallProgress,
                        bytesWritten: progress.bytesWritten,
                        totalBytes: progress.totalBytes
                    )
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markQwen3ModelReady(at: installedURL.path, size: modelSize)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = whisperKitVariant(for: id) {
                let paths = try ApplicationSupportPaths.live(fileManager: fileManager)
                let installedURL = try await whisperKitModelDownloader.download(
                    variant: variant,
                    modelsDirectory: paths.modelsDirectory
                ) { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted
                    )
                }
                guard variant.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markWhisperModelReady(at: installedURL.path, variant: asrManager.whisperVariant)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = sherpaVariant(for: id) {
                let installedURL = try await sherpaModelDownloader.download(variant: variant) { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted,
                        bytesWritten: update.bytesWritten,
                        totalBytes: update.totalBytes
                    )
                }
                guard FunASRModelVariant(precision: asrManager.funASRPrecision).modelsExist(
                    at: installedURL,
                    fileManager: fileManager
                ) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markFunASRModelReady(at: installedURL.path, precision: asrManager.funASRPrecision)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.senseVoice {
                let installedURL = try await senseVoiceModelDownloader.download { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted
                    )
                }
                guard SenseVoiceModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markSenseVoiceModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.paraformer {
                let installedURL = try await paraformerModelDownloader.download { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted
                    )
                }
                guard ParaformerModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markParaformerModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.nvidiaNemotron {
                let installedURL = try await nvidiaNemotronModelDownloader.download { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted
                    )
                }
                guard NVIDIANemotronModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markNVIDIANemotronModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.parakeetStreaming {
                let installedURL = try await parakeetModelDownloader.download { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted
                    )
                }
                guard ParakeetModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markParakeetModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.omnilingualASR {
                let installedURL = try await omnilingualModelDownloader.download { [weak self] update in
                    self?.setDownloadProgress(
                        operation: operation,
                        providerID: id,
                        componentName: update.status,
                        statusText: update.status,
                        fractionCompleted: update.fractionCompleted
                    )
                }
                guard OmnilingualModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                guard shouldApplyDownloadResult(operation) else {
                    return
                }
                asrManager.markOmnilingualModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else {
                Self.logger.warning("asr_provider_vm_download_model_skipped unsupported id=\(id)")
                return
            }
            Self.logger.info("asr_provider_vm_download_model_success id=\(id)")
            finishDownloadTracking(providerID: id)
        } catch {
            if shouldIgnoreDownloadFailure(operation) {
                return
            }
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_download_model_failed id=\(id) error=\(error.localizedDescription)")
            failDownloadTracking(providerID: id, error: error)
        }
    }

    private func shouldApplyDownloadResult(_ operation: ModelDownloadOperation) -> Bool {
        if cleanupRequestedDownloadIDs.remove(operation.id) != nil {
            lastError = nil
            if lastActionMessage == nil {
                lastActionMessage = "已删除本地模型"
            }
            Self.logger.info(
                "asr_provider_vm_download_model_ignored_after_cleanup id=\(operation.providerID)"
            )
            return false
        }
        guard activeDownloadOperation == operation else {
            Self.logger.info(
                "asr_provider_vm_download_model_ignored_stale_operation id=\(operation.providerID)"
            )
            return false
        }
        return true
    }

    private func shouldIgnoreDownloadFailure(_ operation: ModelDownloadOperation) -> Bool {
        if cleanupRequestedDownloadIDs.remove(operation.id) != nil {
            lastError = nil
            if lastActionMessage == nil {
                lastActionMessage = "已删除本地模型"
            }
            Self.logger.info(
                "asr_provider_vm_download_model_cancelled_after_cleanup id=\(operation.providerID)"
            )
            return true
        }
        guard activeDownloadOperation == operation else {
            Self.logger.info(
                "asr_provider_vm_download_model_ignored_stale_failure id=\(operation.providerID)"
            )
            return true
        }
        return false
    }

    func deleteLocalQwenModel() {
        deleteLocalModel(id: ASRProviderID.qwen3)
    }

    func deleteLocalModel(id: String) {
        guard let fallbackEngine = self.fallbackEngine(for: id) else {
            Self.logger.warning("asr_provider_vm_delete_local_model_skipped id=\(id)")
            return
        }
        Self.logger.info("asr_provider_vm_delete_local_model_start id=\(id) engine=\(fallbackEngine.rawValue)")
        let urlsToDelete = modelDeletionURLs(id: id)
        if isDownloading, downloadingProviderID == id {
            if let operation = activeDownloadOperation, operation.providerID == id {
                cleanupRequestedDownloadIDs.insert(operation.id)
                activeDownloadOperation = nil
            }
            downloadProgress = ModelDownloadProgressViewState(
                providerID: id,
                componentName: "清理模型",
                statusText: "正在取消下载并清理模型",
                fractionCompleted: nil,
                bytesWritten: nil,
                totalBytes: nil,
                totalModelBytes: nil,
                speedBytesPerSecond: nil
            )
            Task { @MainActor in
                await cancelActiveDownload(id: id)
                completeLocalModelDeletion(
                    id: id,
                    fallbackEngine: fallbackEngine,
                    urlsToDelete: urlsToDelete
                )
                isDownloading = false
                downloadingProviderID = nil
                downloadProgress = nil
            }
            return
        }
        completeLocalModelDeletion(
            id: id,
            fallbackEngine: fallbackEngine,
            urlsToDelete: urlsToDelete
        )
    }

    private func cancelActiveDownload(id: String) async {
        switch id {
        case ASRProviderID.qwen3:
            await downloader.cancelDownload()
        case ASRProviderID.funASR:
            await sherpaModelDownloader.cancelDownload()
        default:
            break
        }
    }

    private func completeLocalModelDeletion(
        id: String,
        fallbackEngine: ASREngineType,
        urlsToDelete: [URL]
    ) {
        asrManager.markModelDeleting(for: fallbackEngine)
        load()
        do {
            for url in urlsToDelete where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            if id == ASRProviderID.qwen3 {
                asrManager.clearModelInstallationState(for: .qwen3)
            } else {
                asrManager.clearModelInstallationState(for: fallbackEngine)
            }

            if asrManager.selectedEngineType == fallbackEngine {
                asrManager.selectedEngineType = .apple
            }
            load()
            lastError = nil
            lastActionMessage = "已删除本地模型"
            Self.logger.info("asr_provider_vm_delete_local_model_success id=\(id) pathCount=\(urlsToDelete.count)")
        } catch {
            asrManager.markModelDeletionFailed(for: fallbackEngine, message: error.localizedDescription)
            load()
            lastActionMessage = nil
            lastError = error.localizedDescription
            Self.logger.error("asr_provider_vm_delete_local_model_failed id=\(id) error=\(error.localizedDescription)")
        }
    }

    private func modelDeletionURLs(id: String) -> [URL] {
        if id == ASRProviderID.qwen3 {
            return ASRManager.ModelSize.allCases
                .flatMap { asrManager.qwen3ModelDeletionURLs(for: $0) }
                .reduce(into: []) { result, url in
                    guard !result.contains(url) else { return }
                    result.append(url)
                }
        }
        var urls = modelPath(id: id).map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? []
        if let sherpaVariant = sherpaVariant(for: id) {
            urls.append(sherpaVariant.partialArchiveURL)
        }
        return urls.reduce(into: []) { result, url in
            guard !result.contains(url) else { return }
            result.append(url)
        }
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func persistProviderRecords() throws {
        Self.logger.debug("asr_provider_vm_persist_provider_records_start providers=\(providers.count)")
        let existing = try environment.asrProviderRepository.list()
            .reduce(into: [String: ASRProviderRecord]()) { partial, record in
                partial[record.id] = record
            }
        let now = environment.clock.now
        for descriptor in providers {
            let record = ASRProviderRecord(
                id: descriptor.id,
                displayName: descriptor.displayName,
                providerType: descriptor.providerType,
                capabilitiesJSON: jsonString(descriptor.capabilities.identifiers),
                tagsJSON: jsonString(descriptor.tags),
                configJSON: jsonString([
                    "modelSize": descriptor.modelSize?.rawValue ?? "",
                    "privacy": descriptor.privacySummary,
                ]),
                enabled: true,
                isDefault: descriptor.isDefault,
                lastHealthStatus: healthStatus(for: descriptor),
                lastHealthMessage: descriptor.statusMessage,
                lastCheckedAt: now,
                createdAt: existing[descriptor.id]?.createdAt ?? now,
                updatedAt: now
            )
            try environment.asrProviderRepository.save(record)
        }
        Self.logger.info("asr_provider_vm_persist_provider_records_success providers=\(providers.count)")
    }

    private func healthStatus(for descriptor: ASRProviderDescriptor) -> String {
        descriptor.healthStatus.rawValue
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
