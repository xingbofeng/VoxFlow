import Foundation
import VoxFlowASRCore
import VoxFlowAudio

final class Qwen3ASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let modelURL: URL
    private let languageHint: String?
    private let sessionFactory: any Qwen3StreamingSessionMaking
    private let timeoutPolicy: ASRTimeoutPolicy
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var runtimeDriver: Qwen3StreamingRuntimeDriver?
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var hasStartedSpeech = false
    private var isClosed = false
    private var partialStablePrefix = ""
    private var contextPrompt: String?

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        modelURL: URL,
        languageHint: String?,
        sessionFactory: any Qwen3StreamingSessionMaking,
        timeoutPolicy: ASRTimeoutPolicy = .standard
    ) {
        self.sessionID = sessionID
        self.modelURL = modelURL
        self.languageHint = languageHint
        self.sessionFactory = sessionFactory
        self.timeoutPolicy = timeoutPolicy
    }

    func start() async throws {
        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        let prompt = lock.withLock { contextPrompt }
        do {
            let driver = Qwen3StreamingRuntimeDriver(
                modelURL: modelURL,
                languageHint: languageHint,
                contextPrompt: prompt,
                sessionFactory: sessionFactory
            )
            try await driver.start()
            runtimeDriver = driver
            eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func configurePrompt(_ prompt: String?) async throws {
        let normalizedPrompt = prompt?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            contextPrompt = normalizedPrompt?.isEmpty == false ? normalizedPrompt : nil
        }
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

        guard let runtimeDriver else {
            throw Qwen3ProviderError.preparationFailed("Qwen3-ASR session has not started.")
        }

        if let update = try await runtimeDriver.accept(frame),
           !update.transcript.isEmpty {
            emitTranscript(update.transcript, isFinal: false)
        }
    }

    func finish() async throws {
        guard !isClosedForCallback else { return }
        guard let runtimeDriver else {
            throw Qwen3ProviderError.preparationFailed("Qwen3-ASR session has not started.")
        }
        do {
            if let update = try await finishRuntime(runtimeDriver) {
                if update.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emitFailure(
                        ASRError(
                            category: .emptyTranscript,
                            message: "Qwen3-ASR final result was empty."
                        )
                    )
                    throw Qwen3ASRSessionError.emptyTranscript
                }
                emitTranscript(update.transcript, isFinal: true)
            }
        } catch Qwen3ASRSessionError.finalTimeout {
            emitFailure(
                ASRError(
                    category: .finalTimeout,
                    message: "Qwen3-ASR final result timed out."
                )
            )
            throw Qwen3ASRSessionError.finalTimeout
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func cancel() async {
        let shouldEmit = close()
        await runtimeDriver?.cancel()
        guard shouldEmit else { return }

        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "Qwen3-ASR session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
    }

    private func emitTranscript(_ text: String, isFinal: Bool) {
        guard !isClosedForCallback else { return }
        let revision = nextRevision()
        if isFinal {
            guard close() else { return }
            eventStream.yield(.final(sessionID: sessionID, revision: revision, text: text))
            eventStream.yield(
                .metrics(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    metrics: metrics()
                )
            )
            eventStream.finish()
            return
        }

        let partial = nextPartialTranscript(for: text, revision: revision)
        eventStream.yield(
            .partial(
                sessionID: sessionID,
                transcript: partial
            )
        )
    }

    private func nextPartialTranscript(
        for text: String,
        revision: UInt64
    ) -> VoxFlowASRCore.PartialTranscript {
        let audioDuration = audioDuration()
        return lock.withLock {
            let stablePrefix = partialStablePrefix
            let unstableSuffix: String
            if !stablePrefix.isEmpty, text.hasPrefix(stablePrefix) {
                let suffixStart = text.index(text.startIndex, offsetBy: stablePrefix.count)
                unstableSuffix = String(text[suffixStart...])
            } else if Self.isPunctuationAwareRevision(previous: stablePrefix, next: text)
                || Self.isLikelyWholeUtteranceRevision(previous: stablePrefix, next: text) {
                partialStablePrefix = text
                return VoxFlowASRCore.PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: text,
                    revision: revision,
                    audioDuration: audioDuration
                )
            } else {
                unstableSuffix = text
            }
            partialStablePrefix = stablePrefix + unstableSuffix
            return VoxFlowASRCore.PartialTranscript(
                stablePrefix: stablePrefix,
                unstableSuffix: unstableSuffix,
                revision: revision,
                audioDuration: audioDuration
            )
        }
    }

    private static func isPunctuationAwareRevision(previous: String, next: String) -> Bool {
        guard !previous.isEmpty, !next.isEmpty else { return false }
        let normalizedPrevious = normalizedForRevisionComparison(previous)
        let normalizedNext = normalizedForRevisionComparison(next)
        guard !normalizedPrevious.isEmpty, !normalizedNext.isEmpty else { return false }
        return normalizedNext.hasPrefix(normalizedPrevious)
    }

    private static func isLikelyWholeUtteranceRevision(previous: String, next: String) -> Bool {
        let normalizedPrevious = normalizedForRevisionComparison(previous)
        let normalizedNext = normalizedForRevisionComparison(next)
        guard !normalizedPrevious.isEmpty, !normalizedNext.isEmpty else { return false }
        guard normalizedPrevious != normalizedNext else { return true }

        let previousCharacters = Array(normalizedPrevious)
        let nextCharacters = Array(normalizedNext)
        let shorterCount = min(previousCharacters.count, nextCharacters.count)
        guard shorterCount >= 4 else { return false }

        let sharedSuffixCount = zip(previousCharacters.reversed(), nextCharacters.reversed())
            .prefix { $0 == $1 }
            .count
        return sharedSuffixCount >= 3 && sharedSuffixCount * 2 >= shorterCount
    }

    private static func normalizedForRevisionComparison(_ text: String) -> String {
        text.unicodeScalars
            .filter { scalar in
                !CharacterSet.whitespacesAndNewlines.contains(scalar)
                    && !revisionIgnoredPunctuation.contains(scalar)
            }
            .map(String.init)
            .joined()
    }

    private static let revisionIgnoredPunctuation = CharacterSet(
        charactersIn: ".,!?;:，。！？；：、 "
    )

    private func finishRuntime(
        _ runtimeDriver: Qwen3StreamingRuntimeDriver
    ) async throws -> Qwen3StreamingUpdate? {
        let timeout = timeoutPolicy.timeout(for: .final(audioDuration: audioDuration()))
        let race = Qwen3FinishRace()
        let result = await withCheckedContinuation { continuation in
            Task {
                do {
                    let update = try await runtimeDriver.finish()
                    race.resume(continuation, with: .success(update))
                } catch {
                    race.resume(continuation, with: .failure(error))
                }
            }
            Task {
                do {
                    try await Task.sleep(for: timeout)
                    race.resume(continuation, with: .failure(Qwen3ASRSessionError.finalTimeout))
                } catch {
                    race.resume(continuation, with: .failure(error))
                }
            }
        }
        return try result.get()
    }

    private func emitFailure(_ error: Error) {
        emitFailure(
            VoxFlowASRCore.ASRError(
                category: .preparationFailed,
                message: error.localizedDescription
            )
        )
    }

    private func emitFailure(_ asrError: ASRError) {
        guard close() else { return }
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: asrError
            )
        )
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

    private func audioDuration() -> Duration {
        lock.withLock {
            guard sampleRate > 0 else { return .zero }
            return .milliseconds(Int64((processedSampleCount * 1_000) / UInt64(sampleRate)))
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
}

private enum Qwen3ASRSessionError: Error {
    case emptyTranscript
    case finalTimeout
}

private final class Qwen3FinishRace: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<Result<Qwen3StreamingUpdate?, Error>, Never>,
        with result: Result<Qwen3StreamingUpdate?, Error>
    ) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        continuation.resume(returning: result)
    }
}
