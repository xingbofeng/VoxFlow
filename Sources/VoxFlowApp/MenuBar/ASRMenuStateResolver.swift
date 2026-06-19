import Foundation

final class ASRMenuStateResolver {
    typealias QwenAvailability = (ASRManager.ModelSize) -> Bool
    typealias FunASRAvailability = (ASRManager.FunASRPrecision) -> Bool
    typealias WhisperAvailability = (ASRManager.WhisperVariant) -> Bool

    private let asrManager: ASRManager
    private let qwenAvailableOnDisk: QwenAvailability
    private let funASRAvailable: FunASRAvailability
    private let whisperAvailable: WhisperAvailability

    init(
        asrManager: ASRManager,
        qwenAvailableOnDisk: @escaping QwenAvailability = { _ in false },
        funASRAvailable: @escaping FunASRAvailability = { _ in false },
        whisperAvailable: @escaping WhisperAvailability = { _ in false }
    ) {
        self.asrManager = asrManager
        self.qwenAvailableOnDisk = qwenAvailableOnDisk
        self.funASRAvailable = funASRAvailable
        self.whisperAvailable = whisperAvailable
    }

    convenience init(asrManager: ASRManager) {
        self.init(
            asrManager: asrManager,
            qwenAvailableOnDisk: { size in asrManager.isQwen3ModelAvailableOnDisk(for: size) },
            funASRAvailable: { precision in
                asrManager.isFunASRModelAvailable(for: precision)
            },
            whisperAvailable: { variant in
                guard ASRManager.isWhisperRuntimeSupported(variant: variant) else {
                    return false
                }
                return asrManager.isWhisperModelAvailable(for: variant)
            }
        )
    }

    func isEnabled(_ option: ASRMenuModel) -> Bool {
        if option.engineType == .qwen3, let size = option.modelSize {
            guard asrManager.isQwen3RuntimeSupported(size: size) else {
                return false
            }
            return qwenAvailableOnDisk(size)
        }
        if option.engineType == .funASR, let precision = option.funASRPrecision {
            return funASRAvailable(precision)
        }
        if option.engineType == .whisper, let variant = option.whisperVariant {
            guard ASRManager.isWhisperRuntimeSupported(variant: variant) else {
                return false
            }
            return whisperAvailable(variant)
        }
        return asrManager.canSelectEngine(option.engineType)
    }

    func isSelected(_ option: ASRMenuModel) -> Bool {
        let selectedEngineType = effectiveSelectedEngineTypeForMenu()
        if option.engineType == .qwen3, let size = option.modelSize {
            return selectedEngineType == .qwen3 && asrManager.qwen3ModelSize == size
        }
        if option.engineType == .funASR, let precision = option.funASRPrecision {
            return selectedEngineType == .funASR && asrManager.funASRPrecision == precision
        }
        if option.engineType == .whisper, let variant = option.whisperVariant {
            return selectedEngineType == .whisper && asrManager.whisperVariant == variant
        }
        return selectedEngineType == option.engineType
    }

    private func effectiveSelectedEngineTypeForMenu() -> ASREngineType {
        let selectedEngineType = asrManager.selectedEngineType
        guard isCurrentSelectionAvailableForMenu() else {
            return .apple
        }
        return selectedEngineType
    }

    private func isCurrentSelectionAvailableForMenu() -> Bool {
        switch asrManager.selectedEngineType {
        case .apple:
            return true
        case .qwen3:
            let size = asrManager.qwen3ModelSize
            return asrManager.isQwen3RuntimeSupported(size: size) && qwenAvailableOnDisk(size)
        case .funASR:
            return funASRAvailable(asrManager.funASRPrecision)
        case .whisper:
            let variant = asrManager.whisperVariant
            return ASRManager.isWhisperRuntimeSupported(variant: variant) && whisperAvailable(variant)
        case .senseVoice, .paraformer, .nvidiaNemotron, .parakeetStreaming, .omnilingualASR,
             .groqWhisper, .tencentCloud, .aliyunDashScope:
            return asrManager.canSelectEngine(asrManager.selectedEngineType)
        }
    }

    @discardableResult
    func select(_ option: ASRMenuModel) -> Bool {
        guard isEnabled(option) else { return false }
        if option.engineType == .qwen3, let size = option.modelSize {
            asrManager.qwen3ModelSize = size
        }
        if option.engineType == .funASR, let precision = option.funASRPrecision {
            asrManager.funASRPrecision = precision
        }
        if option.engineType == .whisper, let variant = option.whisperVariant {
            asrManager.whisperVariant = variant
        }
        asrManager.selectedEngineType = option.engineType
        return true
    }
}
