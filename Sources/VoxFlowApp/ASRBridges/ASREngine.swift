import Foundation
import VoxFlowAudio

enum ASREngineType: String, CaseIterable, Equatable {
    case apple = "Apple Speech"
    case funASR = "FunASR"
    case whisper = "Whisper"
    case qwen3 = "Qwen3-ASR"
    case senseVoice = "SenseVoice Small"
    case paraformer = "Paraformer"
    case nvidiaNemotron = "NVIDIA Nemotron ASR 0.6B"
    case parakeetStreaming = "Parakeet Streaming"
    case omnilingualASR = "Omnilingual ASR"
    case groqWhisper = "Groq Whisper"
    case tencentCloud = "Tencent Cloud ASR"
    case aliyunDashScope = "Aliyun DashScope ASR"

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
        case .senseVoice:
            return "SenseVoice Small"
        case .paraformer:
            return "Paraformer Large zh"
        case .nvidiaNemotron:
            return "NVIDIA Nemotron ASR 0.6B"
        case .parakeetStreaming:
            return "Parakeet Streaming"
        case .omnilingualASR:
            return "Omnilingual ASR"
        case .groqWhisper:
            return "Groq（免费）"
        case .tencentCloud:
            return "腾讯云"
        case .aliyunDashScope:
            return "阿里云"
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
    func appendAudioFrame(_ frame: AudioFrame)
    func endAudio()
    func stop()
    func cancel()
}

struct ASRRuntimeMetadataSnapshot: Equatable, Sendable {
    var sessionID: String?
    var audioDurationMs: Int?
    var finalLatencyMs: Int?
    var droppedFrameCount: Int?
    var errorCode: String?
}

protocol ASRRuntimeMetadataProviding: AnyObject {
    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot { get }
}

enum ASREngineError: LocalizedError {
    case modelNotLoaded
    var errorDescription: String? { "语音识别模型未加载。请先在设置中下载模型。" }
}

protocol ASREngineFactory {
    func makeEngine(type: ASREngineType) -> ASREngine
}
