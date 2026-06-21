import VoxFlowASRCore
import VoxFlowAudio
import XCTest
@testable import VoxFlowApp

final class ASRCoreBackedASREngineTests: XCTestCase {
    func testMapsASRCoreSessionEventsToLegacyCallbacks() async throws {
        let session = CapturingCoreSession()
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let partial = expectation(description: "partial callback")
        let final = expectation(description: "final callback")
        var callbacks: [(String, Bool)] = []
        engine.onTranscription = { (text: String, isFinal: Bool) in
            callbacks.append((text, isFinal))
            if text == "实时片段", !isFinal {
                partial.fulfill()
            }
            if text == "最终文本", isFinal {
                final.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 7))
        engine.endAudio()

        await fulfillment(of: [partial, final], timeout: 1.0)
        XCTAssertTrue(engine.isAvailable)
        XCTAssertEqual(provider.requestedLanguages.map { $0.bcp47Tag }, ["zh-CN"])
        XCTAssertEqual(session.acceptedSequenceNumbers(), [7])
        XCTAssertEqual(session.finishCallCount(), 1)
        XCTAssertEqual(callbacks.map(\.0), ["实时片段", "最终文本"])
        XCTAssertEqual(callbacks.map(\.1), [false, true])
    }

    func testEndAudioIgnoresLateAudioFramesAfterFinalCallback() async throws {
        let session = CapturingCoreSession()
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let final = expectation(description: "final callback")
        engine.onTranscription = { _, isFinal in
            if isFinal {
                final.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 7))
        engine.endAudio()
        await fulfillment(of: [final], timeout: 1.0)

        engine.appendAudioFrame(Self.frame(sequenceNumber: 8))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(session.acceptedSequenceNumbers(), [7])
        XCTAssertEqual(session.finishCallCount(), 1)
    }

    func testEndAudioWithoutAcceptedAudioEmitsEmptyFinalWithoutFinishingProviderSession() async throws {
        let session = CapturingCoreSession()
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let emptyFinal = expectation(description: "empty final callback")
        var callbacks: [(String, Bool)] = []
        engine.onTranscription = { text, isFinal in
            callbacks.append((text, isFinal))
            if text.isEmpty, isFinal {
                emptyFinal.fulfill()
            }
        }

        try engine.start()
        engine.endAudio()

        await fulfillment(of: [emptyFinal], timeout: 1.0)
        XCTAssertEqual(callbacks.map(\.0), [""])
        XCTAssertEqual(callbacks.map(\.1), [true])
        XCTAssertEqual(session.acceptedSequenceNumbers(), [])
        XCTAssertEqual(session.finishCallCount(), 0)
    }

    func testCapturesASRCoreSessionIDAndMetricsForDiagnostics() async throws {
        let session = CapturingCoreSession()
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let final = expectation(description: "final callback")
        engine.onTranscription = { _, isFinal in
            if isFinal {
                final.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 7))
        engine.endAudio()

        await fulfillment(of: [final], timeout: 1.0)
        let metadata = engine.asrRuntimeMetadataSnapshot
        XCTAssertEqual(metadata.sessionID, "capturing-core-session")
        XCTAssertEqual(metadata.audioDurationMs, 125)
        XCTAssertEqual(metadata.droppedFrameCount, 2)
        XCTAssertNil(metadata.errorCode)
    }

    func testStopIgnoresLaterAudioFrames() async throws {
        let session = CapturingCoreSession()
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let partial = expectation(description: "first partial callback")
        var didFulfillFirstPartial = false
        engine.onTranscription = { text, isFinal in
            if text == "实时片段", !isFinal, !didFulfillFirstPartial {
                didFulfillFirstPartial = true
                partial.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 7))
        await fulfillment(of: [partial], timeout: 1.0)

        engine.stop()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 8))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(session.acceptedSequenceNumbers(), [7])
    }

    func testStopReleasesProviderSessionAfterFinalEvenWhenEventsRemainOpen() async throws {
        let session = CapturingCoreSession(finishEventStreamOnFinish: false)
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let final = expectation(description: "final callback")
        engine.onTranscription = { _, isFinal in
            if isFinal {
                final.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 7))
        engine.endAudio()
        await fulfillment(of: [final], timeout: 1.0)

        engine.stop()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(session.cancelCallCount(), 1)
    }

    func testAudioFramesUseBoundedBufferWhenProviderIsBackPressured() async throws {
        let session = CapturingCoreSession(acceptDelayNanoseconds: 500_000_000)
        let provider = CapturingCoreProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: ASRProviderID(rawValue: "test-provider"),
                displayName: "Test Provider",
                modelInstallationState: .ready,
                supportedLanguages: [ASRLanguageCapability(bcp47Tag: "zh-CN")],
                streamingSemantics: .nativeStreaming
            ),
            session: session
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )

        try engine.start()
        for sequenceNumber in 0..<220 {
            engine.appendAudioFrame(Self.frame(sequenceNumber: UInt64(sequenceNumber)))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let metadata = engine.asrRuntimeMetadataSnapshot
        engine.cancel()

        XCTAssertGreaterThan(metadata.droppedFrameCount ?? 0, 0)
    }

    private static func frame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}

