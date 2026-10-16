import Foundation
import VoxFlowASRRuntime
import VoxFlowASRCore
import VoxFlowAudio

private final class ASRCoreBackedCallbackBox: @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
}

/// 录音期间真正进入 ASR 的音频统计。
///
/// `dictation_history.duration_ms` 是墙钟时长，证明不了音频真的到了识别器；出问题时只有
/// 「收了多少帧/多少毫秒音频、会话多久就绪、帧之间最大间隔、丢了多少帧」能把「设备没采到声音」
/// 和「音频在管线里被丢了」分开。
private struct ASRIngestStats {
    var frameCount = 0
    var audioDurationMs = 0
    var droppedFrameCount = 0
    var firstFrameDelayMs: Int?
    var maxFrameGapMs = 0
    var sessionReadyAfterMs: Int?
}

final class ASRCoreBackedASREngine: ASREngine, ASRRuntimeMetadataProviding, ASRTermPromptConfiguring, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)? {
        get { callbacks.onTranscription }
        set { callbacks.onTranscription = newValue }
    }

    var onError: ((Error) -> Void)? {
        get { callbacks.onError }
        set {
            let presentError = errorPresentation
            callbacks.onError = newValue.map { callback in
                { error in callback(presentError(error)) }
            }
        }
    }

    var isAvailable: Bool {
        provider.descriptor.modelInstallationState.isReady
    }

    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot {
        metadataLock.withLock { runtimeMetadata }
    }

    /// 待识别帧的缓冲上限。帧消费者只在会话就绪后才开始取帧，FireRedASR 这类每次录音都要重新
    /// 加载权重的 provider 会让这段等待长达数秒，所以上限按「几分钟音频」而不是「几秒」来定，
    /// 保证启动等待期间一帧都不丢，同时仍然给异常 provider 留一个内存安全阀。
    static let audioFrameBufferLimit = 4096

    private let provider: any ASRProvider
    private let defaultLanguage: ASRLanguageCapability
    private let deliversPartialTranscripts: @Sendable () -> Bool
    private let releaseIdleResources: @Sendable () async -> Void
    private let errorPresentation: @Sendable (Error) -> Error
    private let callbacks = ASRCoreBackedCallbackBox()
    private let lifecycleLock = NSLock()
    private let metadataLock = NSLock()
    private var configuredLanguage: ASRLanguageCapability?
    private var configuredTermPrompt: String?
    private var sessionTask: Task<any ASRSession, Error>?
    private var eventTask: Task<Void, Never>?
    private var frameConsumerTask: Task<Void, Never>?
    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private var isFinishing = false
    private var hasAcceptedAudioFrame = false
    private var generation: UInt64 = 0
    private var hasReportedFailure = false
    private var runtimeMetadata = ASRRuntimeMetadataSnapshot()
    private var startedAt: ContinuousClock.Instant?
    private var ingest = ASRIngestStats()
    private var lastFrameAt: ContinuousClock.Instant?

    init(
        provider: any ASRProvider,
        defaultLanguage: ASRLanguageCapability,
        deliversPartialTranscripts: @escaping @Sendable () -> Bool = { true },
        releaseIdleResources: @escaping @Sendable () async -> Void = {},
        errorPresentation: @escaping @Sendable (Error) -> Error = { $0 }
    ) {
        self.provider = provider
        self.defaultLanguage = defaultLanguage
        self.deliversPartialTranscripts = deliversPartialTranscripts
        self.releaseIdleResources = releaseIdleResources
        self.errorPresentation = errorPresentation
    }

    func configure(locale: Locale) {
        let language = ASRLanguageCapability(
            bcp47Tag: locale.identifier.replacingOccurrences(of: "_", with: "-")
        )
        lifecycleLock.withLock {
            configuredLanguage = language
        }
    }

    func configureTermPrompt(_ prompt: String?) {
        lifecycleLock.withLock {
            configuredTermPrompt = prompt
        }
    }

    func start() throws {
        AppLogger.audio.debug(
            "ASRCoreBackedASREngine start requested available=\(isAvailable) configuredLanguage=\(configuredLanguage?.bcp47Tag ?? defaultLanguage.bcp47Tag)"
        )
        guard isAvailable else {
            AppLogger.audio.warning("ASRCoreBackedASREngine start blocked model not loaded")
            throw ASREngineError.modelNotLoaded
        }

        let provider = provider
        let configuration = lifecycleLock.withLock {
            (configuredLanguage ?? defaultLanguage, configuredTermPrompt)
        }
        let language = configuration.0
        let prompt = configuration.1
        metadataLock.withLock {
            runtimeMetadata = ASRRuntimeMetadataSnapshot()
            ingest = ASRIngestStats()
            lastFrameAt = nil
        }
        let generation = lifecycleLock.withLock {
            self.generation &+= 1
            hasReportedFailure = false
            isFinishing = false
            hasAcceptedAudioFrame = false
            startedAt = ContinuousClock.now
            return self.generation
        }
        AppLogger.audio.debug("ASRCoreBackedASREngine start generation=\(generation)")
        var frameContinuation: AsyncStream<AudioFrame>.Continuation?
        // 缓冲上限必须远大于会话就绪等待期间的帧量，否则最旧的帧会被静默丢掉，
        // 直接吃掉用户开头说的话。见 `audioFrameBufferLimit`。
        let frameStream = AsyncStream<AudioFrame>(
            bufferingPolicy: .bufferingNewest(Self.audioFrameBufferLimit)
        ) { continuation in
            frameContinuation = continuation
        }
        let requestedAt = ContinuousClock.now
        let sessionTask = Task<any ASRSession, Error> {
            let session = try await provider.makeSession(language: language)
            try await session.configurePrompt(prompt)
            try await session.start()
            return session
        }
        lifecycleLock.withLock {
            self.sessionTask = sessionTask
            self.frameContinuation = frameContinuation
        }
        let frameConsumerTask = Task {
            do {
                let session = try await sessionTask.value
                let readyAt = ContinuousClock.now
                self.metadataLock.withLock {
                    self.ingest.sessionReadyAfterMs = Self.milliseconds(from: requestedAt.duration(to: readyAt))
                }
                AppLogger.audio.notice(
                    "ASR session ready generation=\(generation) afterMs=\(Self.milliseconds(from: requestedAt.duration(to: readyAt)))"
                )
                for await frame in frameStream {
                    guard self.isCurrentGeneration(generation) else { break }
                    try await session.accept(frame)
                }
            } catch is CancellationError {
            } catch {
                AppLogger.audio.warning(
                    "ASRCoreBackedASREngine frame consumer failed generation=\(generation) reason=\(error.localizedDescription)"
                )
                guard self.isCurrentGeneration(generation) else { return }
                await self.reportFailure(error, expectedGeneration: generation)
            }
        }
        let eventTask = Task {
            do {
                let session = try await sessionTask.value
                for await event in session.events {
                    guard self.isCurrentGeneration(generation) else { break }
                    self.record(event)
                    await self.deliver(event, expectedGeneration: generation)
                }
            } catch is CancellationError {
            } catch {
                AppLogger.audio.warning(
                    "ASRCoreBackedASREngine event loop failed generation=\(generation) reason=\(error.localizedDescription)"
                )
                guard self.isCurrentGeneration(generation) else { return }
                await self.reportFailure(error, expectedGeneration: generation)
            }
        }
        lifecycleLock.withLock {
            if self.generation == generation {
                self.frameConsumerTask = frameConsumerTask
                self.eventTask = eventTask
            } else {
                frameConsumerTask.cancel()
                eventTask.cancel()
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        let continuation = lifecycleLock.withLock {
            guard sessionTask != nil, !isFinishing, let frameContinuation else {
                AppLogger.audio.warning("ASRCoreBackedASREngine appendAudioFrame skipped (not recording)")
                return Optional<AsyncStream<AudioFrame>.Continuation>.none
            }
            if !frame.samples.isEmpty {
                hasAcceptedAudioFrame = true
            }
            return frameContinuation
        }
        guard let continuation else { return }
        let yieldResult = continuation.yield(frame)
        recordIngest(frame, at: .now)
        switch yieldResult {
        case .dropped:
            recordDroppedFrame()
        case .enqueued, .terminated:
            break
        @unknown default:
            break
        }
    }

    func endAudio() {
        let snapshot = lifecycleLock.withLock {
            guard let sessionTask else {
                AppLogger.audio.warning("ASRCoreBackedASREngine endAudio skipped (no active session)")
                return Optional<(
                    sessionTask: Task<any ASRSession, Error>,
                    eventTask: Task<Void, Never>?,
                    frameConsumerTask: Task<Void, Never>?,
                    frameContinuation: AsyncStream<AudioFrame>.Continuation?,
                    generation: UInt64,
                    hasAcceptedAudioFrame: Bool
                )>.none
            }
            isFinishing = true
            let snapshot = (
                sessionTask: sessionTask,
                eventTask: eventTask,
                frameConsumerTask: frameConsumerTask,
                frameContinuation: frameContinuation,
                generation: generation,
                hasAcceptedAudioFrame: hasAcceptedAudioFrame
            )
            frameContinuation = nil
            return snapshot
        }
        guard let snapshot else { return }
        let callbacks = callbacks
        logIngestSummary(generation: snapshot.generation)
        snapshot.frameContinuation?.finish()
        guard snapshot.hasAcceptedAudioFrame else {
            AppLogger.audio.warning(
                "ASRCoreBackedASREngine endAudio with no accepted frames generation=\(snapshot.generation)"
            )
            snapshot.frameConsumerTask?.cancel()
            snapshot.eventTask?.cancel()
            callbacks.onTranscription?("", true)
            let releaseIdleResources = releaseIdleResources
            Task {
                if let session = try? await snapshot.sessionTask.value {
                    await session.cancel()
                }
                await releaseIdleResources()
            }
            return
        }
        Task {
            do {
                await snapshot.frameConsumerTask?.value
                guard self.isCurrentGeneration(snapshot.generation) else { return }
                AppLogger.audio.debug("ASRCoreBackedASREngine finishing with frames generation=\(snapshot.generation)")
                let session = try await snapshot.sessionTask.value
                try await session.finish()
            } catch is CancellationError {
            } catch {
                AppLogger.audio.warning(
                    "ASRCoreBackedASREngine endAudio failed generation=\(snapshot.generation) reason=\(error.localizedDescription)"
                )
                guard self.isCurrentGeneration(snapshot.generation) else { return }
                await self.reportFailure(error, expectedGeneration: snapshot.generation)
            }
        }
    }

    func stop() {
        let snapshot = lifecycleLock.withLock {
            AppLogger.audio.debug("ASRCoreBackedASREngine stop generation=\(generation)")
            generation &+= 1
            isFinishing = true
            let snapshot = (
                frameContinuation: frameContinuation,
                frameConsumerTask: frameConsumerTask,
                eventTask: eventTask,
                sessionTask: sessionTask
            )
            frameContinuation = nil
            frameConsumerTask = nil
            eventTask = nil
            sessionTask = nil
            hasAcceptedAudioFrame = false
            startedAt = nil
            return snapshot
        }
        snapshot.frameContinuation?.finish()
        snapshot.frameConsumerTask?.cancel()
        snapshot.eventTask?.cancel()
        snapshot.sessionTask?.cancel()
        let releaseIdleResources = releaseIdleResources
        Task {
            if let session = try? await snapshot.sessionTask?.value {
                await session.cancel()
            }
            await releaseIdleResources()
        }
    }

    func cancel() {
        let snapshot = lifecycleLock.withLock {
            AppLogger.audio.debug("ASRCoreBackedASREngine cancel generation=\(generation)")
            generation &+= 1
            let snapshot = (
                frameContinuation: frameContinuation,
                frameConsumerTask: frameConsumerTask,
                eventTask: eventTask,
                sessionTask: sessionTask
            )
            frameConsumerTask = nil
            frameContinuation = nil
            eventTask = nil
            sessionTask = nil
            isFinishing = false
            hasAcceptedAudioFrame = false
            startedAt = nil
            return snapshot
        }
        snapshot.frameContinuation?.finish()
        snapshot.frameConsumerTask?.cancel()
        snapshot.eventTask?.cancel()
        snapshot.sessionTask?.cancel()
        let releaseIdleResources = releaseIdleResources
        Task {
            if let session = try? await snapshot.sessionTask?.value {
                await session.cancel()
            }
            await releaseIdleResources()
        }
    }

    private func record(_ event: ASREvent) {
        let finalLatencyMs: Int?
        let startedAt = lifecycleLock.withLock { self.startedAt }
        if case .final = event, let startedAt {
            finalLatencyMs = Self.milliseconds(from: startedAt.duration(to: ContinuousClock.now))
        } else {
            finalLatencyMs = nil
        }

        metadataLock.withLock {
            runtimeMetadata.sessionID = event.sessionID.rawValue

            switch event {
            case .partial(_, let transcript):
                runtimeMetadata.audioDurationMs = Self.milliseconds(from: transcript.audioDuration)
            case .metrics(_, _, let metrics):
                runtimeMetadata.audioDurationMs = Self.milliseconds(from: metrics.audioDuration)
                runtimeMetadata.droppedFrameCount = Int(clamping: metrics.droppedFrameCount)
            case .failure(_, _, let error):
                runtimeMetadata.errorCode = error.category.rawValue
            case .final:
                runtimeMetadata.finalLatencyMs = finalLatencyMs
            case .preparing, .ready, .speechStarted, .endpoint:
                break
            }
        }
    }

    private func recordDroppedFrame() {
        let total = metadataLock.withLock { () -> Int in
            ingest.droppedFrameCount += 1
            runtimeMetadata.droppedFrameCount = (runtimeMetadata.droppedFrameCount ?? 0) + 1
            return ingest.droppedFrameCount
        }
        // 丢帧意味着用户说的话永远进不了转写。正常路径下这里一次都不该触发。
        if total == 1 || total % 50 == 0 {
            AppLogger.audio.warning("ASR audio frame dropped (pipeline lagging) droppedFrames=\(total)")
        }
    }

    /// 记录一帧真正交给 ASR 的音频。`maxFrameGapMs` 是相邻两帧进入管线的时间间隔：采集侧断流
    /// （切换输入设备、设备失效）会在这里留下几十毫秒以上的台阶，而墙钟时长看不出来。
    private func recordIngest(_ frame: AudioFrame, at now: ContinuousClock.Instant) {
        let startedAt = lifecycleLock.withLock { self.startedAt }
        metadataLock.withLock {
            if let lastFrameAt {
                ingest.maxFrameGapMs = max(
                    ingest.maxFrameGapMs,
                    Self.milliseconds(from: lastFrameAt.duration(to: now))
                )
            } else if let startedAt {
                ingest.firstFrameDelayMs = Self.milliseconds(from: startedAt.duration(to: now))
            }
            lastFrameAt = now
            ingest.frameCount += 1
            if frame.sampleRate > 0 {
                ingest.audioDurationMs += frame.samples.count * 1_000 / frame.sampleRate
            }
        }
    }

    private func logIngestSummary(generation: UInt64) {
        let stats = metadataLock.withLock { ingest }
        let wallClockMs = lifecycleLock.withLock {
            startedAt.map { Self.milliseconds(from: $0.duration(to: .now)) }
        }
        AppLogger.audio.notice(
            "ASR audio ingest generation=\(generation) wallClockMs=\(wallClockMs.map(String.init) ?? "n/a") "
                + "frames=\(stats.frameCount) audioMs=\(stats.audioDurationMs) "
                + "droppedFrames=\(stats.droppedFrameCount) "
                + "firstFrameDelayMs=\(stats.firstFrameDelayMs.map(String.init) ?? "n/a") "
                + "maxFrameGapMs=\(stats.maxFrameGapMs) "
                + "sessionReadyMs=\(stats.sessionReadyAfterMs.map(String.init) ?? "n/a")"
        )
    }

    private func isCurrentGeneration(_ expectedGeneration: UInt64) -> Bool {
        lifecycleLock.withLock {
            generation == expectedGeneration && sessionTask != nil
        }
    }

    private static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: milliseconds)
    }

    @MainActor
    private func deliver(_ event: ASREvent, expectedGeneration: UInt64) {
        guard isCurrentGeneration(expectedGeneration) else { return }
        switch event {
        case .partial(_, let transcript):
            guard deliversPartialTranscripts() else { return }
            let text = transcript.stablePrefix + transcript.unstableSuffix
            guard !text.isEmpty else { return }
            callbacks.onTranscription?(text, false)
        case .final(_, _, let text):
            callbacks.onTranscription?(text, true)
        case .failure(_, _, let error):
            reportFailure(ASRCoreBackedASREngineError.failure(error), expectedGeneration: expectedGeneration)
        case .preparing, .ready, .speechStarted, .endpoint, .metrics:
            break
        }
    }

    @MainActor
    private func reportFailure(_ error: Error, expectedGeneration: UInt64) {
        let shouldReport = lifecycleLock.withLock {
            guard generation == expectedGeneration, sessionTask != nil, !hasReportedFailure else { return false }
            hasReportedFailure = true
            return true
        }
        if shouldReport { callbacks.onError?(error) }
    }
}

enum ASRCoreBackedASREngineError: Error, LocalizedError {
    case failure(ASRError)

    var errorDescription: String? {
        switch self {
        case .failure(let error):
            return ASRErrorUserMessage.message(for: error)
        }
    }
}
