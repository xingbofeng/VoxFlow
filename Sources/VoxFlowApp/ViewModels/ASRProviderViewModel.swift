import Combine
import Foundation
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
            return "全部"
        case .online:
            return "在线"
        case .offline:
            return "离线"
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
            return ASRProviderTagPresentation.cardTags(for: descriptor).contains("在线")
        case .offline:
            return ASRProviderTagPresentation.cardTags(for: descriptor).contains("离线")
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
}

private enum GroqASRConfigurationError: LocalizedError {
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

private enum TencentCloudASRConfigurationError: LocalizedError {
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

private enum AliyunDashScopeASRConfigurationError: LocalizedError {
    case emptyAPIKey
    case emptyModel

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "阿里云百炼 API Key 不能为空。"
        case .emptyModel:
            return "阿里云百炼识别模型不能为空。"
        }
    }
}

struct GroqASRModelOption: Identifiable, Equatable {
    let id: String
    let title: String
}

@MainActor
final class ASRProviderViewModel: ObservableObject {
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
    @Published private(set) var downloadProgress: Qwen3ModelDownloadProgress?
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
    @Published private(set) var isTestingAliyunDashScope = false

    private let environment: any AppServiceProviding
    private let asrManager: ASRManager
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
        groqBaseURLInput = resolvedASRManager.groqBaseURL
        groqModelInput = Self.supportedGroqModels.contains { $0.id == resolvedASRManager.groqModel }
            ? resolvedASRManager.groqModel
            : GroqCloudASRClient.defaultModel
        groqAPIKeyInput = resolvedASRManager.isGroqConfigured ? Self.storedGroqAPIKeyMask : ""
        let tencentCredentials = resolvedASRManager.storedTencentCloudCredentials()
        tencentAppIDInput = tencentCredentials.appID
        tencentSecretIDInput = tencentCredentials.secretID
        tencentSecretKeyInput = tencentCredentials.secretKey.isEmpty ? "" : Self.storedTencentSecretMask
        tencentEngineModelTypeInput = TencentRealtimeASRConfiguration.defaultEngineModelType
        aliyunDashScopeAPIKeyInput = resolvedASRManager.isAliyunDashScopeConfigured
            ? Self.storedAliyunDashScopeAPIKeyMask
            : ""
        aliyunDashScopeModelInput = AliyunDashScopeRealtimeASRConfiguration.defaultModel
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
        return ASRProviderTagPresentation.approvedCardTags.filter { tag in
            tag != "离线" && tag != "在线" && scopedTagSet.contains(tag)
        }
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
        do {
            try persistGroqConfiguration()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已保存 Groq 配置"
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func testGroqConnection() async {
        guard !isTestingGroq else { return }
        isTestingGroq = true
        defer { isTestingGroq = false }
        do {
            try persistGroqConfiguration()
            let result = try await asrManager.testGroqConnection()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = result.message
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func deleteGroqAPIKey() {
        do {
            try asrManager.saveGroqAPIKey("")
            groqAPIKeyInput = ""
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已删除 Groq API Key"
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func saveTencentCloudConfiguration() {
        do {
            try persistTencentCloudConfiguration()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已保存腾讯云配置"
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func testTencentCloudConnection() async {
        guard !isTestingTencentCloud else { return }
        isTestingTencentCloud = true
        defer { isTestingTencentCloud = false }
        do {
            try persistTencentCloudConfiguration()
            let result = try await asrManager.testTencentCloudConnection()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = result.message
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func deleteTencentCloudCredentials() {
        do {
            try asrManager.deleteTencentCloudCredentials()
            tencentAppIDInput = ""
            tencentSecretIDInput = ""
            tencentSecretKeyInput = ""
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已删除腾讯云凭据"
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func saveAliyunDashScopeConfiguration() {
        do {
            try persistAliyunDashScopeConfiguration()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已保存阿里云百炼配置"
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func testAliyunDashScopeConnection() async {
        guard !isTestingAliyunDashScope else { return }
        isTestingAliyunDashScope = true
        defer { isTestingAliyunDashScope = false }
        do {
            try persistAliyunDashScopeConfiguration()
            let result = try await asrManager.testAliyunDashScopeConnection()
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = result.message
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func deleteAliyunDashScopeAPIKey() {
        do {
            try asrManager.saveAliyunDashScopeAPIKey("")
            aliyunDashScopeAPIKeyInput = ""
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = "已删除阿里云百炼 API Key"
        } catch {
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    private func persistGroqConfiguration() throws {
        let baseURL = groqBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: baseURL),
              components.scheme == "https",
              components.host != nil else {
            throw GroqASRConfigurationError.invalidHTTPSURL
        }
        let model = groqModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw GroqASRConfigurationError.emptyModel
        }
        guard Self.supportedGroqModels.contains(where: { $0.id == model }) else {
            throw GroqASRConfigurationError.unsupportedModel
        }
        let key = groqAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && key != Self.storedGroqAPIKeyMask {
            try asrManager.saveGroqAPIKey(key)
            groqAPIKeyInput = Self.storedGroqAPIKeyMask
        } else if !asrManager.isGroqConfigured {
            throw CloudASRClientError.missingCredential
        } else {
            groqAPIKeyInput = Self.storedGroqAPIKeyMask
        }
        asrManager.groqBaseURL = baseURL
        asrManager.groqModel = model
    }

    private func persistTencentCloudConfiguration() throws {
        let stored = asrManager.storedTencentCloudCredentials()
        let appID = try resolvedTencentValue(
            input: tencentAppIDInput,
            stored: stored.appID,
            missingError: TencentCloudASRConfigurationError.emptyAppID
        )
        let secretID = try resolvedTencentValue(
            input: tencentSecretIDInput,
            stored: stored.secretID,
            missingError: TencentCloudASRConfigurationError.emptySecretID
        )
        let secretKey = try resolvedTencentValue(
            input: tencentSecretKeyInput,
            stored: stored.secretKey,
            missingError: TencentCloudASRConfigurationError.emptySecretKey
        )
        try asrManager.saveTencentCloudCredentials(
            appID: appID,
            secretID: secretID,
            secretKey: secretKey
        )
        asrManager.tencentRealtimeEngineModelType = TencentRealtimeASRConfiguration.defaultEngineModelType
        tencentEngineModelTypeInput = TencentRealtimeASRConfiguration.defaultEngineModelType
        tencentAppIDInput = appID
        tencentSecretIDInput = secretID
        tencentSecretKeyInput = Self.storedTencentSecretMask
    }

    private func resolvedTencentValue(
        input: String,
        stored: String,
        missingError: TencentCloudASRConfigurationError
    ) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isMaskedTencentSecret(text: trimmed), !stored.isEmpty {
            return stored
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        if !stored.isEmpty {
            return stored
        }
        throw missingError
    }

    private func persistAliyunDashScopeConfiguration() throws {
        let key = aliyunDashScopeAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && key != Self.storedAliyunDashScopeAPIKeyMask {
            try asrManager.saveAliyunDashScopeAPIKey(key)
            aliyunDashScopeAPIKeyInput = Self.storedAliyunDashScopeAPIKeyMask
        } else if !asrManager.isAliyunDashScopeConfigured {
            throw AliyunDashScopeASRConfigurationError.emptyAPIKey
        } else {
            aliyunDashScopeAPIKeyInput = Self.storedAliyunDashScopeAPIKeyMask
        }
        asrManager.aliyunDashScopeModel = AliyunDashScopeRealtimeASRConfiguration.defaultModel
        aliyunDashScopeModelInput = AliyunDashScopeRealtimeASRConfiguration.defaultModel
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
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.funASR)
        }
        asrManager.funASRPrecision = precision
        configurationDidChange()
    }

    func selectWhisperVariant(_ variant: ASRManager.WhisperVariant, selectingProvider: Bool = false) {
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.whisper)
        }
        guard ASRManager.isWhisperRuntimeSupported(variant: variant) else {
            lastActionMessage = nil
            lastError = ASRManager.whisperRuntimeUnsupportedMessage(for: variant)
            return
        }
        asrManager.whisperVariant = variant
        configurationDidChange()
    }

    func selectQwenModelSize(_ size: ASRManager.ModelSize, selectingProvider: Bool = false) {
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.qwen3)
        }
        asrManager.qwen3ModelSize = size
        configurationDidChange()
    }

    func selectProviderForConfiguration(id: String) {
        guard let fallbackEngine = fallbackEngine(for: id) else { return }
        asrManager.selectedEngineType = fallbackEngine
    }

    private func configurationDidChange() {
        refreshProviders(persistRecords: false)
        scheduleProviderRecordPersistence()
        lastError = nil
        lastActionMessage = "已切换模型配置"
    }

    func load() {
        refreshProviders(persistRecords: true)
    }

    private func refreshProviders(persistRecords: Bool) {
        do {
            providers = registry.descriptors()
            if persistRecords {
                try persistProviderRecords()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func scheduleProviderRecordPersistence() {
        providerRecordPersistenceTask?.cancel()
        providerRecordPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let self, !Task.isCancelled else { return }
                try self.persistProviderRecords()
            } catch is CancellationError {
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    func toggleTag(_ tag: String) {
        guard availableTags.contains(tag) else {
            selectedTags.remove(tag)
            return
        }
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func selectProviderScope(_ scope: ASRProviderScope) {
        providerScope = scope
        selectedTags.formIntersection(availableTags)
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
        do {
            try registry.selectDefaultProvider(id: id)
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = nil
        } catch {
            let message = error.localizedDescription
            load()
            lastError = message
        }
    }

    func setQwenModelPath(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard Qwen3ModelManifest.supportedModelExists(at: url, fileManager: fileManager) else {
            lastError = "所选目录不是可用的 Qwen3-ASR 模型。"
            return
        }
        asrManager.qwen3ModelPath = path
        load()
        lastError = nil
        lastActionMessage = "已设置本地模型目录"
    }

    func downloadQwenModel() async {
        await downloadModel(id: ASRProviderID.qwen3)
    }

    private func modelPath(id: String) -> String? {
        switch id {
        case ASRProviderID.qwen3: return asrManager.qwen3ModelPath
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

    func downloadModel(id: String) async {
        isDownloading = true
        downloadingProviderID = id
        downloadProgress = nil
        lastError = nil
        defer {
            isDownloading = false
            downloadingProviderID = nil
        }

        do {
            if id == ASRProviderID.qwen3 {
                let modelSize = asrManager.qwen3ModelSize
                let coordinator = SettingsQwenModelDownloadCoordinator(
                    asrManager: asrManager,
                    downloader: downloader,
                    readinessPreparer: qwenReadinessPreparer,
                    fileManager: fileManager
                )
                _ = try await coordinator.downloadQwen3Model(size: modelSize) { [weak self] progress in
                    self?.downloadProgress = progress
                }
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = whisperKitVariant(for: id) {
                let paths = try ApplicationSupportPaths.live(fileManager: fileManager)
                let installedURL = try await whisperKitModelDownloader.download(
                    variant: variant,
                    modelsDirectory: paths.modelsDirectory
                ) { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard variant.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markWhisperModelReady(at: installedURL.path, variant: asrManager.whisperVariant)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = sherpaVariant(for: id) {
                let installedURL = try await sherpaModelDownloader.download(variant: variant) { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted ?? 0
                    )
                }
                guard FunASRModelVariant(precision: asrManager.funASRPrecision).modelsExist(
                    at: installedURL,
                    fileManager: fileManager
                ) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markFunASRModelReady(at: installedURL.path, precision: asrManager.funASRPrecision)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.senseVoice {
                let installedURL = try await senseVoiceModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard SenseVoiceModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markSenseVoiceModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.paraformer {
                let installedURL = try await paraformerModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard ParaformerModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markParaformerModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.nvidiaNemotron {
                let installedURL = try await nvidiaNemotronModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard NVIDIANemotronModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markNVIDIANemotronModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.parakeetStreaming {
                let installedURL = try await parakeetModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard ParakeetModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markParakeetModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.omnilingualASR {
                let installedURL = try await omnilingualModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard OmnilingualModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markOmnilingualModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else {
                return
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteLocalQwenModel() {
        deleteLocalModel(id: ASRProviderID.qwen3)
    }

    func deleteLocalModel(id: String) {
        guard let fallbackEngine = self.fallbackEngine(for: id) else { return }
        let pathToDelete = modelPath(id: id)
        asrManager.markModelDeleting(for: fallbackEngine)
        load()
        do {
            if let path = pathToDelete, fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: URL(fileURLWithPath: path, isDirectory: true))
            }
            if id == ASRProviderID.qwen3 {
                asrManager.qwen3ModelPath = nil
            } else {
                asrManager.clearModelInstallationState(for: fallbackEngine)
            }

            if asrManager.selectedEngineType == fallbackEngine {
                asrManager.selectedEngineType = .apple
            }
            load()
            lastError = nil
            lastActionMessage = "已删除本地模型"
        } catch {
            asrManager.markModelDeletionFailed(for: fallbackEngine, message: error.localizedDescription)
            load()
            lastActionMessage = nil
            lastError = error.localizedDescription
        }
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func persistProviderRecords() throws {
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
