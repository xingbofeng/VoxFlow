import Foundation
import VoxFlowAudio

/// 跨平台 ASR engine 协议，macOS 与 iOS 共享。
/// 回调必须在主线程触发；实现方负责 dispatch 到主队列。
public protocol ASREngine: AnyObject {
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

/// 可选的热词/term prompt 配置能力。腾讯云实时 ASR 实现；其他 provider 可空实现。
public protocol ASRTermPromptConfiguring: AnyObject {
    func configureTermPrompt(_ prompt: String?)
}

/// ASR runtime 运行期元数据快照，跨平台共享。
public struct ASRRuntimeMetadataSnapshot: Equatable, Sendable {
    public var sessionID: String?
    public var audioDurationMs: Int?
    public var finalLatencyMs: Int?
    public var droppedFrameCount: Int?
    public var errorCode: String?

    public init() {}

    public init(
        sessionID: String?,
        audioDurationMs: Int? = nil,
        finalLatencyMs: Int? = nil,
        droppedFrameCount: Int? = nil,
        errorCode: String? = nil
    ) {
        self.sessionID = sessionID
        self.audioDurationMs = audioDurationMs
        self.finalLatencyMs = finalLatencyMs
        self.droppedFrameCount = droppedFrameCount
        self.errorCode = errorCode
    }
}

public protocol ASRRuntimeMetadataProviding: AnyObject {
    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot { get }
}

public enum ASREngineError: LocalizedError {
    case modelNotLoaded
    public var errorDescription: String? { "语音识别模型未加载。请先在设置中下载模型。" }
}
