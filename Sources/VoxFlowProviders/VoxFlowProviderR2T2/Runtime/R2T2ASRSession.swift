import Foundation
import VoxFlowASRCore
import VoxFlowAudio

/// R2T2 稳定前缀会话。
///
/// 契约：`stablePrefix` 只包含 R2T2 已确认的文本，永不回滚；上游 `R2T2Stream` 每一步会回滚
/// `unfixedTokens` 个 token 留到下一步重解码，那段尾巴走 `unstableSuffix` 作为**实时预览**交给
/// HUD。它会被后续步骤改写，也可能为空，因此调用方不能用它做插入决策——插入只取 `final` 文本。
///
/// 之所以要暴露它：尾巴不出 driver 时 HUD 恒定落后一个 token，中文口述表现为「最后一个字不显示、
/// 也不实时更新」（词表里 `今天` `我们` 这类双字词本身是单个 token，所以有时是两个字的滞后）。
final class R2T2ASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let modelURL: URL
    private let languageHint: String?
    private let streamFactory: any R2T2StreamMaking
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var runtimeDriver: R2T2StreamingRuntimeDriver?
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var hasStartedSpeech = false
    private var isClosed = false
    private var contextPrompt: String?

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        modelURL: URL,
        languageHint: String?,
        streamFactory: any R2T2StreamMaking
    ) {
        self.sessionID = sessionID
        self.modelURL = modelURL
        self.languageHint = languageHint
        self.streamFactory = streamFactory
    }

    func configurePrompt(_ prompt: String?) async throws {
        let normalized = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            contextPrompt = normalized?.isEmpty == false ? normalized : nil
        }
    }

    func start() async throws {
        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        let prompt = lock.withLock { contextPrompt }
        let driver = R2T2StreamingRuntimeDriver(
            modelURL: modelURL,
            languageHint: languageHint,
            contextPrompt: prompt,
            streamFactory: streamFactory
        )
        do {
            try await driver.start()
        } catch {
            emitFailure(error)
            throw error
        }
        // `start()` 是 async：模型加载期间 `cancel()` 可能已经关掉 session。挂载与 closed 检查
        // 必须同一把锁内完成，否则被取消的 session 会把 driver 留在属性里（KV cache 泄漏）并在
        // cancellation 之后补发 ready。
        let installed = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            runtimeDriver = driver
            return true
        }
        guard installed else {
            await driver.cancel()
            return
        }
        eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
    }

    func accept(_ frame: AudioFrame) async throws {
        let shouldEmitSpeechStarted = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            guard !hasStartedSpeech else { return false }
            hasStartedSpeech = true
            return true
        }
        guard !isClosedForCallback else { return }

        if shouldEmitSpeechStarted {
            eventStream.yield(
                .speechStarted(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    sequenceNumber: frame.sequenceNumber
                )
            )
        }

        guard let driver = currentDriver() else {
            throw R2T2ProviderError.preparationFailed("Confucius4-R2T2 session has not started.")
        }
        let update = try await driver.accept(frame)
        guard let update, !isClosedForCallback else { return }
        emitPartial(committed: update.committedText, pending: update.pendingText)
    }

    func finish() async throws {
        guard !isClosedForCallback else {
            await releaseDriver()
            return
        }
        guard let driver = currentDriver() else {
            throw R2T2ProviderError.preparationFailed("Confucius4-R2T2 session has not started.")
        }
        do {
            let text = try await driver.finish()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                emitFailure(
                    VoxFlowASRCore.ASRError(
                        category: .emptyTranscript,
                        message: "Confucius4-R2T2 final result was empty."
                    )
                )
                throw R2T2ASRSessionError.emptyTranscript
            }
            emitFinal(text)
        } catch {
            emitFailure(error)
            await releaseDriver()
            throw error
        }
        await releaseDriver()
    }

    func cancel() async {
        // 先关闭再释放：`start()` 的在途挂载靠 `isClosed` 判定放弃，不会与这里抢 driver。
        // 即使 session 已经被 final/失败关闭，也要释放 driver —— 上游 `R2T2Stream` 的取消
        // 语义就是释放它（连同 KV cache），漏掉这一步会让 2.4 GB 权重的会话状态留在内存里。
        let shouldEmit = close()
        await releaseDriver()
        guard shouldEmit else { return }
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "Confucius4-R2T2 session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    /// 取走并释放当前 driver。取与清空在同一把锁内，避免与 `start()` 的挂载互相覆盖。
    private func releaseDriver() async {
        let driver = lock.withLock { () -> R2T2StreamingRuntimeDriver? in
            let driver = runtimeDriver
            runtimeDriver = nil
            return driver
        }
        await driver?.cancel()
    }

    private func currentDriver() -> R2T2StreamingRuntimeDriver? {
        lock.withLock { runtimeDriver }
    }

    // MARK: - Emissions

    private func emitPartial(committed: String, pending: String) {
        eventStream.yield(
            .partial(
                sessionID: sessionID,
                transcript: VoxFlowASRCore.PartialTranscript(
                    stablePrefix: committed,
                    unstableSuffix: pending,
                    revision: nextRevision(),
                    audioDuration: audioDuration()
                )
            )
        )
    }

    private func emitFinal(_ text: String) {
        guard close() else { return }
        eventStream.yield(.final(sessionID: sessionID, revision: nextRevision(), text: text))
        eventStream.yield(
            .metrics(sessionID: sessionID, revision: nextRevision(), metrics: metrics())
        )
        eventStream.finish()
    }

    private func emitFailure(_ error: Error) {
        emitFailure(
            (error as? R2T2ProviderError)?.asrError
                ?? VoxFlowASRCore.ASRError(
                    category: .preparationFailed,
                    message: error.localizedDescription
                )
        )
    }

    private func emitFailure(_ asrError: VoxFlowASRCore.ASRError) {
        guard close() else { return }
        eventStream.yield(
            .failure(sessionID: sessionID, revision: nextRevision(), error: asrError)
        )
        eventStream.finish()
    }

    // MARK: - State

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
    }

    private func close() -> Bool {
        lock.withLock {
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
    }

    private func nextRevision() -> UInt64 {
        lock.withLock {
            currentRevision += 1
            return currentRevision
        }
    }

    private func audioDuration() -> Duration {
        lock.withLock {
            guard sampleRate > 0 else { return .zero }
            return .milliseconds(Int64((processedSampleCount * 1_000) / UInt64(sampleRate)))
        }
    }

    private func metrics() -> VoxFlowASRCore.ASRMetrics {
        VoxFlowASRCore.ASRMetrics(
            audioDuration: audioDuration(),
            processedFrameCount: lock.withLock { processedFrameCount },
            droppedFrameCount: 0
        )
    }
}

enum R2T2ASRSessionError: Error {
    case emptyTranscript
}
