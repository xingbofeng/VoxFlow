import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
import VoxFlowProviderAliyunDashScope
import VoxFlowProviderCloudCore
import VoxFlowProviderFunASR
import VoxFlowProviderGroq
import VoxFlowProviderNVIDIA
import VoxFlowProviderOmnilingual
import VoxFlowProviderParakeet
import VoxFlowProviderParaformer
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderTencentCloud
import VoxFlowProviderVolcengine
import VoxFlowProviderWhisper

enum LocalModelDeletionError: LocalizedError, Equatable {
    case modelOperationInProgress

    var errorDescription: String? {
        switch self {
        case .modelOperationInProgress:
            return "本地模型正在下载、验证或删除中，请等待完成后再删除全部本地模型。"
        }
    }
}

final class ASRManager: ASREngineFactory, @unchecked Sendable {
    struct SelectionFallbackNotice: Equatable {
        let selectedEngineType: ASREngineType
        let effectiveEngineType: ASREngineType

        var message: String {
            "已选的 \(selectedEngineType.displayName) 不可用，临时改用\(effectiveEngineType.displayName)。"
        }
    }

    enum ModelSize: String, CaseIterable, Equatable {
        case size0_6B = "0.6B"
        case size1_7B = "1.7B"
    }

    enum FunASRPrecision: String, CaseIterable, Equatable {
        case int8 = "INT8"
        case fp32 = "FP32"
    }

    enum WhisperVariant: String, CaseIterable, Equatable {
        case turbo = "Turbo"
        case largeV3 = "Large V3"
    }

    private let defaults: UserDefaults
    private let modelInstallationRepository: (any ModelInstallationStateStoring)?
    private let qwen3RuntimePreflight: (ModelSize) -> Qwen3RuntimePreflightResult
    private let cloudCredentials: ASRCloudCredentialManager
    private let modelStoreRoot: URL?

    private enum Keys {
        static let selectedEngineType = "ASRManager.selectedEngineType"
        static let qwen3ModelSize = "ASRManager.qwen3ModelSize"
        static let qwen3ModelPath = "ASRManager.qwen3ModelPath"
        static let qwen3ValidatedModelPath = "ASRManager.qwen3ValidatedModelPath"
        static let qwen3ValidatedModelSize = "ASRManager.qwen3ValidatedModelSize"
        static let funASRPrecision = "ASRManager.funASRPrecision"
        static let whisperVariant = "ASRManager.whisperVariant"
        static let groqBaseURL = "ASRManager.groqBaseURL"
        static let groqModel = "ASRManager.groqModel"
        static let tencentRealtimeEngineModelType = "ASRManager.tencentRealtimeEngineModelType"
        static let aliyunDashScopeModel = "ASRManager.aliyunDashScopeModel"
        static let aliyunDashScopeVocabularyID = "ASRManager.aliyunDashScopeVocabularyID"
    }

    static let groqAPIKeyAccount = "asr.groq.api-key"
    static let tencentAppIDAccount = "asr.tencent.app-id"
    static let tencentSecretIDAccount = "asr.tencent.secret-id"
    static let tencentSecretKeyAccount = "asr.tencent.secret-key"
    static let aliyunDashScopeAPIKeyAccount = "asr.aliyun-dashscope.api-key"
    static let volcengineAppIDAccount = "asr.volcengine.app-id"
    static let volcengineAccessTokenAccount = "asr.volcengine.access-token"
    static let volcengineSecretKeyAccount = "asr.volcengine.secret-key"

