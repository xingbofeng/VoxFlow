import Foundation
import XCTest
import VoxFlowContextBoost
@testable import VoxFlowApp

@MainActor
final class ContextBoostPrefetchCoordinatorTests: XCTestCase {
    func testResolveUsesAccurateResultWithoutStartingFast() async {
        let snapshot = makeSnapshot("Qwen3-ASR")
        let session = FakeContextBoostOCRCaptureSession(
            accurate: .immediate(.captured(snapshot)),
            fast: .immediate(.noContext)
        )
        let coordinator = ContextBoostPrefetchCoordinator(
            sessionProvider: FakeContextBoostOCRCaptureSessionProvider(session: session)
        )

        coordinator.start(target: DictationTarget(pid: 42))
        await waitUntilAccurateStarted(session)
        let outcome = await coordinator.resolve(postReleaseTimeoutNanoseconds: 100_000_000)

        XCTAssertEqual(outcome?.snapshot, snapshot)
        XCTAssertEqual(session.events, [.accurateStarted, .accurateStopped])
    }

    func testResolveWaitsForAccurateCancellationBeforeStartingFast() async {
        let snapshot = makeSnapshot("WhisperKit")
        let session = FakeContextBoostOCRCaptureSession(
            accurate: .waitForCancellation(.cancelled),
            fast: .immediate(.captured(snapshot))
        )
        let coordinator = ContextBoostPrefetchCoordinator(
            sessionProvider: FakeContextBoostOCRCaptureSessionProvider(session: session)
        )

        coordinator.start(target: DictationTarget(pid: 42))
        await waitUntilAccurateStarted(session)
        let outcome = await coordinator.resolve(postReleaseTimeoutNanoseconds: 100_000_000)

        XCTAssertEqual(outcome?.snapshot, snapshot)
        XCTAssertEqual(session.events, [
            .accurateStarted,
            .cancelRequested,
            .accurateStopped,
            .fastStarted,
            .fastStopped,
        ])
    }

    func testResolveAcceptsAccurateResultThatWinsCancellationRace() async {
        let snapshot = makeSnapshot("Project Apollo")
        let session = FakeContextBoostOCRCaptureSession(
            accurate: .waitForCancellation(.captured(snapshot)),
            fast: .immediate(.noContext)
        )
        let coordinator = ContextBoostPrefetchCoordinator(
            sessionProvider: FakeContextBoostOCRCaptureSessionProvider(session: session)
        )

        coordinator.start(target: DictationTarget(pid: 42))
        await waitUntilAccurateStarted(session)
        let outcome = await coordinator.resolve(postReleaseTimeoutNanoseconds: 100_000_000)

        XCTAssertEqual(outcome?.snapshot, snapshot)
        XCTAssertFalse(session.events.contains(.fastStarted))
    }

    func testResolveTimesOutFastWithinPostReleaseBudget() async {
        let session = FakeContextBoostOCRCaptureSession(
            accurate: .waitForCancellation(.cancelled),
            fast: .waitForCancellation(.cancelled)
        )
        let coordinator = ContextBoostPrefetchCoordinator(
            sessionProvider: FakeContextBoostOCRCaptureSessionProvider(session: session)
        )

        coordinator.start(target: DictationTarget(pid: 42))
        await waitUntilAccurateStarted(session)
        let outcome = await coordinator.resolve(postReleaseTimeoutNanoseconds: 10_000_000)

        XCTAssertEqual(outcome?.failureReason, "context_boost_timeout")
        XCTAssertEqual(session.events.filter { $0 == .cancelRequested }.count, 2)
    }

    private func makeSnapshot(_ hotword: String) -> OCRContextSnapshot {
        OCRContextSnapshot(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowTitle: "Notes",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            hotwords: [temporaryHotword(hotword)]
        )
    }

    private func waitUntilAccurateStarted(_ session: FakeContextBoostOCRCaptureSession) async {
        for _ in 0..<100 where !session.events.contains(.accurateStarted) {
            await Task.yield()
        }
        XCTAssertTrue(session.events.contains(.accurateStarted))
    }

    private func temporaryHotword(_ text: String) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: text.lowercased(),
            score: 1,
            source: .ocrKeyphrase,
            evidence: [],
            expiresAt: Date(timeIntervalSince1970: 1_800_000_120)
        )
    }
}

private final class FakeContextBoostOCRCaptureSessionProvider: ContextBoostOCRCaptureSessionProviding, @unchecked Sendable {
    let session: any ContextBoostOCRCaptureSession

    init(session: any ContextBoostOCRCaptureSession) {
        self.session = session
    }

    func makeCaptureSession(for target: DictationTarget) -> (any ContextBoostOCRCaptureSession)? {
        session
    }
}

private final class FakeContextBoostOCRCaptureSession: ContextBoostOCRCaptureSession, @unchecked Sendable {
    enum Event: Equatable {
        case accurateStarted
        case accurateStopped
        case fastStarted
        case fastStopped
        case cancelRequested
    }

    enum Behavior {
        case immediate(ContextBoostOCRRecognitionOutcome)
        case waitForCancellation(ContextBoostOCRRecognitionOutcome)
    }

    private let accurate: Behavior
    private let fast: Behavior
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ContextBoostOCRRecognitionOutcome, Never>?
    private var cancellationOutcome: ContextBoostOCRRecognitionOutcome?
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    init(accurate: Behavior, fast: Behavior) {
        self.accurate = accurate
        self.fast = fast
    }

    func recognize(quality: ContextBoostOCRQuality) async -> ContextBoostOCRRecognitionOutcome {
        append(quality == .accurate ? .accurateStarted : .fastStarted)
        if Task.isCancelled {
            append(quality == .accurate ? .accurateStopped : .fastStopped)
            return .cancelled
        }
        let behavior = quality == .accurate ? accurate : fast
        let outcome: ContextBoostOCRRecognitionOutcome
        switch behavior {
        case .immediate(let result):
            outcome = result
        case .waitForCancellation(let result):
            outcome = await withCheckedContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    cancellationOutcome = result
                }
            }
        }
        append(quality == .accurate ? .accurateStopped : .fastStopped)
        return outcome
    }

    func cancelCurrentRecognition() {
        let pending: (CheckedContinuation<ContextBoostOCRRecognitionOutcome, Never>, ContextBoostOCRRecognitionOutcome)? = lock.withLock {
            recordedEvents.append(.cancelRequested)
            guard let continuation, let cancellationOutcome else { return nil }
            self.continuation = nil
            self.cancellationOutcome = nil
            return (continuation, cancellationOutcome)
        }
        pending?.0.resume(returning: pending!.1)
    }

    private func append(_ event: Event) {
        lock.withLock { recordedEvents.append(event) }
    }
}

private extension ContextBoostCaptureOutcome {
    var snapshot: OCRContextSnapshot? {
        guard case .captured(let snapshot) = self else { return nil }
        return snapshot
    }

    var failureReason: String? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }
}
