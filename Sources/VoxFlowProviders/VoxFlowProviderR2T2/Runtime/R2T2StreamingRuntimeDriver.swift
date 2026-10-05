import Foundation
import VoxFlowAudio

/// 一次 `push` 之后交给 Provider 的文本。
///
/// `committedText` 是已确认前缀（只增长、不回滚）；`pendingText` 是本步被回滚、尚未确认的尾巴，
/// 它会被下一步重新解码，只能作为实时预览。
public struct R2T2StreamingUpdate: Sendable, Equatable {
    public let committedText: String
    public let pendingText: String

    public init(committedText: String, pendingText: String) {
        self.committedText = committedText
        self.pendingText = pendingText
    }
}

/// 把音频帧喂给 R2T2 core，并区分「已确认文本」与「尚未确认的预览尾巴」。
///
/// 与 Qwen3 的 driver 不同，这里不做累积重转写：上游 `R2T2Stream` 自己维护 block 缓冲与
/// 滚动窗口，`push` 只返回本次已提交的增量。driver 因此不缓存音频，也不做前缀猜测。
public actor R2T2StreamingRuntimeDriver {
    private let modelURL: URL
    private let languageHint: String?
    private let contextPrompt: String?
    private let streamFactory: any R2T2StreamMaking
    private var stream: (any R2T2StreamingEngine)?
    private var isCancelled = false
    private var hasFinished = false
    /// 上一次交给调用方的待定尾巴：尾巴变了也要刷新预览，即使没有新的已确认文本。
    private var lastPendingText = ""

    public init(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String? = nil,
        streamFactory: any R2T2StreamMaking
    ) {
        self.modelURL = modelURL
        self.languageHint = languageHint
        self.contextPrompt = contextPrompt
        self.streamFactory = streamFactory
    }

    public func start() async throws {
        isCancelled = false
        hasFinished = false
        lastPendingText = ""
        guard stream == nil else { return }
        stream = try await streamFactory.makeStream(
            modelURL: modelURL,
            languageHint: languageHint,
            contextPrompt: contextPrompt
        )
    }

    /// 提交一帧音频。有新的已确认文本、或待定尾巴发生变化时返回当前状态，否则返回 nil。
    public func accept(_ frame: AudioFrame) throws -> R2T2StreamingUpdate? {
        guard !isCancelled, !hasFinished else { return nil }
        guard let stream else {
            throw R2T2ProviderError.preparationFailed("Confucius4-R2T2 session has not started.")
        }
        let deltas = stream.push(Array(frame.samples))
        let pending = stream.pendingText
        guard !deltas.isEmpty || pending != lastPendingText else { return nil }
        lastPendingText = pending
        return R2T2StreamingUpdate(committedText: stream.committedText, pendingText: pending)
    }

    /// 冲刷尾部音频。返回截至当前的完整已确认文本（可能为空串，由调用方判定）。
    ///
    /// final 解码会把待定尾巴一并确认，因此此后不再有待定内容。
    public func finish() throws -> String {
        guard !isCancelled, !hasFinished else { return "" }
        guard let stream else {
            throw R2T2ProviderError.preparationFailed("Confucius4-R2T2 session has not started.")
        }
        _ = stream.finish()
        hasFinished = true
        lastPendingText = ""
        return stream.committedText
    }

    public func cancel() {
        isCancelled = true
        stream?.cancel()
        // 释放本次 stream（连同其 KV cache）；模型权重由工厂缓存继续持有。
        stream = nil
    }
}