    var funASRPrecision: FunASRPrecision {
        get {
            defaults.string(forKey: Keys.funASRPrecision)
                .flatMap(FunASRPrecision.init(rawValue:)) ?? .int8
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.funASRPrecision) }
    }

    var whisperVariant: WhisperVariant {
        get {
            defaults.string(forKey: Keys.whisperVariant)
                .flatMap(WhisperVariant.init(rawValue:)) ?? .turbo
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.whisperVariant) }
    }

    var funASRModelVariant: SherpaASRModelVariant {
        funASRPrecision == .int8 ? .funASRInt8 : .funASRFP32
    }

    var whisperModelVariant: WhisperKitModelVariant {
        whisperVariant == .turbo ? .turbo : .largeV3
    }

    var isFunASRModelAvailable: Bool {
        isFunASRModelAvailable(for: funASRPrecision)
    }
    var isWhisperModelAvailable: Bool {
        isWhisperModelAvailable(for: whisperVariant)
    }

    var isSenseVoiceModelAvailable: Bool {
        senseVoiceReadyInstallation() != nil
    }

    var isParaformerModelAvailable: Bool {
        paraformerReadyInstallation() != nil
    }

    var isNVIDIANemotronModelAvailable: Bool {
        nvidiaNemotronReadyInstallation() != nil
    }

    var isParakeetModelAvailable: Bool {
        parakeetReadyInstallation() != nil
    }

    var isOmnilingualModelAvailable: Bool {
        omnilingualReadyInstallation() != nil
    }

    var isNVIDIANemotronRuntimeSupported: Bool {
        Self.isNVIDIANemotronRuntimeSupported()
    }

    func isFunASRModelAvailable(for precision: FunASRPrecision) -> Bool {
        funASRReadyInstallation(for: precision) != nil
    }

    func isWhisperModelAvailable(for variant: WhisperVariant) -> Bool {
        whisperReadyInstallation(for: variant) != nil
    }

    static func isQwen3RuntimeSupported(size: ModelSize) -> Bool {
        qwen3RuntimePreflightResult(for: size).isSupported
    }

    static func qwen3RuntimeUnsupportedMessage(for size: ModelSize) -> String {
        qwen3RuntimePreflightResult(for: size).reason ?? ""
    }

    static func isWhisperRuntimeSupported(variant: WhisperVariant) -> Bool {
        true
    }

    static func whisperRuntimeUnsupportedMessage(for variant: WhisperVariant) -> String {
        ""
    }

    static func isNVIDIANemotronRuntimeSupported() -> Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    static func nvidiaNemotronRuntimeUnsupportedMessage() -> String {
        NVIDIANemotronProviderDescriptor.runtimeUnsupportedReason
    }

    init(
        defaults: UserDefaults = .standard,
        modelInstallationRepository: (any ModelInstallationStateStoring)? = nil,
        credentialStore: any CredentialStore = AppLocalCredentialStore.liveDefault(),
        settingsRepository: (any SettingsRepository)? = nil,
        qwen3RuntimePreflight: @escaping (ModelSize) -> Qwen3RuntimePreflightResult = ASRManager.qwen3RuntimePreflightResult(for:),
        modelStoreRoot: URL? = nil
    ) {
        self.defaults = defaults
        self.modelInstallationRepository = modelInstallationRepository ?? Self.defaultModelInstallationRepository(for: defaults)
        cloudCredentials = ASRCloudCredentialManager(
            credentialStore: credentialStore,
            settingsRepository: settingsRepository
        )
        self.qwen3RuntimePreflight = qwen3RuntimePreflight
        self.modelStoreRoot = modelStoreRoot ?? Self.defaultModelStoreRoot(for: defaults)
    }

    // MARK: - Engine Selection

    var selectedEngineType: ASREngineType {
        get {
            guard let raw = defaults.string(forKey: Keys.selectedEngineType),
                  let type = ASREngineType(rawValue: raw) else {
                return .apple
            }
            return type
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedEngineType)
        }
    }

    var groqBaseURL: String {
        get { defaults.string(forKey: Keys.groqBaseURL) ?? GroqCloudASRClient.defaultBaseURL }
        set { defaults.set(newValue, forKey: Keys.groqBaseURL) }
    }

    var groqModel: String {
        get { defaults.string(forKey: Keys.groqModel) ?? GroqCloudASRClient.defaultModel }
        set { defaults.set(newValue, forKey: Keys.groqModel) }
    }

    var tencentRealtimeEngineModelType: String {
        get {
            defaults.string(forKey: Keys.tencentRealtimeEngineModelType)
                ?? TencentRealtimeASRConfiguration.defaultEngineModelType
        }
        set { defaults.set(newValue, forKey: Keys.tencentRealtimeEngineModelType) }
    }

    var aliyunDashScopeModel: String {
        get {
            defaults.string(forKey: Keys.aliyunDashScopeModel)
                ?? AliyunDashScopeRealtimeASRConfiguration.defaultModel
        }
        set { defaults.set(newValue, forKey: Keys.aliyunDashScopeModel) }
    }

    var aliyunDashScopeVocabularyID: String {
        get {
            defaults.string(forKey: Keys.aliyunDashScopeVocabularyID) ?? ""
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.aliyunDashScopeVocabularyID)
        }
    }

    var isGroqConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.groqAPIKeyAccount)
    }

    func storedGroqAPIKey() -> String {
        cloudCredentials.storedCredential(account: Self.groqAPIKeyAccount)
    }

    func saveGroqAPIKey(_ apiKey: String) throws {
        try cloudCredentials.saveCredential(apiKey, account: Self.groqAPIKeyAccount)
    }

    func testGroqConnection() async throws -> ASRProviderHealthResult {
        try await GroqCloudASRClient(credentialStore: cloudCredentialStore()).testConnection(
            configuration: groqConfiguration
        )
    }

    var isTencentCloudConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.tencentAppIDAccount)
            && cloudCredentials.isConfigured(account: Self.tencentSecretIDAccount)
            && cloudCredentials.isConfigured(account: Self.tencentSecretKeyAccount)
    }

    func storedTencentCloudCredentials() -> (appID: String, secretID: String, secretKey: String) {
        (
            cloudCredentials.storedCredential(account: Self.tencentAppIDAccount),
            cloudCredentials.storedCredential(account: Self.tencentSecretIDAccount),
            cloudCredentials.storedCredential(account: Self.tencentSecretKeyAccount)
        )
    }

    func saveTencentCloudCredentials(appID: String, secretID: String, secretKey: String) throws {
        try cloudCredentials.saveCredential(appID, account: Self.tencentAppIDAccount)
        try cloudCredentials.saveCredential(secretID, account: Self.tencentSecretIDAccount)
        try cloudCredentials.saveCredential(secretKey, account: Self.tencentSecretKeyAccount)
    }

    func deleteTencentCloudCredentials() throws {
        try cloudCredentials.deleteCredential(account: Self.tencentAppIDAccount)
        try cloudCredentials.deleteCredential(account: Self.tencentSecretIDAccount)
        try cloudCredentials.deleteCredential(account: Self.tencentSecretKeyAccount)
    }

    func tencentCloudConfiguration() throws -> TencentRealtimeASRConfiguration {
        let credentials = storedTencentCloudCredentials()
        let configuration = TencentRealtimeASRConfiguration(
            appID: credentials.appID,
            secretID: credentials.secretID,
            secretKey: credentials.secretKey,
            engineModelType: tencentRealtimeEngineModelType
        )
        guard configuration.isComplete else {
            throw TencentRealtimeASRError.missingCredential
        }
        return configuration
    }

    func testTencentCloudConnection() async throws -> ASRProviderHealthResult {
        try await TencentRealtimeASRClient().testConnection(
            configuration: tencentCloudConfiguration()
        )
    }

    var isAliyunDashScopeConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func storedAliyunDashScopeAPIKey() -> String {
        cloudCredentials.storedCredential(account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func saveAliyunDashScopeAPIKey(_ apiKey: String) throws {
        try cloudCredentials.saveCredential(apiKey, account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func aliyunDashScopeConfiguration() throws -> AliyunDashScopeRealtimeASRConfiguration {
        let configuration = AliyunDashScopeRealtimeASRConfiguration(
            apiKey: storedAliyunDashScopeAPIKey(),
            model: aliyunDashScopeModel,
            vocabularyID: aliyunDashScopeVocabularyID
        )
        guard configuration.isComplete else {
            throw AliyunDashScopeRealtimeASRError.missingCredential
        }
        return configuration
    }

    func testAliyunDashScopeConnection() async throws -> ASRProviderHealthResult {
        try await AliyunDashScopeRealtimeASRClient().testConnection(
            configuration: aliyunDashScopeConfiguration()
        )
    }

    var isVolcengineConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.volcengineAppIDAccount)
            && cloudCredentials.isConfigured(account: Self.volcengineAccessTokenAccount)
            && cloudCredentials.isConfigured(account: Self.volcengineSecretKeyAccount)
    }

    func storedVolcengineCredentials() -> (appID: String, accessToken: String, secretKey: String) {
        (
            cloudCredentials.storedCredential(account: Self.volcengineAppIDAccount),
            cloudCredentials.storedCredential(account: Self.volcengineAccessTokenAccount),
            cloudCredentials.storedCredential(account: Self.volcengineSecretKeyAccount)
        )
    }

    func saveVolcengineCredentials(appID: String, accessToken: String, secretKey: String) throws {
        try cloudCredentials.saveCredential(appID, account: Self.volcengineAppIDAccount)
        try cloudCredentials.saveCredential(accessToken, account: Self.volcengineAccessTokenAccount)
        try cloudCredentials.saveCredential(secretKey, account: Self.volcengineSecretKeyAccount)
    }

    func deleteVolcengineCredentials() throws {
        try cloudCredentials.deleteCredential(account: Self.volcengineAppIDAccount)
        try cloudCredentials.deleteCredential(account: Self.volcengineAccessTokenAccount)
        try cloudCredentials.deleteCredential(account: Self.volcengineSecretKeyAccount)
    }

    func volcengineConfiguration() throws -> VolcengineRealtimeASRConfiguration {
        let credentials = storedVolcengineCredentials()
        let configuration = VolcengineRealtimeASRConfiguration(
            appID: credentials.appID,
            accessToken: credentials.accessToken,
            secretKey: credentials.secretKey
        )
        guard configuration.isComplete else {
            throw VolcengineRealtimeASRError.missingCredential
        }
        return configuration
    }

    func testVolcengineConnection() async throws -> ASRProviderHealthResult {
        try await VolcengineRealtimeASRClient().testConnection(
            configuration: volcengineConfiguration()
        )
    }

    var groqConfiguration: CloudASRProviderConfiguration {
        CloudASRProviderConfiguration(
            providerID: ASRProviderID.groqWhisper,
            displayName: "Groq（免费）",
            baseURL: groqBaseURL,
            model: groqModel,
            apiKeyRef: Self.groqAPIKeyAccount,
            timeoutSeconds: 60
        )
    }

    private func cloudCredentialStore() -> any CredentialStore {
        cloudCredentials
    }

    // MARK: - Qwen3 Configuration

    var qwen3ModelSize: ModelSize {
        get {
            guard let raw = defaults.string(forKey: Keys.qwen3ModelSize),
                  let size = ModelSize(rawValue: raw) else {
                return .size0_6B
            }
            return size
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.qwen3ModelSize)
        }
    }

    var qwen3ModelPath: String? {
        get {
            defaults.string(forKey: Keys.qwen3ModelPath)
        }
        set {
            if let path = newValue {
                defaults.set(path, forKey: Keys.qwen3ModelPath)
                if defaults.string(forKey: Keys.qwen3ValidatedModelPath) != path {
                    clearQwen3ValidatedModelPath()
                }
            } else {
                defaults.removeObject(forKey: Keys.qwen3ModelPath)
                clearQwen3ValidatedModelPath()
            }
        }
    }

    func markQwen3ModelReady(at path: String, size: ModelSize) {
        qwen3ModelSize = size
        qwen3ModelPath = path
        if let key = Self.qwen3ModelInstallKey(for: size),
           let modelInstallationRepository {
            let installation = ModelInstallation(
                modelID: key.modelID,
                version: key.version,
                installedRoot: URL(fileURLWithPath: path, isDirectory: true)
            )
            try? modelInstallationRepository.save(.ready(installation), for: key)
        }
        defaults.set(path, forKey: Keys.qwen3ValidatedModelPath)
        defaults.set(size.rawValue, forKey: Keys.qwen3ValidatedModelSize)
    }

    func markQwen3ModelDownloading(for size: ModelSize, progress: ModelDownloadProgress) {
        guard let key = Self.qwen3ModelInstallKey(for: size),
              let modelInstallationRepository else {
            return
        }
        try? modelInstallationRepository.save(.downloading(progress: progress), for: key)
    }

    func markWhisperModelReady(at path: String, variant: WhisperVariant) {
        guard let key = Self.whisperModelInstallKey(for: variant),
              let modelInstallationRepository else {
            return
        }
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func markFunASRModelReady(at path: String, precision: FunASRPrecision) {
        guard let key = Self.funASRModelInstallKey(for: precision),
              let modelInstallationRepository else {
            return
        }
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func markSenseVoiceModelReady(at path: String) {
        guard let modelInstallationRepository else {
            return
        }
        let key = Self.senseVoiceModelInstallKey()
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func markParaformerModelReady(at path: String) {
        guard let modelInstallationRepository else {
            return
        }
        let key = Self.paraformerModelInstallKey()
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func markNVIDIANemotronModelReady(at path: String) {
        guard let modelInstallationRepository else {
            return
        }
        let key = Self.nvidiaNemotronModelInstallKey()
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func markParakeetModelReady(at path: String) {
        guard let modelInstallationRepository else {
            return
        }
        let key = Self.parakeetModelInstallKey()
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func markOmnilingualModelReady(at path: String) {
        guard let modelInstallationRepository else {
            return
        }
        let key = Self.omnilingualModelInstallKey()
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? modelInstallationRepository.save(.ready(installation), for: key)
    }

    func clearModelInstallationState(for engineType: ASREngineType) {
        guard let modelInstallationRepository else {
            return
        }

        switch engineType {
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope, .volcengineDoubao:
            return
        case .qwen3:
            clearAllQwen3ModelInstallationStates()
        case .funASR:
            guard let key = Self.funASRModelInstallKey(for: funASRPrecision) else {
                return
            }
            try? modelInstallationRepository.removeState(for: key)
        case .whisper:
            guard let key = Self.whisperModelInstallKey(for: whisperVariant) else {
                return
            }
            try? modelInstallationRepository.removeState(for: key)
        case .senseVoice:
            try? modelInstallationRepository.removeState(for: Self.senseVoiceModelInstallKey())
        case .paraformer:
            try? modelInstallationRepository.removeState(for: Self.paraformerModelInstallKey())
        case .nvidiaNemotron:
            try? modelInstallationRepository.removeState(for: Self.nvidiaNemotronModelInstallKey())
        case .parakeetStreaming:
            try? modelInstallationRepository.removeState(for: Self.parakeetModelInstallKey())
        case .omnilingualASR:
            try? modelInstallationRepository.removeState(for: Self.omnilingualModelInstallKey())
        }
    }

    func markModelDeleting(for engineType: ASREngineType) {
        guard let key = self.modelInstallKey(for: engineType),
              let modelInstallationRepository,
              case let .ready(installation) = (try? modelInstallationRepository.state(for: key)) ?? .notInstalled else {
            return
        }
        AppLogger.general.info("Marking model deleting: \(engineType.rawValue)")
        try? modelInstallationRepository.save(.deleting(installation), for: key)
    }

    func markModelDownloading(for engineType: ASREngineType, progress: ModelDownloadProgress) {
        guard let key = self.modelInstallKey(for: engineType),
              let modelInstallationRepository else {
            return
        }
        try? modelInstallationRepository.save(.downloading(progress: progress), for: key)
    }

    func markModelDeletionFailed(for engineType: ASREngineType, message: String) {
        guard let key = self.modelInstallKey(for: engineType),
              let modelInstallationRepository else {
            return
        }
        AppLogger.general.error("Model deletion failed: \(engineType.rawValue), reason=\(message)")
        try? modelInstallationRepository.save(.failed(message: message), for: key)
    }

    func restoreModelInstallationState(_ state: ModelInstallationState, for engineType: ASREngineType) {
        guard let key = self.modelInstallKey(for: engineType),
              let modelInstallationRepository else {
            return
        }
        switch state {
        case .notInstalled:
            try? modelInstallationRepository.removeState(for: key)
        default:
            try? modelInstallationRepository.save(state, for: key)
        }
    }

    func modelInstallationState(for engineType: ASREngineType) -> ModelInstallationState {
        switch engineType {
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope, .volcengineDoubao:
            return .notInstalled
        case .qwen3:
            return qwen3ModelInstallationState(for: qwen3ModelSize)
        case .funASR:
            return funASRModelInstallationState(for: funASRPrecision)
        case .whisper:
            return whisperModelInstallationState(for: whisperVariant)
        case .senseVoice:
            return senseVoiceModelInstallationState()
        case .paraformer:
            return paraformerModelInstallationState()
        case .nvidiaNemotron:
            return nvidiaNemotronModelInstallationState()
        case .parakeetStreaming:
            return parakeetModelInstallationState()
        case .omnilingualASR:
            return omnilingualModelInstallationState()
        }
    }

    /// Finds the path for a specific Qwen3 model size only after ModelStore marks it ready.
    func qwen3ModelPath(for size: ModelSize) -> String? {
        if let installation = qwen3ReadyInstallation(for: size) {
            return installation.installedRoot.path
        }
        return nil
    }

    /// Checks provider readiness using the ModelStore lifecycle state.
    var isQwen3ModelAvailable: Bool {
        qwen3ReadyInstallation(for: qwen3ModelSize) != nil
    }

    var qwen3ModelInstallationState: ModelInstallationState {
        qwen3ModelInstallationState(for: qwen3ModelSize)
    }

    func qwen3StoredModelInstallationState(for size: ModelSize) -> ModelInstallationState {
        guard let key = Self.qwen3ModelInstallKey(for: size),
              let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: key)) ?? .notInstalled
        let validated = Self.validatedReadyState(state) { installation in
            Qwen3ModelManifest.manifest(for: size).modelsExist(at: installation.installedRoot)
        }
        switch validated {
        case .notInstalled, .corrupt:
            if let discovered = discoverQwen3ReadyInstallation(for: size, key: key) {
                try? modelInstallationRepository.save(.ready(discovered), for: key)
                return .ready(discovered)
            }
        default:
            break
        }
        return validated
    }

    func qwen3ModelInstallationState(for size: ModelSize) -> ModelInstallationState {
        let preflight = qwen3RuntimePreflight(size)
        switch preflight {
        case .supported:
            break
        case .runtimeUnsupported(let reason):
            return .runtimeUnsupported(reason: reason)
        case .hardwareUnsupported(let reason):
            return .hardwareUnsupported(reason: reason)
        }
        return qwen3StoredModelInstallationState(for: size)
    }

    /// Checks if a specific Qwen3 model size is available anywhere on disk
    /// (either via UserDefaults path or default installation folder).
    /// Used by the flattened menu bar items to enable/disable size options.
    func isQwen3ModelAvailableOnDisk(for size: ModelSize) -> Bool {
        qwen3ModelPath(for: size) != nil
    }

    func qwen3ModelDeletionURLs(for size: ModelSize) -> [URL] {
        guard let key = Self.qwen3ModelInstallKey(for: size) else {
            return qwen3ModelPath(for: size)
                .map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? []
        }

        var urls: [URL] = []
        if case let .ready(installation) = qwen3StoredModelInstallationState(for: size) {
            urls.append(installation.installedRoot)
        }

        if let modelStoreRoot {
            let manifest = Qwen3ModelManifest.manifest(for: size)
            urls.append(
                ResumableModelDownloader.stagingRoot(for: key, storeRoot: modelStoreRoot)
            )
            urls.append(
                contentsOf: qwen3ModelStoreCandidates(
                    root: modelStoreRoot,
                    key: key,
                    manifest: manifest
                )
            )
        }

        return urls.reduce(into: []) { result, url in
            guard !result.contains(url) else { return }
            result.append(url)
        }
    }

    var effectiveSelectedEngineType: ASREngineType {
        let type = selectedEngineType
        if canSelectEngine(type) {
            return type
        }
        AppLogger.general.warning("Effective ASR engine fallback triggered; selected=\(type.rawValue), fallback=apple")
        return .apple
    }

    var selectionFallbackNotice: SelectionFallbackNotice? {
        let selected = selectedEngineType
        let effective = effectiveSelectedEngineType
        guard selected != effective else {
            return nil
        }
        return SelectionFallbackNotice(
            selectedEngineType: selected,
            effectiveEngineType: effective
        )
    }

    func modelMetadata(for type: ASREngineType) -> (modelID: String?, modelVersion: String?) {
        switch type {
        case .apple:
            return ("apple-speech-system", nil)
        case .funASR:
            guard let key = Self.funASRModelInstallKey(for: funASRPrecision) else {
                return ("funasr-\(funASRPrecision.rawValue.lowercased())", nil)
            }
            return (key.modelID.rawValue, key.version)
        case .whisper:
            guard let key = Self.whisperModelInstallKey(for: whisperVariant) else {
                return ("whisper-\(whisperVariant.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))", nil)
            }
            return (key.modelID.rawValue, key.version)
        case .qwen3:
            guard let metadata = try? Qwen3ModelStoreMetadata.metadata(
                for: Qwen3ModelManifest.manifest(for: qwen3ModelSize)
            ) else {
                return ("qwen3-\(qwen3ModelSize.rawValue.lowercased())", nil)
            }
            return (metadata.modelID.rawValue, metadata.version)
        case .senseVoice:
            let key = Self.senseVoiceModelInstallKey()
            return (key.modelID.rawValue, key.version)
        case .paraformer:
            let key = Self.paraformerModelInstallKey()
            return (key.modelID.rawValue, key.version)
        case .nvidiaNemotron:
            let key = Self.nvidiaNemotronModelInstallKey()
            return (key.modelID.rawValue, key.version)
        case .parakeetStreaming:
            let key = Self.parakeetModelInstallKey()
            return (key.modelID.rawValue, key.version)
        case .omnilingualASR:
            let key = Self.omnilingualModelInstallKey()
            return (key.modelID.rawValue, key.version)
        case .groqWhisper:
            return (groqModel, nil)
        case .tencentCloud:
            return ("tencent-\(tencentRealtimeEngineModelType)", nil)
        case .aliyunDashScope:
            return ("aliyun-dashscope-\(aliyunDashScopeModel)", nil)
        case .volcengineDoubao:
            return ("volcengine-\(VolcengineRealtimeASRConfiguration.defaultResourceID)", nil)
        }
    }

    func canSelectEngine(_ type: ASREngineType) -> Bool {
        let available: Bool
        let reason: String?
        switch type {
        case .apple:
            available = true
            reason = nil
        case .funASR:
            available = isFunASRModelAvailable
            reason = available ? nil : "FunASR model unavailable"
        case .whisper:
            if !Self.isWhisperRuntimeSupported(variant: whisperVariant) {
                reason = Self.whisperRuntimeUnsupportedMessage(for: whisperVariant)
                available = false
            } else {
                available = isWhisperModelAvailable
                reason = available ? nil : "Whisper model unavailable"
            }
        case .qwen3:
            if !isQwen3RuntimeSupported(size: qwen3ModelSize) {
                reason = qwen3RuntimeUnsupportedMessage(for: qwen3ModelSize)
                available = false
            } else {
                available = isQwen3ModelAvailable
                reason = available ? nil : "Qwen3 model unavailable"
            }
        case .senseVoice:
            available = isSenseVoiceModelAvailable
            reason = available ? nil : "SenseVoice model unavailable"
        case .paraformer:
            available = isParaformerModelAvailable
            reason = available ? nil : "Paraformer model unavailable"
        case .nvidiaNemotron:
            if !isNVIDIANemotronRuntimeSupported {
                reason = Self.nvidiaNemotronRuntimeUnsupportedMessage()
                available = false
            } else {
                available = isNVIDIANemotronModelAvailable
                reason = available ? nil : "NVIDIA Nemotron model unavailable"
            }
        case .parakeetStreaming:
            available = isParakeetModelAvailable
            reason = available ? nil : "Parakeet model unavailable"
        case .omnilingualASR:
            available = isOmnilingualModelAvailable
            reason = available ? nil : "Omnilingual model unavailable"
        case .groqWhisper:
            available = isGroqConfigured
            reason = available ? nil : "Groq API key missing"
        case .tencentCloud:
            available = isTencentCloudConfigured
            reason = available ? nil : "Tencent credentials incomplete"
        case .aliyunDashScope:
            available = isAliyunDashScopeConfigured
            reason = available ? nil : "Aliyun DashScope key missing"
        case .volcengineDoubao:
            available = isVolcengineConfigured
            reason = available ? nil : "Volcengine credentials incomplete"
        }
        if !available, let reason {
            AppLogger.general.info("ASR engine unavailable: type=\(type.rawValue), reason=\(reason)")
        }
        return available
    }

    func isQwen3RuntimeSupported(size: ModelSize) -> Bool {
        qwen3RuntimePreflight(size).isSupported
    }

    func qwen3RuntimeUnsupportedMessage(for size: ModelSize) -> String {
        qwen3RuntimePreflight(size).reason ?? ""
    }

    @discardableResult
    func selectEngine(_ type: ASREngineType) -> Bool {
        AppLogger.general.info("Request selecting ASR engine: \(type.rawValue)")
        selectedEngineType = type
        guard canSelectEngine(type) else {
            AppLogger.general.warning("Reject ASR engine selection: \(type.rawValue)")
            return false
        }
        AppLogger.general.info("ASR engine selected: \(type.rawValue)")
        return true
    }

    func resetASRSettingsToDefaults() {
        selectedEngineType = .apple
        qwen3ModelPath = nil
        qwen3ModelSize = .size0_6B
        funASRPrecision = .int8
        whisperVariant = .turbo
        groqBaseURL = GroqCloudASRClient.defaultBaseURL
        groqModel = GroqCloudASRClient.defaultModel
        tencentRealtimeEngineModelType = TencentRealtimeASRConfiguration.defaultEngineModelType
        aliyunDashScopeModel = AliyunDashScopeRealtimeASRConfiguration.defaultModel
        aliyunDashScopeVocabularyID = ""
    }

    func deleteAllLocalModels(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        AppLogger.general.info("Delete all local models requested: targetDirectory=\(modelsDirectory.path)")
        try throwIfLocalModelOperationInProgress()

        for key in Self.allLocalModelInstallKeys() {
            if case let .ready(installation) = try modelInstallationRepository?.state(for: key) ?? .notInstalled {
                try? modelInstallationRepository?.save(.deleting(installation), for: key)
            }
        }

        if fileManager.fileExists(atPath: modelsDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: nil,
                options: []
            )
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        }
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        for key in Self.allLocalModelInstallKeys() {
            try? modelInstallationRepository?.removeState(for: key)
        }
        qwen3ModelPath = nil
        if selectedEngineType.isLocalModelProvider {
            selectedEngineType = .apple
        }
        AppLogger.general.info("Delete all local models completed")
    }

    func localModelStorageBytes(
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
            ), values.isDirectory != true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    var qwen3DownloadURL: URL {
        Self.downloadURL(for: qwen3ModelSize)
    }

    static func downloadURL(for size: ModelSize) -> URL {
        switch size {
        case .size0_6B:
            return URL(string: "https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit")!
        case .size1_7B:
            return URL(string: "https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-8bit")!
        }
    }

    // MARK: - ASREngineFactory

    func makeEngine(type: ASREngineType) -> ASREngine {
        let available = canSelectEngine(type)
        AppLogger.dictation.info(
            "Creating ASR engine instance: \(type.rawValue), selectedAvailable=\(available)"
        )
        if !available {
            AppLogger.general.warning("ASR engine not available during creation: \(type.rawValue), runtime check result: unavailable")
        }
        switch type {
        case .apple:
            AppLogger.general.debug("ASR engine branch: apple")
            return SpeechRecognizer()
        case .funASR:
            AppLogger.general.debug("ASR engine branch: funASR")
            return makeFunASRProviderBackedEngine()
        case .whisper:
            AppLogger.general.debug("ASR engine branch: whisper")
            return makeWhisperProviderBackedEngine()
        case .qwen3:
            AppLogger.general.debug("ASR engine branch: qwen3")
            return makeQwen3ProviderBackedEngine()
        case .senseVoice:
            AppLogger.general.debug("ASR engine branch: senseVoice")
            return makeSenseVoiceProviderBackedEngine()
        case .paraformer:
            AppLogger.general.debug("ASR engine branch: paraformer")
            return makeParaformerProviderBackedEngine()
        case .nvidiaNemotron:
            AppLogger.general.debug("ASR engine branch: nvidiaNemotron")
            return makeNVIDIANemotronProviderBackedEngine()
        case .parakeetStreaming:
            AppLogger.general.debug("ASR engine branch: parakeetStreaming")
            return makeParakeetProviderBackedEngine()
        case .omnilingualASR:
            AppLogger.general.debug("ASR engine branch: omnilingualASR")
            return makeOmnilingualProviderBackedEngine()
        case .groqWhisper:
            let client = GroqCloudASRClient(credentialStore: cloudCredentialStore())
            AppLogger.general.debug(
                "ASR engine branch: groqWhisper, baseURL=\(groqConfiguration.baseURL), model=\(groqModel)"
            )
            return BufferedCloudASREngine(
                client: client,
                configuration: groqConfiguration,
                configurationAvailable: { [weak self] in
                    guard let self else {
                        AppLogger.general.warning("Groq ASR config unavailable while closure executes: manager released")
                        return false
                    }
                    AppLogger.general.debug("Groq ASR config check result=\(self.isGroqConfigured)")
                    return self.isGroqConfigured
                }
            )
        case .tencentCloud:
            return TencentRealtimeASREngine { [weak self] in
                guard let self else {
                    AppLogger.general.warning("Tencent ASR config unavailable while closure executes: manager released")
                    throw TencentRealtimeASRError.missingCredential
                }
                AppLogger.general.debug(
                    "Tencent ASR config check passed=\(self.isTencentCloudConfigured), runtimeModel=\(self.tencentRealtimeEngineModelType)"
                )
                return try self.tencentCloudConfiguration()
            }
        case .aliyunDashScope:
            return AliyunDashScopeRealtimeASREngine { [weak self] in
                guard let self else {
                    AppLogger.general.warning("Aliyun DashScope ASR config unavailable while closure executes: manager released")
                    throw AliyunDashScopeRealtimeASRError.missingCredential
                }
                AppLogger.general.debug("Aliyun DashScope config check passed=\(self.isAliyunDashScopeConfigured)")
                return try self.aliyunDashScopeConfiguration()
            }
        case .volcengineDoubao:
            return VolcengineRealtimeASREngine { [weak self] in
                guard let self else {
                    AppLogger.general.warning("Volcengine ASR config unavailable while closure executes: manager released")
                    throw VolcengineRealtimeASRError.missingCredential
                }
                AppLogger.general.debug("Volcengine config check passed=\(self.isVolcengineConfigured)")
                return try self.volcengineConfiguration()
            }
        }
    }

    private func makeQwen3ProviderBackedEngine() -> ASREngine {
        let installState = qwen3ModelInstallationState(for: qwen3ModelSize)
        let providerState = Self.asrModelInstallationState(from: installState)
        let modelPath = qwen3ReadyInstallation(for: qwen3ModelSize)?.installedRoot.path
        AppLogger.general.debug("Qwen3 provider state=\(installState), modelPath=\(modelPath ?? "<nil>")")
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: providerState),
            modelURL: qwen3ReadyInstallation(for: qwen3ModelSize)?.installedRoot,
            sessionFactory: Qwen3StreamingSessionFactoryProvider.factory(
                for: Qwen3ModelVariant(size: qwen3ModelSize)
            )
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeWhisperProviderBackedEngine() -> ASREngine {
        let state: ModelInstallationState
        if Self.isWhisperRuntimeSupported(variant: whisperVariant) {
            state = whisperModelInstallationState(for: whisperVariant)
        } else {
            state = .runtimeUnsupported(reason: Self.whisperRuntimeUnsupportedMessage(for: whisperVariant))
        }
        let modelPath = whisperReadyInstallation(for: whisperVariant)?.installedRoot.path
        AppLogger.general.debug("Whisper provider state=\(state), modelPath=\(modelPath ?? "<nil>")")
        let providerState = Self.asrModelInstallationState(from: state)
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: whisperModelVariant,
                modelInstallationState: providerState
            ),
            variant: whisperModelVariant,
            modelURL: whisperReadyInstallation(for: whisperVariant)?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeFunASRProviderBackedEngine() -> ASREngine {
        let providerVariant = FunASRModelVariant(precision: funASRPrecision)
        let modelPath = funASRReadyInstallation(for: funASRPrecision)?.installedRoot.path
        AppLogger.general.debug(
            "FunASR provider precision=\(funASRPrecision.rawValue), modelPath=\(modelPath ?? "<nil>")"
        )
        let providerState = Self.asrModelInstallationState(
            from: funASRModelInstallationState(for: funASRPrecision)
        )
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: providerVariant,
                modelInstallationState: providerState
            ),
            variant: providerVariant,
            modelURL: funASRReadyInstallation(for: funASRPrecision)?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeSenseVoiceProviderBackedEngine() -> ASREngine {
        let providerState = Self.asrModelInstallationState(
            from: senseVoiceModelInstallationState()
        )
        AppLogger.general.debug(
            "SenseVoice provider state=\(providerState), modelPath=\(senseVoiceReadyInstallation()?.installedRoot.path ?? "<nil>")"
        )
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(
                modelInstallationState: providerState
            ),
            modelURL: senseVoiceReadyInstallation()?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeParaformerProviderBackedEngine() -> ASREngine {
        let providerState = Self.asrModelInstallationState(
            from: paraformerModelInstallationState()
        )
        AppLogger.general.debug(
            "Paraformer provider state=\(providerState), modelPath=\(paraformerReadyInstallation()?.installedRoot.path ?? "<nil>")"
        )
        let provider = ParaformerASRProvider(
            descriptor: ParaformerProviderDescriptor.descriptor(
                modelInstallationState: providerState
            ),
            modelURL: paraformerReadyInstallation()?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeNVIDIANemotronProviderBackedEngine() -> ASREngine {
        let state: ModelInstallationState
        if isNVIDIANemotronRuntimeSupported {
            state = nvidiaNemotronModelInstallationState()
        } else {
            state = .runtimeUnsupported(reason: Self.nvidiaNemotronRuntimeUnsupportedMessage())
        }
        AppLogger.general.debug(
            "NVIDIA Nemotron provider state=\(state), modelPath=\(nvidiaNemotronReadyInstallation()?.installedRoot.path ?? "<nil>")"
        )
        let providerState = Self.asrModelInstallationState(from: state)
        let provider = NVIDIANemotronASRProvider.live(
            descriptor: NVIDIANemotronProviderDescriptor.descriptor(
                modelInstallationState: providerState
            ),
            modelURL: nvidiaNemotronReadyInstallation()?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeParakeetProviderBackedEngine() -> ASREngine {
        let providerState = Self.asrModelInstallationState(
            from: parakeetModelInstallationState()
        )
        AppLogger.general.debug(
            "Parakeet provider state=\(providerState), modelPath=\(parakeetReadyInstallation()?.installedRoot.path ?? "<nil>")"
        )
        let provider = ParakeetASRProvider(
            descriptor: ParakeetProviderDescriptor.descriptor(
                modelInstallationState: providerState
            ),
            modelURL: parakeetReadyInstallation()?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func makeOmnilingualProviderBackedEngine() -> ASREngine {
        let providerState = Self.asrModelInstallationState(
            from: omnilingualModelInstallationState()
        )
        AppLogger.general.debug(
            "Omnilingual provider state=\(providerState), modelPath=\(omnilingualReadyInstallation()?.installedRoot.path ?? "<nil>")"
        )
        let provider = OmnilingualASRProvider(
            descriptor: OmnilingualProviderDescriptor.descriptor(
                modelInstallationState: providerState
            ),
            modelURL: omnilingualReadyInstallation()?.installedRoot
        )
        let descriptor = provider.descriptor
        return ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: descriptor.supportedLanguages[0]
        )
    }

    private func isQwen3ValidatedModelPath(_ path: String, size: ModelSize) -> Bool {
        if let key = Self.qwen3ModelInstallKey(for: size),
           let modelInstallationRepository,
           case let .ready(installation) = try? modelInstallationRepository.state(for: key),
           installation.installedRoot.path == path {
            return FileManager.default.fileExists(atPath: path)
        }

        guard defaults.string(forKey: Keys.qwen3ValidatedModelPath) == path,
              defaults.string(forKey: Keys.qwen3ValidatedModelSize) == size.rawValue else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    private func qwen3ReadyInstallation(for size: ModelSize) -> ModelInstallation? {
        guard case let .ready(installation) = qwen3ModelInstallationState(for: size),
              FileManager.default.fileExists(atPath: installation.installedRoot.path) else {
            return nil
        }
        return installation
    }

    private func discoverQwen3ReadyInstallation(
        for size: ModelSize,
        key: ModelInstallKey
    ) -> ModelInstallation? {
        guard let modelStoreRoot else {
            return nil
        }
        let manifest = Qwen3ModelManifest.manifest(for: size)
        let candidates = qwen3ModelStoreCandidates(
            root: modelStoreRoot,
            key: key,
            manifest: manifest
        )
        guard let installedRoot = candidates.first(where: { manifest.modelsExist(at: $0) }) else {
            return nil
        }
        return ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: installedRoot
        )
    }

    private func qwen3ModelStoreCandidates(
        root: URL,
        key: ModelInstallKey,
        manifest: Qwen3ModelManifest
    ) -> [URL] {
        let canonical = root
            .appendingPathComponent(key.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(key.version, isDirectory: true)
        let legacyParent = root.appendingPathComponent(manifest.localDirectoryName, isDirectory: true)
        let legacyVersion = legacyParent.appendingPathComponent(key.version, isDirectory: true)
        let legacyChildren = (
            try? FileManager.default.contentsOfDirectory(
                at: legacyParent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        ) ?? []
        return ([canonical, legacyVersion] + legacyChildren).reduce(into: []) { result, url in
            guard !result.contains(url) else { return }
            result.append(url)
        }
    }

    func whisperModelDirectoryURL(for variant: WhisperVariant) -> URL {
        let base = (try? ApplicationSupportPaths.live().modelsDirectory)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoxFlowModels")
        return WhisperKitModelVariant(variant: variant).defaultDirectoryURL(modelsDirectory: base)
    }

    func funASRModelDirectoryURL(for precision: FunASRPrecision) -> URL {
        let base = (try? ApplicationSupportPaths.live().modelsDirectory)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoxFlowModels")
        return FunASRModelVariant(precision: precision).defaultDirectoryURL(modelsDirectory: base)
    }

    func senseVoiceModelDirectoryURL() -> URL {
        SenseVoiceModel.defaultDirectoryURL()
    }

    func paraformerModelDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("paraformer-large-zh-coreml", isDirectory: true)
    }

    func nvidiaNemotronModelDirectoryURL() -> URL {
        nvidiaNemotronReadyInstallation()?.installedRoot
            ?? NVIDIANemotronModel.defaultDirectoryURL()
    }

    func parakeetModelDirectoryURL() -> URL {
        parakeetReadyInstallation()?.installedRoot
            ?? ParakeetModel.defaultDirectoryURL()
    }

    func omnilingualModelDirectoryURL() -> URL {
        omnilingualReadyInstallation()?.installedRoot
            ?? OmnilingualModel.defaultDirectoryURL()
    }

    func whisperModelInstallationState(for variant: WhisperVariant) -> ModelInstallationState {
        guard let key = Self.whisperModelInstallKey(for: variant),
              let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: key)) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            WhisperKitModelVariant(variant: variant).modelsExist(at: installation.installedRoot)
        }
    }

    func funASRModelInstallationState(for precision: FunASRPrecision) -> ModelInstallationState {
        guard let key = Self.funASRModelInstallKey(for: precision),
              let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: key)) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            FunASRModelVariant(precision: precision).modelsExist(at: installation.installedRoot)
        }
    }

    func senseVoiceModelInstallationState() -> ModelInstallationState {
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: Self.senseVoiceModelInstallKey())) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            SenseVoiceModel.modelsExist(at: installation.installedRoot)
        }
    }

    func paraformerModelInstallationState() -> ModelInstallationState {
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: Self.paraformerModelInstallKey())) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            ParaformerModel.modelsExist(at: installation.installedRoot)
        }
    }

    func nvidiaNemotronModelInstallationState() -> ModelInstallationState {
        guard isNVIDIANemotronRuntimeSupported else {
            return .runtimeUnsupported(reason: Self.nvidiaNemotronRuntimeUnsupportedMessage())
        }
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: Self.nvidiaNemotronModelInstallKey())) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            NVIDIANemotronModel.modelsExist(at: installation.installedRoot)
        }
    }

    func parakeetModelInstallationState() -> ModelInstallationState {
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: Self.parakeetModelInstallKey())) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            ParakeetModel.modelsExist(at: installation.installedRoot)
        }
    }

    func omnilingualModelInstallationState() -> ModelInstallationState {
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        let state = (try? modelInstallationRepository.state(for: Self.omnilingualModelInstallKey())) ?? .notInstalled
        return Self.validatedReadyState(state) { installation in
            OmnilingualModel.modelsExist(at: installation.installedRoot)
        }
    }

    private func whisperReadyInstallation(for variant: WhisperVariant) -> ModelInstallation? {
        guard case let .ready(installation) = whisperModelInstallationState(for: variant),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              WhisperKitModelVariant(variant: variant).modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private func funASRReadyInstallation(for precision: FunASRPrecision) -> ModelInstallation? {
        guard case let .ready(installation) = funASRModelInstallationState(for: precision),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              FunASRModelVariant(precision: precision).modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private func senseVoiceReadyInstallation() -> ModelInstallation? {
        guard case let .ready(installation) = senseVoiceModelInstallationState(),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              SenseVoiceModel.modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private func paraformerReadyInstallation() -> ModelInstallation? {
        guard case let .ready(installation) = paraformerModelInstallationState(),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              ParaformerModel.modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private func nvidiaNemotronReadyInstallation() -> ModelInstallation? {
        guard case let .ready(installation) = nvidiaNemotronModelInstallationState(),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              NVIDIANemotronModel.modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private func parakeetReadyInstallation() -> ModelInstallation? {
        guard case let .ready(installation) = parakeetModelInstallationState(),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              ParakeetModel.modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private func omnilingualReadyInstallation() -> ModelInstallation? {
        guard case let .ready(installation) = omnilingualModelInstallationState(),
              FileManager.default.fileExists(atPath: installation.installedRoot.path),
              OmnilingualModel.modelsExist(at: installation.installedRoot) else {
            return nil
        }
        return installation
    }

    private static func validatedReadyState(
        _ state: ModelInstallationState,
        modelsExist: (ModelInstallation) -> Bool
    ) -> ModelInstallationState {
        guard case let .ready(installation) = state else {
            return state
        }
        guard FileManager.default.fileExists(atPath: installation.installedRoot.path) else {
            return .notInstalled
        }
        guard modelsExist(installation) else {
            return .corrupt(reason: "模型文件不完整，请重新下载。")
        }
        return state
    }

    private func clearQwen3ValidatedModelPath() {
        if let key = Self.qwen3ModelInstallKey(for: qwen3ModelSize),
           let modelInstallationRepository {
            try? modelInstallationRepository.removeState(for: key)
        }
        defaults.removeObject(forKey: Keys.qwen3ValidatedModelPath)
        defaults.removeObject(forKey: Keys.qwen3ValidatedModelSize)
    }

    private func clearAllQwen3ModelInstallationStates() {
        if let modelInstallationRepository {
            for size in ModelSize.allCases {
                guard let key = Self.qwen3ModelInstallKey(for: size) else { continue }
                try? modelInstallationRepository.removeState(for: key)
            }
        }
        defaults.removeObject(forKey: Keys.qwen3ModelPath)
        defaults.removeObject(forKey: Keys.qwen3ValidatedModelPath)
        defaults.removeObject(forKey: Keys.qwen3ValidatedModelSize)
    }

    private static func qwen3ModelInstallKey(for size: ModelSize) -> ModelInstallKey? {
        guard let metadata = try? Qwen3ModelStoreMetadata.metadata(
            for: Qwen3ModelManifest.manifest(for: size)
        ) else {
            return nil
        }
        return ModelInstallKey(modelID: metadata.modelID, version: metadata.version)
    }

    private static func qwen3RuntimePreflightResult(for size: ModelSize) -> Qwen3RuntimePreflightResult {
        Qwen3RuntimePreflight.evaluate(variant: Qwen3ModelVariant(size: size))
    }

    private static func whisperModelInstallKey(for variant: WhisperVariant) -> ModelInstallKey? {
        let providerVariant = WhisperKitModelVariant(variant: variant)
        return ModelInstallKey(
            modelID: ModelID(rawValue: "whisper-\(providerVariant.rawValue)"),
            version: providerVariant.remoteName
        )
    }

    private static func funASRModelInstallKey(for precision: FunASRPrecision) -> ModelInstallKey? {
        let variant = FunASRModelVariant(precision: precision)
        return ModelInstallKey(
            modelID: ModelID(rawValue: "funasr-\(variant.rawValue)"),
            version: variant.directoryName
        )
    }

    private static func senseVoiceModelInstallKey() -> ModelInstallKey {
        ModelInstallKey(
            modelID: ModelID(rawValue: SenseVoiceModel.modelID),
            version: SenseVoiceModel.version
        )
    }

    private static func paraformerModelInstallKey() -> ModelInstallKey {
        ModelInstallKey(
            modelID: ModelID(rawValue: ParaformerModel.modelID),
            version: ParaformerModel.version
        )
    }

    private static func nvidiaNemotronModelInstallKey() -> ModelInstallKey {
        ModelInstallKey(
            modelID: ModelID(rawValue: NVIDIANemotronModel.modelID),
            version: NVIDIANemotronModel.version
        )
    }

    private static func parakeetModelInstallKey() -> ModelInstallKey {
        ModelInstallKey(
            modelID: ModelID(rawValue: ParakeetModel.modelID),
            version: ParakeetModel.version
        )
    }

    private static func omnilingualModelInstallKey() -> ModelInstallKey {
        ModelInstallKey(
            modelID: ModelID(rawValue: OmnilingualModel.modelID),
            version: OmnilingualModel.version
        )
    }

    private static func allLocalModelInstallKeys() -> [ModelInstallKey] {
        let variableKeys = ModelSize.allCases.compactMap(qwen3ModelInstallKey)
            + WhisperVariant.allCases.compactMap(whisperModelInstallKey)
            + FunASRPrecision.allCases.compactMap(funASRModelInstallKey)
        return variableKeys + [
            senseVoiceModelInstallKey(),
            paraformerModelInstallKey(),
            nvidiaNemotronModelInstallKey(),
            parakeetModelInstallKey(),
            omnilingualModelInstallKey(),
        ]
    }

    private func throwIfLocalModelOperationInProgress() throws {
        guard let modelInstallationRepository else { return }
        for key in Self.allLocalModelInstallKeys() {
            if try modelInstallationRepository.state(for: key).isOperationInProgress {
                AppLogger.general.warning("Local model operation in progress: \(key.modelID.rawValue)#\(key.version)")
                throw LocalModelDeletionError.modelOperationInProgress
            }
        }
    }

    private func modelInstallKey(for engineType: ASREngineType) -> ModelInstallKey? {
        switch engineType {
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope, .volcengineDoubao:
            return nil
        case .qwen3:
            return Self.qwen3ModelInstallKey(for: qwen3ModelSize)
        case .funASR:
            return Self.funASRModelInstallKey(for: funASRPrecision)
        case .whisper:
            return Self.whisperModelInstallKey(for: whisperVariant)
        case .senseVoice:
            return Self.senseVoiceModelInstallKey()
        case .paraformer:
            return Self.paraformerModelInstallKey()
        case .nvidiaNemotron:
            return Self.nvidiaNemotronModelInstallKey()
        case .parakeetStreaming:
            return Self.parakeetModelInstallKey()
        case .omnilingualASR:
            return Self.omnilingualModelInstallKey()
        }
    }

    private static func asrModelInstallationState(
        from state: ModelInstallationState
    ) -> ASRModelInstallationState {
        switch state {
        case .notInstalled, .insufficientDisk:
            return .notInstalled
        case .downloading(let progress):
            return .downloading(progress: progress.fractionCompleted ?? 0)
        case .paused(let progress):
            return .downloading(progress: progress.fractionCompleted ?? 0)
        case .verifying, .extracting, .deleting(_):
            return .verifying
        case .compiling:
            return .compiling
        case .warmingUp, .canaryTesting:
            return .prewarming
        case .ready:
            return .ready
        case .corrupt:
            return .corrupt
        case .runtimeUnsupported(let reason):
            return .runtimeUnsupported(reason: reason)
        case .hardwareUnsupported(let reason):
            return .hardwareUnsupported(reason: reason)
        case .failed(let message):
            return .failed(message: message)
        }
    }

    private static func defaultModelInstallationRepository(
        for defaults: UserDefaults
    ) -> (any ModelInstallationStateStoring)? {
        guard defaults === UserDefaults.standard,
              let paths = try? ApplicationSupportPaths.live() else {
            return nil
        }

        return FileModelInstallationStateRepository(
            fileURL: paths.modelsDirectory.appendingPathComponent(
                "installation-states.json",
                isDirectory: false
            )
        )
    }

    private static func defaultModelStoreRoot(for defaults: UserDefaults) -> URL? {
        guard defaults === UserDefaults.standard,
              let paths = try? ApplicationSupportPaths.live() else {
            return nil
        }
        return paths.modelsDirectory
    }
}

private extension ASREngineType {
    var isLocalModelProvider: Bool {
        switch self {
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope, .volcengineDoubao:
            return false
        case .funASR, .whisper, .qwen3, .senseVoice, .paraformer,
             .nvidiaNemotron, .parakeetStreaming, .omnilingualASR:
            return true
        }
    }
}

private extension ModelInstallationState {
    var isOperationInProgress: Bool {
        switch self {
        case .downloading, .paused, .verifying, .extracting, .compiling,
             .warmingUp, .canaryTesting, .deleting:
            return true
        case .notInstalled, .insufficientDisk, .ready, .corrupt,
             .runtimeUnsupported, .hardwareUnsupported, .failed:
            return false
        }
    }
}

extension WhisperKitModelVariant {
    init(variant: ASRManager.WhisperVariant) {
        switch variant {
        case .turbo:
            self = .turbo
        case .largeV3:
            self = .largeV3
        }
    }
}

extension FunASRModelVariant {
    init(precision: ASRManager.FunASRPrecision) {
        switch precision {
        case .int8:
            self = .int8
        case .fp32:
            self = .fp32
        }
    }
}
