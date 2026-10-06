import Foundation
import VoxFlowASRCore
import VoxFlowAudio
import XCTest
@testable import VoxFlowProviderXASR

final class XASRASRSessionTests: XCTestCase, @unchecked Sendable {
    func testContinuousSpeechAndSilenceProduceRevisablePreviewThenOneFinal() async throws {
        let stream = CapturingXASRStream(partials: ["你 好", "你 好", "你 好 世 界"], final: "你 好 世 界 。")
        let session = makeSession(stream)
        let events = Task { await collect(session.events) }
        try await session.start()
        try await session.accept(frame(0, samples: [0.1, 0.2]))
        try await session.accept(frame(1, samples: [0, 0]))
        try await session.accept(frame(2, samples: [0.3, 0.4]))
        try await session.finish()
        try await session.finish()
        await session.cancel()
        let delivered = await events.value
        let partials = delivered.compactMap { event -> PartialTranscript? in
            if case .partial(_, let text) = event { return text }; return nil
        }
        XCTAssertEqual(partials.map(\.unstableSuffix), ["你好", "你好世界"])
        XCTAssertTrue(partials.allSatisfy { $0.stablePrefix.isEmpty })
        XCTAssertEqual(delivered.compactMap(finalText), ["你好世界。"])
        let received = await stream.receivedSamples
        XCTAssertEqual(received, [[0.1, 0.2], [0, 0], [0.3, 0.4]])
        let metrics = delivered.compactMap { event -> ASRMetrics? in
            if case .metrics(_, _, let metrics) = event { return metrics }; return nil
        }.first
        XCTAssertEqual(metrics?.processedFrameCount, 3)
        XCTAssertEqual(metrics?.audioDuration, .nanoseconds(375_000))
    }

    func testOutOfOrderAudioFailsWithoutFeedingTheBrokenFrame() async throws {
        let stream = CapturingXASRStream(partials: ["你好"], final: "你好")
        let session = makeSession(stream)
        let events = Task { await collect(session.events) }
        try await session.start()
        try await session.accept(frame(0, samples: [0.1, 0.2]))
        do { try await session.accept(frame(2, samples: [0.3, 0.4])); XCTFail("lost frame was accepted") }
        catch {}
        await session.cancel()
        let delivered = await events.value
        XCTAssertTrue(delivered.contains { if case .failure(_, _, let error) = $0 { return error.category == .audioDropped }; return false })
        let received = await stream.receivedSamples
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(delivered.compactMap(finalText).isEmpty)
    }

    func testEmptyRecognitionIsFailureRatherThanAnEmptyFinal() async throws {
        let session = makeSession(CapturingXASRStream(partials: [""], final: "  "))
        let events = Task { await collect(session.events) }
        try await session.start()
        try await session.accept(frame(0, samples: [0, 0]))
        do { try await session.finish(); XCTFail("empty final was accepted") } catch {}
        await session.cancel()
        let delivered = await events.value
        XCTAssertTrue(delivered.contains { if case .failure(_, _, let error) = $0 { return error.category == .emptyTranscript }; return false })
        XCTAssertTrue(delivered.compactMap(finalText).isEmpty)
    }

    func testCancellationSuppressesLateText() async throws {
        let stream = GatedXASRStream()
        let session = XASRASRSession(sessionID: .init(rawValue: "cancel"), modelURL: URL(fileURLWithPath: "/tmp/xasr-test"), streamFactory: FixedXASRFactory(stream: stream))
        let events = Task { await collect(session.events) }
        try await session.start()
        let accept = Task { try await session.accept(frame(0, samples: [0.1, 0.2])) }
        await stream.waitUntilEntered()
        await session.cancel()
        await stream.release()
        _ = try? await accept.value
        let delivered = await events.value
        XCTAssertFalse(delivered.contains { if case .partial = $0 { return true }; return false })
        XCTAssertTrue(delivered.compactMap(finalText).isEmpty)
    }

    func testCancellationDuringLoadingDoesNotPublishReadyOrLeakCreatedStream() async throws {
        let stream = CapturingXASRStream(partials: ["你好"], final: "你好")
        let factory = LoadingXASRFactory(stream: stream)
        let session = XASRASRSession(sessionID: .init(rawValue: "loading"), modelURL: URL(fileURLWithPath: "/tmp/xasr-test"), streamFactory: factory)
        let events = Task { await collect(session.events) }
        let loading = Task { try await session.start() }
        await factory.waitUntilEntered()
        await session.cancel()
        await factory.release()
        _ = try? await loading.value
        let delivered = await events.value
        XCTAssertFalse(delivered.contains { if case .ready = $0 { return true }; return false })
        XCTAssertTrue(delivered.compactMap(finalText).isEmpty)
        let cancelled = await stream.cancelCount
        XCTAssertEqual(cancelled, 1)
    }

    private func makeSession(_ stream: any XASRStreaming) -> XASRASRSession {
        XASRASRSession(sessionID: .init(rawValue: UUID().uuidString), modelURL: URL(fileURLWithPath: "/tmp/xasr-test"), streamFactory: FixedXASRFactory(stream: stream))
    }
}

private func frame(_ index: UInt64, samples: [Float]) -> AudioFrame {
    AudioFrame(sequenceNumber: index, startSample: index * 2, samples: ContiguousArray(samples), sampleRate: 16_000, capturedAt: .now)
}
private func collect(_ stream: AsyncStream<ASREvent>) async -> [ASREvent] {
    var events: [ASREvent] = []; for await event in stream { events.append(event) }; return events
}
private func finalText(_ event: ASREvent) -> String? {
    if case .final(_, _, let text) = event { return text }; return nil
}
private struct FixedXASRFactory: XASRStreamMaking {
    let stream: any XASRStreaming
    func makeStream(directoryURL: URL) async throws -> any XASRStreaming { stream }
}
private actor CapturingXASRStream: XASRStreaming {
    let partials: [String]
    let final: String
    var receivedSamples: [[Float]] = []
    var cancelCount = 0
    init(partials: [String], final: String) { self.partials = partials; self.final = final }
    func accept(samples: [Float], sampleRate: Int) async throws -> String {
        receivedSamples.append(samples)
        return partials[min(receivedSamples.count - 1, partials.count - 1)]
    }
    func finish() async throws -> String { final }
    func cancel() async { cancelCount += 1 }
}
private actor LoadingXASRFactory: XASRStreamMaking {
    let stream: any XASRStreaming
    private var entered = false
    private var gate: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    init(stream: any XASRStreaming) { self.stream = stream }
    func makeStream(directoryURL: URL) async throws -> any XASRStreaming {
        entered = true; observers.forEach { $0.resume() }; observers = []
        await withCheckedContinuation { gate = $0 }
        return stream
    }
    func waitUntilEntered() async {
        if entered { return }; await withCheckedContinuation { observers.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
}
private actor GatedXASRStream: XASRStreaming {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var gate: CheckedContinuation<Void, Never>?
    func accept(samples: [Float], sampleRate: Int) async throws -> String {
        entered = true; observers.forEach { $0.resume() }; observers = []
        await withCheckedContinuation { gate = $0 }
        return "迟到文本"
    }
    func waitUntilEntered() async {
        if entered { return }; await withCheckedContinuation { observers.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
    func finish() async throws -> String { "final" }
    func cancel() async {}
}
