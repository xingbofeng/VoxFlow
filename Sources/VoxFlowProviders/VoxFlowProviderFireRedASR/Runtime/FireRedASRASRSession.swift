import Foundation
import VoxFlowASRCore
import VoxFlowAudio

/// FireRedASR2-AED 会话：整段重解产出 final，滚动重解产出实时预览。
///
/// `streamingSemantics` 是 `.rollingWindowConfirmedSegments`。FireRedASR2-AED 是离线自回归模型
/// （sherpa-onnx 只在 offline recognizer 里提供 `fire_red_asr`，没有可增量推进的流式接口），
/// 因此预览只能靠重解已累积音频得到：
/// - 录音期间按「已累积音频比上次调度多出 ≥1 秒」且「同一时刻至多一个预览解码在飞」调度后台重解，
///   结果只落在 `unstableSuffix` 上作预览，`stablePrefix` 恒为空；
/// - **`finish()` 仍是权威时机**：先取消在飞的预览，再整段重解一次，`final` 不受任何预览结果影响；
/// - 超长音频在解码时按 `FireRedASRSegmenter` 分段解码后拼接。
///
/// 节流沿用 `FunASRASRSession` 的 `partialTask` / `lastPartialSampleCount` 模式；
/// `canEmitPartial` 负责挡住「已经进了 finish/cancel 才落地的迟到预览」。
final class FireRedASRASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let modelURL: URL
    private let transcriberFactory: any FireRedASRTranscriberMaking
    private let segmentationObserver: (@Sendable (FireRedASRSegmentationReport) -> Void)?
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var audioSamples: [Float] = []
    private var hasStartedSpeech = false
    private var isClosed = false
    private var transcriberTask: Task<any FireRedASRTranscribing, Error>?
    /// 在飞的预览解码。同时只允许一个：它既做节流（上一个没解完就不再排新的），
    /// 也是 `finish()` / `cancel()` 需要取消的对象。
    private var partialTask: Task<Void, Never>?
    /// 上一次调度预览时的累积采样数，用来量出「至少 1 秒新音频」。
    private var lastPartialSampleCount = 0
    /// 一旦进入 finish/cancel，迟到的预览就必须被丢弃，不能再落到 HUD 上。
    private var isFinalizing = false

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        modelURL: URL,
        transcriberFactory: any FireRedASRTranscriberMaking,
        segmentationObserver: (@Sendable (FireRedASRSegmentationReport) -> Void)? = nil
    ) {
        self.sessionID = sessionID
        self.modelURL = modelURL
        self.transcriberFactory = transcriberFactory
        self.segmentationObserver = segmentationObserver
    }

    func start() async throws {
        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        let task = makeTranscriberTask()

        // `start()` 是 async：加载 1.24 GB 权重期间 `cancel()` 可能已经关掉 session。
        // 挂载与 closed 检查必须同一把锁内完成，否则被取消的 session 会把识别器留在属性里
        // （ORT session 与 800 MB 权重不会被释放），并在 cancellation 之后补发 ready。
        let installed = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            transcriberTask = task
            return true
        }
        guard installed else {
            task.cancel()
            return
        }

        do {
            _ = try await task.value
        } catch {
            emitFailure(error)
            throw error
        }

        // 加载期间被取消：`cancel()` 已经发过 failure 并关掉事件流，这里不能再补 ready。
        guard lock.withLock({ !isClosed }) else { return }
        eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
    }

    func accept(_ frame: AudioFrame) async throws {
        let acceptance = lock.withLock { () -> (shouldEmitSpeechStarted: Bool, partialSamples: [Float]?) in
            guard !isClosed else { return (false, nil) }
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            audioSamples.append(contentsOf: frame.samples)
            let shouldEmitSpeechStarted = !hasStartedSpeech && !frame.samples.isEmpty
            if shouldEmitSpeechStarted {
                hasStartedSpeech = true
            }
            // 预览节流：至少 1 秒新音频，且上一个预览解码已经结束。
            // 解码是同步 ORT 调用，重解成本随输出 token 线性增长，所以绝不能让预览任务排队堆积。
            guard partialTask == nil,
                  audioSamples.count - lastPartialSampleCount >= max(frame.sampleRate, 1) else {
                return (shouldEmitSpeechStarted, nil)
            }
            lastPartialSampleCount = audioSamples.count
            return (shouldEmitSpeechStarted, Array(audioSamples))
        }
        guard !isClosedForCallback else { return }

        if acceptance.shouldEmitSpeechStarted {
            eventStream.yield(
                .speechStarted(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    sequenceNumber: frame.sequenceNumber
                )
            )
        }
        if let partialSamples = acceptance.partialSamples {
            schedulePartialTranscription(samples: partialSamples)
        }
    }

    func finish() async throws {
        guard !isClosedForCallback else {
            releaseTranscriber()
            return
        }
        // 先掐掉在飞的预览：一是防止它的结果在 final 之后落地，二是避免它和下面的整段重解
        // 抢同一个识别器（识别器内部用 NSLock 串行化，且同步 ORT 调用不可被打断）。
        cancelPartialTask()
        defer { releaseTranscriber() }

        let samples = lock.withLock { audioSamples }
        do {
            guard Self.containsAudibleSamples(samples) else {
                emitFailure(Self.emptyTranscriptError)
                throw FireRedASRProviderError.emptyTranscript
            }
            guard let task = lock.withLock({ transcriberTask }) else {
                throw FireRedASRProviderError.modelNotInstalled
            }
            let transcriber = try await task.value
            let text = try await Self.transcribe(
                samples: samples,
                sampleRate: lock.withLock { sampleRate },
                using: transcriber,
                observer: segmentationObserver
            )
            guard !text.isEmpty else {
                emitFailure(Self.emptyTranscriptError)
                throw FireRedASRProviderError.emptyTranscript
            }
            emitFinal(text)
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func cancel() async {
        cancelPartialTask()
        let task = lock.withLock { transcriberTask }
        task?.cancel()
        guard close() else { return }
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "FireRedASR2-AED session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    // MARK: - 解码

    /// 分段解码并保序拼接。抽成 static 是为了能在没有识别器的情况下直接测这条管线。
    static func transcribe(
        samples: [Float],
        sampleRate: Int,
        using transcriber: any FireRedASRTranscribing,
        observer: (@Sendable (FireRedASRSegmentationReport) -> Void)? = nil
    ) async throws -> String {
        let segments = FireRedASRSegmenter.segments(samples: samples, sampleRate: sampleRate)
        observer?(
            FireRedASRSegmentationReport(
                segmentCount: segments.count,
                hardCutSegmentCount: segments.filter(\.isHardCut).count,
                sampleCount: samples.count
            )
        )

        var parts: [String] = []
        for segment in segments {
            try Task.checkCancellation()
            // 先剥掉 `<sil>` / `<unk>` 这类功能性 token：整段无语音时模型返回的就是 `<sil>`，
            // 它是非空字符串，直接参与拼接会把噪声当成正文注入。剥完后为空即视为该段无语音。
            let text = FireRedASRSilenceTokens.strippingFunctionalTokens(
                try await transcriber.transcribe(audio: Array(samples[segment.range]))
            )
            if !text.isEmpty {
                parts.append(text)
            }
        }
        return FireRedASRTextJoiner.join(parts)
    }

    // MARK: - 内部

    private func makeTranscriberTask() -> Task<any FireRedASRTranscribing, Error> {
        let factory = transcriberFactory
        let modelURL = modelURL
        return Task {
            try await factory.makeTranscriber(directoryURL: modelURL)
        }
    }

    /// 释放识别器：不清空 `transcriberTask` 本身，因为 `finish()` 之后还会调用 `cancel()`，
    /// 那时必须能看出「已经释放过」而不是再取消一次。
    private func releaseTranscriber() {
        let task = lock.withLock { () -> Task<any FireRedASRTranscribing, Error>? in
            let task = transcriberTask
            transcriberTask = nil
            return task
        }
        task?.cancel()
    }

    // MARK: - 实时预览

    /// 重解已累积音频，结果只作 `unstableSuffix` 预览。
    ///
    /// 这里**不传** `segmentationObserver`：那个回调是给权威解码留痕用的，每次预览都报一遍
    /// 会把它变成噪声；超长音频仍会走分段逻辑，避免位置编码越界。
    private func schedulePartialTranscription(samples: [Float]) {
        guard Self.containsAudibleSamples(samples) else { return }
        partialTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.lock.withLock { self.partialTask = nil }
            }
            do {
                guard let task = self.lock.withLock({ self.transcriberTask }) else { return }
                let transcriber = try await task.value
                let text = try await Self.transcribe(
                    samples: samples,
                    sampleRate: self.lock.withLock { self.sampleRate },
                    using: transcriber
                )
                self.emitPartial(text)
            } catch {
                // 预览是尽力而为：这一次解不出来就丢掉，final 仍会整段重解。
            }
        }
    }

    /// 取消在飞的预览，并标记进入收尾：此后任何预览都不得再落地。
    private func cancelPartialTask() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let task = partialTask
            partialTask = nil
            isFinalizing = true
            return task
        }
        task?.cancel()
    }

    private func emitPartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 整段无语音时模型会返回 `<sil>`：它在 `transcribe` 里已被剥掉，这里再兜一次空值。
        guard !trimmed.isEmpty, canEmitPartial else { return }
        eventStream.yield(
            .partial(
                sessionID: sessionID,
                transcript: VoxFlowASRCore.PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: trimmed,
                    revision: nextRevision(),
                    audioDuration: metrics().audioDuration
                )
            )
        )
    }

    private var canEmitPartial: Bool {
        lock.withLock { !isClosed && !isFinalizing }
    }

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
    }

    private func emitFinal(_ text: String) {
        guard close() else { return }
        eventStream.yield(.final(sessionID: sessionID, revision: nextRevision(), text: text))
        eventStream.yield(.metrics(sessionID: sessionID, revision: nextRevision(), metrics: metrics()))
        eventStream.finish()
    }

    private func emitFailure(_ error: Error) {
        emitFailure(FireRedASRASRProvider.asrError(for: error))
    }

    private func emitFailure(_ asrError: VoxFlowASRCore.ASRError) {
        guard close() else { return }
        eventStream.yield(.failure(sessionID: sessionID, revision: nextRevision(), error: asrError))
        eventStream.finish()
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

    private func metrics() -> VoxFlowASRCore.ASRMetrics {
        lock.withLock {
            let duration: Duration = sampleRate > 0
                ? .milliseconds(Int64((processedSampleCount * 1_000) / UInt64(sampleRate)))
                : .zero
            return VoxFlowASRCore.ASRMetrics(
                audioDuration: duration,
                processedFrameCount: processedFrameCount,
                droppedFrameCount: 0
            )
        }
    }

    private static var emptyTranscriptError: VoxFlowASRCore.ASRError {
        VoxFlowASRCore.ASRError(
            category: .emptyTranscript,
            message: FireRedASRProviderError.emptyTranscript.localizedDescription
        )
    }

    private static func containsAudibleSamples(_ samples: [Float]) -> Bool {
        samples.contains { abs($0) > 0.0005 }
    }
}
