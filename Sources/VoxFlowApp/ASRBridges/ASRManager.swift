import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
import VoxFlowProviderFunASR
import VoxFlowProviderNVIDIA
import VoxFlowProviderParaformer
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderWhisper

final class ASRManager: ASREngineFactory, @unchecked Sendable {
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

    private enum Keys {
        static let selectedEngineType = "ASRManager.selectedEngineType"
        static let qwen3ModelSize = "ASRManager.qwen3ModelSize"
        static let qwen3ModelPath = "ASRManager.qwen3ModelPath"
        static let qwen3ValidatedModelPath = "ASRManager.qwen3ValidatedModelPath"
        static let qwen3ValidatedModelSize = "ASRManager.qwen3ValidatedModelSize"
        static let funASRPrecision = "ASRManager.funASRPrecision"
        static let whisperVariant = "ASRManager.whisperVariant"
    }

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
        modelInstallationRepository: (any ModelInstallationStateStoring)? = nil
    ) {
        self.defaults = defaults
        self.modelInstallationRepository = modelInstallationRepository ?? Self.defaultModelInstallationRepository(for: defaults)
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
        return (try? modelInstallationRepository.state(for: key)) ?? .notInstalled
    }

    func qwen3ModelInstallationState(for size: ModelSize) -> ModelInstallationState {
        let preflight = Self.qwen3RuntimePreflightResult(for: size)
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
            return Self.isQwen3RuntimeSupported(size: qwen3ModelSize) && isQwen3ModelAvailable
        case .senseVoice:
            return isSenseVoiceModelAvailable
        case .paraformer:
            return isParaformerModelAvailable
        case .nvidiaNemotron:
            return isNVIDIANemotronRuntimeSupported && isNVIDIANemotronModelAvailable
        }
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
            return URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B")!
        case .size1_7B:
            return URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-1.7B")!
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
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML", isDirectory: true)
            .appendingPathComponent("multilingual", isDirectory: true)
            .appendingPathComponent("1120ms", isDirectory: true)
    }

    func whisperModelInstallationState(for variant: WhisperVariant) -> ModelInstallationState {
        guard let key = Self.whisperModelInstallKey(for: variant),
              let modelInstallationRepository else {
            return .notInstalled
        }
        return (try? modelInstallationRepository.state(for: key)) ?? .notInstalled
    }

    func funASRModelInstallationState(for precision: FunASRPrecision) -> ModelInstallationState {
        guard let key = Self.funASRModelInstallKey(for: precision),
              let modelInstallationRepository else {
            return .notInstalled
        }
        return (try? modelInstallationRepository.state(for: key)) ?? .notInstalled
    }

    func senseVoiceModelInstallationState() -> ModelInstallationState {
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        return (try? modelInstallationRepository.state(for: Self.senseVoiceModelInstallKey())) ?? .notInstalled
    }

    func paraformerModelInstallationState() -> ModelInstallationState {
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        return (try? modelInstallationRepository.state(for: Self.paraformerModelInstallKey())) ?? .notInstalled
    }

    func nvidiaNemotronModelInstallationState() -> ModelInstallationState {
        guard isNVIDIANemotronRuntimeSupported else {
            return .runtimeUnsupported(reason: Self.nvidiaNemotronRuntimeUnsupportedMessage())
        }
        guard let modelInstallationRepository else {
            return .notInstalled
        }
        return (try? modelInstallationRepository.state(for: Self.nvidiaNemotronModelInstallKey())) ?? .notInstalled
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
        case .verifying, .extracting:
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
