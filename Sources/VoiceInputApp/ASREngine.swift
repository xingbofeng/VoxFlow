import AVFoundation
import Foundation

enum ASREngineType: String, CaseIterable, Equatable {
    case apple = "Apple Speech"
    case funASR = "FunASR"
    case whisper = "Whisper"
    case qwen3 = "Qwen3-ASR"
    case paraformer = "Paraformer"
    case senseVoice = "SenseVoice Small"

    var displayName: String {
        switch self {
        case .apple:
            return "系统自带"
        case .funASR:
            return "FunASR"
        case .whisper:
            return "Whisper"
        case .qwen3:
            return "Qwen3-ASR"
        case .paraformer:
            return "Paraformer"
        case .senseVoice:
            return "SenseVoice Small"
        }
    }
}

protocol ASREngine: AnyObject {
    /// Must be called on the main thread. Implementations must dispatch callbacks to main queue.
    var onTranscription: ((String, Bool) -> Void)? { get set }
    /// Must be called on the main thread. Implementations must dispatch callbacks to main queue.
    var onError: ((Error) -> Void)? { get set }
    var isAvailable: Bool { get }
    func configure(locale: Locale)
    func start() throws
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func endAudio()
    func stop()
    func cancel()
}

enum ASREngineError: LocalizedError {
    case modelNotLoaded
    var errorDescription: String? { "语音识别模型未加载。请先在设置中下载模型。" }
}

protocol ASREngineFactory {
    func makeEngine(type: ASREngineType) -> ASREngine
}
