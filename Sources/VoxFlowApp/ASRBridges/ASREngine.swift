import Foundation
import VoxFlowAudio
import VoxFlowASRRuntime

enum ASREngineType: String, CaseIterable, Equatable, Hashable {
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
    case volcengineDoubao = "Volcengine Doubao ASR"

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
        case .volcengineDoubao:
            return "火山云"
        }
    }
}

protocol ASREngineFactory {
    func makeEngine(type: ASREngineType) -> ASREngine
}
