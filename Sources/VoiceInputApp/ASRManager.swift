import FluidAudio
import Foundation

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

    enum ParaformerLanguage: String, CaseIterable, Equatable {
        case chinese = "中文"
        case english = "English"
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let selectedEngineType = "ASRManager.selectedEngineType"
        static let qwen3ModelSize = "ASRManager.qwen3ModelSize"
        static let qwen3ModelPath = "ASRManager.qwen3ModelPath"
        static let funASRPrecision = "ASRManager.funASRPrecision"
        static let whisperVariant = "ASRManager.whisperVariant"
        static let paraformerLanguage = "ASRManager.paraformerLanguage"
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

    var paraformerLanguage: ParaformerLanguage {
        get {
            defaults.string(forKey: Keys.paraformerLanguage)
                .flatMap(ParaformerLanguage.init(rawValue:)) ?? .chinese
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.paraformerLanguage) }
    }

    var funASRModelVariant: SherpaASRModelVariant {
        funASRPrecision == .int8 ? .funASRInt8 : .funASRFP32
    }

    var whisperModelVariant: WhisperKitModelVariant {
        whisperVariant == .turbo ? .turbo : .largeV3
    }

    var paraformerModelVariant: SherpaASRModelVariant {
        paraformerLanguage == .chinese ? .paraformerChinese : .paraformerEnglish
    }

    var isFunASRModelAvailable: Bool { funASRModelVariant.modelsExist() }
    var isWhisperModelAvailable: Bool { whisperModelVariant.modelsExist() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            } else {
                defaults.removeObject(forKey: Keys.qwen3ModelPath)
            }
        }
    }

    /// Finds the path for a specific Qwen3 model size by checking:
    /// 1. The explicit `qwen3ModelPath` from UserDefaults if it matches the manifest
    /// 2. The standard default installation folder under Application Support/VoiceInput/Models/
    /// Note: This scans the file system (not just UserDefaults), so it can find models
    /// installed at the conventional location even without an explicit UserDefaults entry.
    func qwen3ModelPath(for size: ModelSize) -> String? {
        // First check the explicitly set UserDefaults path
        if let path = qwen3ModelPath, !path.isEmpty {
            let modelURL = URL(fileURLWithPath: path, isDirectory: true)
            if Qwen3ModelManifest.manifest(for: size).modelsExist(at: modelURL) {
                return path
            }
        }
        // Then check the standard default installation folder
        if let paths = try? ApplicationSupportPaths.live() {
            let rootURL = paths.modelsDirectory.appendingPathComponent(Qwen3ModelManifest.manifest(for: size).localDirectoryName, isDirectory: true)
            if Qwen3ModelManifest.manifest(for: size).modelsExist(at: rootURL) {
                return rootURL.path
            }
        }
        return nil
    }

    /// Checks availability using ONLY the explicit UserDefaults path.
    /// Used by `canSelectEngine` and the existing test infrastructure.
    var isQwen3ModelAvailable: Bool {
        guard let path = qwen3ModelPath, !path.isEmpty else {
            return false
        }
        let modelURL = URL(fileURLWithPath: path, isDirectory: true)
        return Qwen3ModelManifest.manifest(for: qwen3ModelSize).modelsExist(at: modelURL)
    }

    /// Checks if a specific Qwen3 model size is available anywhere on disk
    /// (either via UserDefaults path or default installation folder).
    /// Used by the flattened menu bar items to enable/disable size options.
    func isQwen3ModelAvailableOnDisk(for size: ModelSize) -> Bool {
        qwen3ModelPath(for: size) != nil
    }

    var isParaformerModelAvailable: Bool {
        paraformerModelVariant.modelsExist()
    }

    var isSenseVoiceModelAvailable: Bool {
        let model = FluidAudioLocalASRModel.senseVoice
        return SenseVoiceModels.modelsExist(at: model.directoryURL, precision: model.precision ?? .fp32)
    }

    var effectiveSelectedEngineType: ASREngineType {
        let type = selectedEngineType
        if canSelectEngine(type) {
            return type
        }
        return .apple
    }

    func canSelectEngine(_ type: ASREngineType) -> Bool {
        switch type {
        case .apple:
            return true
        case .funASR:
            return isFunASRModelAvailable
        case .whisper:
            return isWhisperModelAvailable
        case .qwen3:
            return isQwen3ModelAvailable
        case .paraformer:
            return isParaformerModelAvailable
        case .senseVoice:
            return isSenseVoiceModelAvailable
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
            return SherpaBatchASREngine(variant: funASRModelVariant)
        case .whisper:
            return WhisperKitBatchASREngine(variant: whisperModelVariant)
        case .qwen3:
            return Qwen3ASREngine(modelPath: qwen3ModelPath(for: qwen3ModelSize))
        case .paraformer:
            return SherpaBatchASREngine(variant: paraformerModelVariant)
        case .senseVoice:
            return FluidAudioBatchASREngine(model: .senseVoice)
        }
    }
}
