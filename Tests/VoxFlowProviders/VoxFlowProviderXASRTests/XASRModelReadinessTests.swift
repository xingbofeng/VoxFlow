import Foundation
import VoxFlowModelStore
import XCTest
@testable import VoxFlowProviderXASR

final class XASRModelReadinessTests: XCTestCase, @unchecked Sendable {
    func testReadinessRequiresAnActualCanaryDecodeAndFinal() async throws {
        let stream = ReadinessStream(final: "你好，这是识别测试")
        let runner = XASRModelReadinessRunner(streamFactory: ReadinessFactory(stream: stream))
        let report = try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/xasr-canary"))
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.transcript, "你好，这是识别测试")
        let accepted = await stream.acceptedSampleCount
        XCTAssertGreaterThan(accepted, 16_000)
        let finished = await stream.didFinish
        XCTAssertTrue(finished)
    }

    func testEmptyCanaryDoesNotMarkModelReady() async throws {
        let stream = ReadinessStream(final: "")
        let runner = XASRModelReadinessRunner(streamFactory: ReadinessFactory(stream: stream))
        do { _ = try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/xasr-canary")); XCTFail("empty canary marked ready") }
        catch {}
    }
}

private struct ReadinessFactory: XASRStreamMaking {
    let stream: ReadinessStream
    func makeStream(directoryURL: URL) async throws -> any XASRStreaming { stream }
}
private actor ReadinessStream: XASRStreaming {
    let final: String
    var acceptedSampleCount = 0
    var didFinish = false
    init(final: String) { self.final = final }
    func accept(samples: [Float], sampleRate: Int) async throws -> String { acceptedSampleCount += samples.count; return "" }
    func finish() async throws -> String { didFinish = true; return final }
    func cancel() async {}
}
