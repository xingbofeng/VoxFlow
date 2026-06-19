import VoxFlowAudio
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3StreamingRuntimeDriverTests: XCTestCase {
    func testStartOnlyCreatesSessionWithoutRunningRecognition() async throws {
        let runtime = CapturingRuntimeDriverSession(
            partial: Qwen3StreamingUpdate(transcript: "不应在 start 时出现", isFinal: false),
            final: Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true)
        )
        let factory = CapturingRuntimeDriverSessionFactory(session: runtime)
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-driver", isDirectory: true)
        let driver = Qwen3StreamingRuntimeDriver(
            modelURL: modelURL,
            languageHint: "zh",
            sessionFactory: factory
        )

        try await driver.start()

        XCTAssertEqual(factory.modelURLs, [modelURL])
        XCTAssertEqual(factory.languageHints, ["zh"])
        let addAudioCount = await runtime.addAudioCallCount()
        let finishCount = await runtime.finishCallCount()
        XCTAssertEqual(addAudioCount, 0)
        XCTAssertEqual(finishCount, 0)
    }

    func testFinishFlushesTailAfterStreamingFinal() async throws {
        let runtime = CapturingRuntimeDriverSession(
            partial: Qwen3StreamingUpdate(transcript: "流式最终文本", isFinal: true),
            final: Qwen3StreamingUpdate(transcript: "尾部刷新后的最终文本", isFinal: true)
        )
        let factory = CapturingRuntimeDriverSessionFactory(session: runtime)
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-driver", isDirectory: true)
        let driver = Qwen3StreamingRuntimeDriver(
            modelURL: modelURL,
            languageHint: "zh",
            sessionFactory: factory
        )

        try await driver.start()
        let streamingUpdate = try await driver.accept(Self.frame(sequenceNumber: 1))
        let finishUpdate = try await driver.finish()

        XCTAssertEqual(factory.modelURLs, [modelURL])
        XCTAssertEqual(factory.languageHints, ["zh"])
        XCTAssertEqual(streamingUpdate, Qwen3StreamingUpdate(transcript: "流式最终文本", isFinal: true))
        XCTAssertEqual(finishUpdate, Qwen3StreamingUpdate(transcript: "尾部刷新后的最终文本", isFinal: true))
        let finishCount = await runtime.finishCallCount()
        XCTAssertEqual(finishCount, 1)
    }

    func testFinishCollapsesDuplicatedFinalSentenceFromCumulativeRecognition() async throws {
        let runtime = CapturingRuntimeDriverSession(
            partial: Qwen3StreamingUpdate(transcript: "我只说了一句。", isFinal: false),
            final: Qwen3StreamingUpdate(transcript: "我只说了一句。我只说了一句。", isFinal: true)
        )
        let driver = Qwen3StreamingRuntimeDriver(
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-driver", isDirectory: true),
            languageHint: "zh",
            sessionFactory: CapturingRuntimeDriverSessionFactory(session: runtime)
        )

        try await driver.start()
        _ = try await driver.accept(Self.frame(sequenceNumber: 1))
        let finishUpdate = try await driver.finish()

        XCTAssertEqual(finishUpdate, Qwen3StreamingUpdate(transcript: "我只说了一句。", isFinal: true))
    }

    func testShortChunkIsBufferedUntilFinishFlushesPendingAudio() async throws {
        let runtime = CapturingRuntimeDriverSession(
            partial: Qwen3StreamingUpdate(transcript: "过早的实时反馈", isFinal: false),
            final: Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true)
        )
        let driver = Qwen3StreamingRuntimeDriver(
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-driver", isDirectory: true),
            languageHint: "zh",
            sessionFactory: CapturingRuntimeDriverSessionFactory(session: runtime)
        )

        try await driver.start()
        let update = try await driver.accept(Self.frame(sequenceNumber: 1, sampleCount: 16_000))

        XCTAssertNil(update)
        let countBeforeFinish = await runtime.addAudioCallCount()
        XCTAssertEqual(countBeforeFinish, 0)

        let final = try await driver.finish()

        XCTAssertEqual(final, Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true))
        let countAfterFinish = await runtime.addAudioCallCount()
        let acceptedSampleCounts = await runtime.acceptedSampleCounts()
        XCTAssertEqual(countAfterFinish, 1)
        XCTAssertEqual(acceptedSampleCounts, [16_000])
    }

    func testAcceptDropsLateUpdateWhenCancelledDuringRuntimeCall() async throws {
        let runtime = DelayedRuntimeDriverSession(
            partial: Qwen3StreamingUpdate(transcript: "取消后晚到文本", isFinal: false),
            final: Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true)
        )
        let driver = Qwen3StreamingRuntimeDriver(
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-driver", isDirectory: true),
            languageHint: "zh",
            sessionFactory: CapturingRuntimeDriverSessionFactory(session: runtime)
        )

        try await driver.start()
        async let lateUpdate = driver.accept(Self.frame(sequenceNumber: 2))
        let reachedAddAudio = await waitUntil(timeout: 1.0) {
            await runtime.addAudioCallCount() > 0
        }
        XCTAssertTrue(reachedAddAudio)

        await driver.cancel()
        await runtime.releaseDelayedAddAudio()

        let update = try await lateUpdate
        XCTAssertNil(update)
    }

    private static func frame(sequenceNumber: UInt64, sampleCount: Int = 32_000) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: 0.1, count: sampleCount),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

private final class CapturingRuntimeDriverSessionFactory: Qwen3StreamingSessionMaking, @unchecked Sendable {
    let session: any Qwen3StreamingSession
    private(set) var modelURLs: [URL] = []
    private(set) var languageHints: [String?] = []

    init(session: any Qwen3StreamingSession) {
        self.session = session
    }

    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession {
        modelURLs.append(modelURL)
        languageHints.append(languageHint)
        return session
    }
}

private actor CapturingRuntimeDriverSession: Qwen3StreamingSession {
    let partial: Qwen3StreamingUpdate?
    let final: Qwen3StreamingUpdate
    private(set) var finishCount = 0
    private var acceptedSamples: [[Float]] = []

    init(partial: Qwen3StreamingUpdate?, final: Qwen3StreamingUpdate) {
        self.partial = partial
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        acceptedSamples.append(samples)
        return partial
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        finishCount += 1
        return final
    }

    func finishCallCount() -> Int {
        finishCount
    }

    func addAudioCallCount() -> Int {
        acceptedSamples.count
    }

    func acceptedSampleCounts() -> [Int] {
        acceptedSamples.map(\.count)
    }

    func cancel() async {}
}

private actor DelayedRuntimeDriverSession: Qwen3StreamingSession {
    let partial: Qwen3StreamingUpdate?
    let final: Qwen3StreamingUpdate
    private(set) var addAudioCount = 0
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(partial: Qwen3StreamingUpdate?, final: Qwen3StreamingUpdate) {
        self.partial = partial
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        addAudioCount += 1
        if !isReleased {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return partial
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        final
    }

    func cancel() async {}

    func addAudioCallCount() -> Int {
        addAudioCount
    }

    func releaseDelayedAddAudio() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
