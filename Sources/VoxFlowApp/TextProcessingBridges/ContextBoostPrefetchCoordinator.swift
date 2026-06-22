import Foundation
import VoxFlowContextBoost

enum ContextBoostOCRQuality: Sendable {
    case accurate
    case fast
}

enum ContextBoostOCRRecognitionOutcome: Sendable {
    case captured(OCRContextSnapshot)
    case noContext
    case cancelled
}

protocol ContextBoostOCRCaptureSession: AnyObject, Sendable {
    func recognize(quality: ContextBoostOCRQuality) async -> ContextBoostOCRRecognitionOutcome
    func cancelCurrentRecognition()
}

protocol ContextBoostOCRCaptureSessionProviding: Sendable {
    func makeCaptureSession(for target: DictationTarget) -> (any ContextBoostOCRCaptureSession)?
}

@MainActor
final class ContextBoostPrefetchCoordinator {
    private static let logger = AppLogger.dictation

    private struct ActiveCapture {
        let generation: UInt64
        let session: any ContextBoostOCRCaptureSession
        let accurateTask: Task<ContextBoostOCRRecognitionOutcome, Never>
        let accurateResult: ContextBoostOCRResultBox
    }

    private let sessionProvider: any ContextBoostOCRCaptureSessionProviding
    private var generation: UInt64 = 0
    private var activeCapture: ActiveCapture?

    init(sessionProvider: any ContextBoostOCRCaptureSessionProviding) {
        self.sessionProvider = sessionProvider
    }

    func start(target: DictationTarget?) {
        cancel()
        generation &+= 1
        let generation = self.generation
        Self.logger.debug(
            "ContextBoostPrefetchCoordinator start requested targetBundle=\(target?.bundleID ?? "-") generation=\(generation)"
        )
        guard let target,
              let session = sessionProvider.makeCaptureSession(for: target) else {
            Self.logger.debug("ContextBoostPrefetchCoordinator start skipped: no target or session unavailable")
            return
        }
        let currentGeneration = generation
        let resultBox = ContextBoostOCRResultBox()
        let task = Task {
            let result = await session.recognize(quality: .accurate)
            resultBox.store(result)
            return result
        }
        activeCapture = ActiveCapture(
            generation: currentGeneration,
            session: session,
            accurateTask: task,
            accurateResult: resultBox
        )
    }

    func resolve(
        postReleaseTimeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> ContextBoostCaptureOutcome? {
        guard let activeCapture else {
            Self.logger.debug("ContextBoostPrefetchCoordinator resolve skipped: no active capture")
            return nil
        }
        self.activeCapture = nil
        let currentGeneration = activeCapture.generation
        Self.logger.debug("ContextBoostPrefetchCoordinator resolve start generation=\(currentGeneration)")
        let startedAt = ContinuousClock.now

        if let completed = activeCapture.accurateResult.value {
            Self.logger.debug(
                "ContextBoostPrefetchCoordinator resolve hit in-memory for generation=\(currentGeneration)"
            )
            return captureOutcome(from: completed)
        }
        await Task.yield()
        if let completed = activeCapture.accurateResult.value {
            Self.logger.debug(
                "ContextBoostPrefetchCoordinator resolve hit after yield for generation=\(currentGeneration)"
            )
            return captureOutcome(from: completed)
        }

        activeCapture.session.cancelCurrentRecognition()
        activeCapture.accurateTask.cancel()
        let accurateOutcome = await activeCapture.accurateTask.value
        guard activeCapture.generation == generation else { return nil }

        switch accurateOutcome {
        case .captured(let snapshot):
            return .captured(snapshot)
        case .noContext:
            return .unavailable("no_ocr_context")
        case .cancelled:
            break
        }

        let elapsed = nanoseconds(in: startedAt.duration(to: ContinuousClock.now))
        Self.logger.debug(
            "ContextBoostPrefetchCoordinator resolve elapsedBeforeFallbackNs=\(elapsed) generation=\(currentGeneration)"
        )
        guard elapsed < postReleaseTimeoutNanoseconds else {
            Self.logger.debug(
                "ContextBoostPrefetchCoordinator resolve timeout before fallback generation=\(currentGeneration)"
            )
            return .unavailable("context_boost_timeout")
        }
        let remaining = postReleaseTimeoutNanoseconds - elapsed

        return await withTaskGroup(of: ContextBoostCaptureOutcome.self) { group in
            group.addTask {
                switch await activeCapture.session.recognize(quality: .fast) {
                case .captured(let snapshot):
                    return .captured(snapshot)
                case .noContext, .cancelled:
                    return .unavailable("no_ocr_context")
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: remaining)
                return .unavailable("context_boost_timeout")
            }

            let result = await group.next() ?? .unavailable("context_boost_timeout")
            Self.logger.debug("ContextBoostPrefetchCoordinator resolve outcome=\(result) generation=\(currentGeneration)")
            if case .unavailable("context_boost_timeout") = result {
                activeCapture.session.cancelCurrentRecognition()
            }
            group.cancelAll()
            return result
        }
    }

    func cancel() {
        generation &+= 1
        guard let activeCapture else {
            Self.logger.debug("ContextBoostPrefetchCoordinator cancel skipped: no active capture")
            return
        }
        Self.logger.debug(
            "ContextBoostPrefetchCoordinator cancel generation=\(activeCapture.generation)"
        )
        activeCapture.session.cancelCurrentRecognition()
        activeCapture.accurateTask.cancel()
        self.activeCapture = nil
    }

    private func nanoseconds(in duration: Duration) -> UInt64 {
        let components = duration.components
        guard components.seconds >= 0 else { return 0 }
        let seconds = UInt64(components.seconds)
        let attoseconds = max(0, components.attoseconds)
        return seconds.multipliedReportingOverflow(by: 1_000_000_000).partialValue
            + UInt64(attoseconds / 1_000_000_000)
    }

    private func captureOutcome(
        from recognitionOutcome: ContextBoostOCRRecognitionOutcome
    ) -> ContextBoostCaptureOutcome {
        switch recognitionOutcome {
        case .captured(let snapshot):
            return .captured(snapshot)
        case .noContext, .cancelled:
            return .unavailable("no_ocr_context")
        }
    }
}

private final class ContextBoostOCRResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: ContextBoostOCRRecognitionOutcome?

    var value: ContextBoostOCRRecognitionOutcome? {
        lock.withLock { storedValue }
    }

    func store(_ value: ContextBoostOCRRecognitionOutcome) {
        lock.withLock { storedValue = value }
    }
}
