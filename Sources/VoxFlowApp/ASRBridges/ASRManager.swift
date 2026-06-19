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
import VoxFlowProviderWhisper

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
    private let credentialStore: any CredentialStore
    private let settingsRepository: (any SettingsRepository)?
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
    }

    static let groqAPIKeyAccount = "asr.groq.api-key"
    static let tencentAppIDAccount = "asr.tencent.app-id"
    static let tencentSecretIDAccount = "asr.tencent.secret-id"
    static let tencentSecretKeyAccount = "asr.tencent.secret-key"
    static let aliyunDashScopeAPIKeyAccount = "asr.aliyun-dashscope.api-key"

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
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        settingsRepository: (any SettingsRepository)? = nil,
        qwen3RuntimePreflight: @escaping (ModelSize) -> Qwen3RuntimePreflightResult = ASRManager.qwen3RuntimePreflightResult(for:),
        modelStoreRoot: URL? = nil
    ) {
        self.defaults = defaults
        self.modelInstallationRepository = modelInstallationRepository ?? Self.defaultModelInstallationRepository(for: defaults)
        self.credentialStore = credentialStore
        self.settingsRepository = settingsRepository
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

    var isGroqConfigured: Bool {
        let value = storedCloudCredential(account: Self.groqAPIKeyAccount)
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func storedGroqAPIKey() -> String {
        storedCloudCredential(account: Self.groqAPIKeyAccount)
    }

    func saveGroqAPIKey(_ apiKey: String) throws {
        try saveCloudCredential(apiKey, account: Self.groqAPIKeyAccount)
    }

    func testGroqConnection() async throws -> ASRProviderHealthResult {
        try await GroqCloudASRClient(credentialStore: cloudCredentialStore()).testConnection(
            configuration: groqConfiguration
        )
    }

    var isTencentCloudConfigured: Bool {
        let appID = storedCloudCredential(account: Self.tencentAppIDAccount)
        let secretID = storedCloudCredential(account: Self.tencentSecretIDAccount)
        let secretKey = storedCloudCredential(account: Self.tencentSecretKeyAccount)
        return !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func storedTencentCloudCredentials() -> (appID: String, secretID: String, secretKey: String) {
        (
            storedCloudCredential(account: Self.tencentAppIDAccount),
            storedCloudCredential(account: Self.tencentSecretIDAccount),
            storedCloudCredential(account: Self.tencentSecretKeyAccount)
        )
    }

    func saveTencentCloudCredentials(appID: String, secretID: String, secretKey: String) throws {
        try saveTencentCredential(appID, account: Self.tencentAppIDAccount)
        try saveTencentCredential(secretID, account: Self.tencentSecretIDAccount)
        try saveTencentCredential(secretKey, account: Self.tencentSecretKeyAccount)
    }

    func deleteTencentCloudCredentials() throws {
        try saveCloudCredential("", account: Self.tencentAppIDAccount)
        try saveCloudCredential("", account: Self.tencentSecretIDAccount)
        try saveCloudCredential("", account: Self.tencentSecretKeyAccount)
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
        let value = storedCloudCredential(account: Self.aliyunDashScopeAPIKeyAccount)
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func storedAliyunDashScopeAPIKey() -> String {
        storedCloudCredential(account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func saveAliyunDashScopeAPIKey(_ apiKey: String) throws {
        try saveCloudCredential(apiKey, account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func aliyunDashScopeConfiguration() throws -> AliyunDashScopeRealtimeASRConfiguration {
        let configuration = AliyunDashScopeRealtimeASRConfiguration(
            apiKey: storedAliyunDashScopeAPIKey(),
            model: aliyunDashScopeModel
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

    private func saveTencentCredential(_ value: String, account: String) throws {
        try saveCloudCredential(value, account: account)
    }

    fileprivate func saveCloudCredential(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let settingsRepository {
            let key = Self.cloudCredentialSettingsKey(account: account)
            if trimmed.isEmpty {
                try settingsRepository.deleteValue(forKey: key)
            } else {
                try settingsRepository.set(
                    key,
                    jsonValue: Self.encodedCredentialJSON(StoredCloudCredential(value: trimmed))
                )
            }
            return
        }
        if trimmed.isEmpty {
            try credentialStore.deleteCredential(account: account)
        } else {
            try credentialStore.saveCredential(trimmed, account: account)
        }
    }

    fileprivate func storedCloudCredential(account: String) -> String {
        if let settingsRepository,
           let json = try? settingsRepository.value(forKey: Self.cloudCredentialSettingsKey(account: account)),
           let data = json.data(using: .utf8),
           let credential = try? JSONDecoder().decode(StoredCloudCredential.self, from: data) {
            return credential.value
        }
        guard settingsRepository == nil else {
            return ""
        }
        return (try? credentialStore.readCredential(account: account)) ?? ""
    }

    private func cloudCredentialStore() -> any CredentialStore {
        ASRSettingsBackedCredentialStore(manager: self)
    }

    private static func cloudCredentialSettingsKey(account: String) -> String {
        "ASRManager.cloudCredential.\(account)"
    }

    private static func encodedCredentialJSON(_ credential: StoredCloudCredential) -> String {
        guard let data = try? JSONEncoder().encode(credential),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"value":""}"#
        }
        return string
    }

    private struct StoredCloudCredential: Codable {
        let value: String
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
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope:
            return
        case .qwen3:
            clearQwen3ValidatedModelPath()
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
        try? modelInstallationRepository.save(.deleting(installation), for: key)
    }

    func markModelDeletionFailed(for engineType: ASREngineType, message: String) {
        guard let key = self.modelInstallKey(for: engineType),
              let modelInstallationRepository else {
            return
        }
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
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope:
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

    var effectiveSelectedEngineType: ASREngineType {
        let type = selectedEngineType
        if canSelectEngine(type) {
            return type
        }
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
        }
    }

    func canSelectEngine(_ type: ASREngineType) -> Bool {
        switch type {
        case .apple:
            return true
        case .funASR:
            return isFunASRModelAvailable
        case .whisper:
            return Self.isWhisperRuntimeSupported(variant: whisperVariant) && isWhisperModelAvailable
        case .qwen3:
            return isQwen3RuntimeSupported(size: qwen3ModelSize) && isQwen3ModelAvailable
        case .senseVoice:
            return isSenseVoiceModelAvailable
        case .paraformer:
            return isParaformerModelAvailable
        case .nvidiaNemotron:
            return isNVIDIANemotronRuntimeSupported && isNVIDIANemotronModelAvailable
        case .parakeetStreaming:
            return isParakeetModelAvailable
        case .omnilingualASR:
            return isOmnilingualModelAvailable
        case .groqWhisper:
            return isGroqConfigured
        case .tencentCloud:
            return isTencentCloudConfigured
        case .aliyunDashScope:
            return isAliyunDashScopeConfigured
        }
    }

    func isQwen3RuntimeSupported(size: ModelSize) -> Bool {
        qwen3RuntimePreflight(size).isSupported
    }

    func qwen3RuntimeUnsupportedMessage(for size: ModelSize) -> String {
        qwen3RuntimePreflight(size).reason ?? ""
    }

    @discardableResult
    func selectEngine(_ type: ASREngineType) -> Bool {
        guard canSelectEngine(type) else {
            selectedEngineType = .apple
            return false
        }
        selectedEngineType = type
        return true
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
        switch type {
        case .apple:
            return SpeechRecognizer()
        case .funASR:
            return makeFunASRProviderBackedEngine()
        case .whisper:
            return makeWhisperProviderBackedEngine()
        case .qwen3:
            return makeQwen3ProviderBackedEngine()
        case .senseVoice:
            return makeSenseVoiceProviderBackedEngine()
        case .paraformer:
            return makeParaformerProviderBackedEngine()
        case .nvidiaNemotron:
            return makeNVIDIANemotronProviderBackedEngine()
        case .parakeetStreaming:
            return makeParakeetProviderBackedEngine()
        case .omnilingualASR:
            return makeOmnilingualProviderBackedEngine()
        case .groqWhisper:
            let client = GroqCloudASRClient(credentialStore: cloudCredentialStore())
            return BufferedCloudASREngine(
                client: client,
                configuration: groqConfiguration,
                configurationAvailable: { [weak self] in
                    self?.isGroqConfigured ?? false
                }
            )
        case .tencentCloud:
            return TencentRealtimeASREngine { [weak self] in
                guard let self else {
                    throw TencentRealtimeASRError.missingCredential
                }
                return try self.tencentCloudConfiguration()
            }
        case .aliyunDashScope:
            return AliyunDashScopeRealtimeASREngine { [weak self] in
                guard let self else {
                    throw AliyunDashScopeRealtimeASRError.missingCredential
                }
                return try self.aliyunDashScopeConfiguration()
            }
        }
    }

    private func makeQwen3ProviderBackedEngine() -> ASREngine {
        let providerState = Self.asrModelInstallationState(
            from: qwen3ModelInstallationState(for: qwen3ModelSize)
        )
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

    private func modelInstallKey(for engineType: ASREngineType) -> ModelInstallKey? {
        switch engineType {
        case .apple, .groqWhisper, .tencentCloud, .aliyunDashScope:
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

private final class ASRSettingsBackedCredentialStore: CredentialStore, @unchecked Sendable {
    private weak var manager: ASRManager?

    init(manager: ASRManager) {
        self.manager = manager
    }

    func readCredential(account: String) throws -> String? {
        manager?.storedCloudCredential(account: account)
    }

    func saveCredential(_ value: String, account: String) throws {
        try manager?.saveCloudCredential(value, account: account)
    }

    func deleteCredential(account: String) throws {
        try manager?.saveCloudCredential("", account: account)
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
