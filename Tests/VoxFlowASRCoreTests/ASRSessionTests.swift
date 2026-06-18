import XCTest
import VoxFlowASRCore
import VoxFlowAudio

final class ASRSessionTests: XCTestCase {
    func testASRSessionProtocolExposesLifecycleAndAudioFrameInput() async throws {
        let sessionID = ASRSessionID(rawValue: "session-protocol")
        let eventStream = ASREventStream()
        let session: any ASRSession = CapturingASRSession(
            sessionID: sessionID,
            revision: 9,
            events: eventStream.stream
        )

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()
        await session.cancel()

        XCTAssertEqual(session.sessionID, sessionID)
        XCTAssertEqual(session.revision, 9)
    }

    func testASREventStreamYieldsEventsInEmissionOrder() async {
        let stream = ASREventStream()
        let sessionID = ASRSessionID(rawValue: "ordered-session")
        let collector = Task {
            var events: [ASREvent] = []
            for await event in stream.stream {
                events.append(event)
            }
            return events
        }

        stream.yield(.preparing(sessionID: sessionID, revision: 0))
        stream.yield(.ready(sessionID: sessionID, revision: 1))
        stream.yield(.final(sessionID: sessionID, revision: 2, text: "done"))
        stream.finish()

        let events = await collector.value
        XCTAssertEqual(events.map(\.revision), [0, 1, 2])
    }

    private static func frame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: sequenceNumber * 160,
            samples: [0.1],
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}

private struct CapturingASRSession: ASRSession {
    let sessionID: ASRSessionID
    let revision: UInt64
    let events: AsyncStream<ASREvent>

    func start() async throws {}
    func accept(_ frame: AudioFrame) async throws {}
    func finish() async throws {}
    func cancel() async {}
}
