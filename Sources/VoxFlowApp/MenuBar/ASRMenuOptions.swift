import Foundation

/// Represents one row in the flattened ASR engine menu.
@objc final class ASRMenuModel: NSObject {
    let engineType: ASREngineType
    let modelSize: ASRManager.ModelSize?
    let funASRPrecision: ASRManager.FunASRPrecision?
    let whisperVariant: ASRManager.WhisperVariant?
    let title: String

    init(
        engineType: ASREngineType,
        modelSize: ASRManager.ModelSize? = nil,
        funASRPrecision: ASRManager.FunASRPrecision? = nil,
        whisperVariant: ASRManager.WhisperVariant? = nil,
        title: String
    ) {
        self.engineType = engineType
        self.modelSize = modelSize
        self.funASRPrecision = funASRPrecision
        self.whisperVariant = whisperVariant
        self.title = title
    }
}

enum ASRMenuOptions {
    static func makeOptions() -> [ASRMenuModel] {
        [
            ASRMenuModel(engineType: .apple, title: "系统自带"),
            ASRMenuModel(engineType: .funASR, funASRPrecision: .int8, title: "FunASR Nano INT8"),
            ASRMenuModel(engineType: .funASR, funASRPrecision: .fp32, title: "FunASR Nano FP32"),
            ASRMenuModel(engineType: .whisper, whisperVariant: .turbo, title: "Whisper Turbo"),
            ASRMenuModel(engineType: .whisper, whisperVariant: .largeV3, title: "Whisper Large V3"),
            ASRMenuModel(engineType: .qwen3, modelSize: .size0_6B, title: "Qwen3-ASR 0.6B"),
            ASRMenuModel(engineType: .qwen3, modelSize: .size1_7B, title: "Qwen3-ASR 1.7B"),
            ASRMenuModel(engineType: .senseVoice, title: "SenseVoice Small"),
            ASRMenuModel(engineType: .paraformer, title: "Paraformer Large zh"),
            ASRMenuModel(engineType: .nvidiaNemotron, title: "NVIDIA Nemotron ASR 0.6B"),
        ]
    }
}
