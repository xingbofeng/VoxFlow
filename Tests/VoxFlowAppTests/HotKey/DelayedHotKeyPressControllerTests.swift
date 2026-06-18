import XCTest
@testable import VoxFlowApp

@MainActor
final class DelayedHotKeyPressControllerTests: XCTestCase {
    func testScheduleDelaysPressUntilThresholdSleepCompletes() async throws {
        let sleeper = HotKeySleepProbe()
        let controller = DelayedHotKeyPressController(
            sleep: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        var handledActions: [VoiceAction] = []

        controller.schedule(action: .dictation, threshold: 0.25) { action in
            handledActions.append(action)
        }
        await sleeper.waitUntilSleeping()

        let recordedNanoseconds = await sleeper.recordedNanoseconds()
        XCTAssertEqual(recordedNanoseconds, [250_000_000])
        XCTAssertTrue(handledActions.isEmpty)

        await sleeper.resume()
        await Task.yield()

        XCTAssertEqual(handledActions, [.dictation])
    }

    func testCancelPreventsScheduledPressFromFiring() async throws {
        let sleeper = HotKeySleepProbe()
        let controller = DelayedHotKeyPressController(
            sleep: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        var handledActions: [VoiceAction] = []

        controller.schedule(action: .agentCompose, threshold: 0.25) { action in
            handledActions.append(action)
        }
        await sleeper.waitUntilSleeping()
        controller.cancel()

        await sleeper.resume()
        await Task.yield()

        XCTAssertTrue(handledActions.isEmpty)
    }
}

private actor HotKeySleepProbe {
    private var nanoseconds: [UInt64] = []
    private var continuation: CheckedContinuation<Void, Error>?
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(nanoseconds: UInt64) async throws {
        self.nanoseconds.append(nanoseconds)
        sleepWaiters.forEach { $0.resume() }
        sleepWaiters.removeAll()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func recordedNanoseconds() -> [UInt64] {
        nanoseconds
    }

    func waitUntilSleeping() async {
        if !nanoseconds.isEmpty {
            return
        }
        await withCheckedContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