private final class CapturingCoreProvider: ASRProvider, @unchecked Sendable {
    let descriptor: VoxFlowASRCore.ASRProviderDescriptor
    let session: CapturingCoreSession
    private(set) var requestedLanguages: [ASRLanguageCapability] = []

    init(descriptor: VoxFlowASRCore.ASRProviderDescriptor, session: CapturingCoreSession) {
        self.descriptor = descriptor
        self.session = session
    }

    func install() async throws {}
    func delete() async throws {}
    func prepare() async throws {}
    func healthCheck() async -> ASRProviderHealth { .healthy }

    func makeSession(language: ASRLanguageCapability) async throws -> any ASRSession {
        requestedLanguages.append(language)
        return session
    }
}

private final class CapturingCoreSession: ASRSession, @unchecked Sendable {
    let sessionID = ASRSessionID(rawValue: "capturing-core-session")
    var events: AsyncStream<ASREvent> { eventStream.stream }
    var revision: UInt64 { lock.withLock { currentRevision } }

    private let eventStream = ASREventStream()
    private let lock = NSLock()
    private let acceptDelayNanoseconds: UInt64
    private let finishEventStreamOnFinish: Bool
    private var currentRevision: UInt64 = 0
    private var acceptedFrames: [AudioFrame] = []
    private var finishCount = 0
    private var cancelCount = 0

    init(
        acceptDelayNanoseconds: UInt64 = 0,
        finishEventStreamOnFinish: Bool = true
    ) {
        self.acceptDelayNanoseconds = acceptDelayNanoseconds
        self.finishEventStreamOnFinish = finishEventStreamOnFinish
    }

    func start() async throws {
        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        let readyRevision = lock.withLock {
            currentRevision += 1
            return currentRevision
        }
        eventStream.yield(.ready(sessionID: sessionID, revision: readyRevision))
    }

    func accept(_ frame: AudioFrame) async throws {
        if acceptDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: acceptDelayNanoseconds)
        }
        let partialRevision = lock.withLock {
            acceptedFrames.append(frame)
            currentRevision += 1
            return currentRevision
        }
        eventStream.yield(
            .partial(
                sessionID: sessionID,
                transcript: PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: "实时片段",
                    revision: partialRevision,
                    audioDuration: .milliseconds(100)
                )
            )
        )
    }

    func finish() async throws {
        let finalRevision = lock.withLock {
            finishCount += 1
            currentRevision += 1
            return currentRevision
        }
        eventStream.yield(
            .metrics(
                sessionID: sessionID,
                revision: finalRevision + 1,
                metrics: ASRMetrics(
                    audioDuration: .milliseconds(125),
                    processedFrameCount: 1,
                    droppedFrameCount: 2
                )
            )
        )
        eventStream.yield(.final(sessionID: sessionID, revision: finalRevision, text: "最终文本"))
        if finishEventStreamOnFinish {
            eventStream.finish()
        }
    }

    func cancel() async {
        lock.withLock {
            cancelCount += 1
        }
        eventStream.finish()
    }

    func acceptedSequenceNumbers() -> [UInt64] {
        lock.withLock {
            acceptedFrames.map(\.sequenceNumber)
        }
    }

    func finishCallCount() -> Int {
        lock.withLock { finishCount }
    }

    func cancelCallCount() -> Int {
        lock.withLock { cancelCount }
    }
}
