import Foundation
import VoxFlowModelStore
import XCTest
@testable import VoxFlowProviderXASR

final class XASRModelReadinessTests: XCTestCase, @unchecked Sendable {
    /// CI runner 只有 7 GiB 物理内存，低于 8 GiB 门槛；readiness 用例必须注入可用环境，
    /// 只隔离 canary 行为本身，不依赖宿主机硬件。
    private static let usableEnvironment = XASRRuntimePreflight.Environment(
        architecture: .arm64, physicalMemoryBytes: 48 * 1_024 * 1_024 * 1_024, macOSMajorVersion: 15
    )

    func testReadinessRequiresAnActualCanaryDecodeAndFinal() async throws {
        let stream = ReadinessStream(final: "你好，这是识别测试")
        let runner = XASRModelReadinessRunner(streamFactory: ReadinessFactory(stream: stream), environment: Self.usableEnvironment)
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
        let runner = XASRModelReadinessRunner(streamFactory: ReadinessFactory(stream: stream), environment: Self.usableEnvironment)
        do { _ = try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/xasr-canary")); XCTFail("empty canary marked ready") }
        catch {}
    }

    func testBlockedEnvironmentFailsBeforeAnyCanaryAudio() async {
        let stream = ReadinessStream(final: "不应被消费")
        let runner = XASRModelReadinessRunner(
            streamFactory: ReadinessFactory(stream: stream),
            environment: .init(architecture: .x86_64, physicalMemoryBytes: 48 * 1_024 * 1_024 * 1_024, macOSMajorVersion: 15)
        )
        do {
            _ = try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/xasr-canary"))
            XCTFail("blocked environment was accepted")
        } catch let error as XASRProviderError {
            guard case .preflightBlocked(let blocker) = error, case .architectureUnsupported = blocker else {
                return XCTFail("expected architecture block, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        let accepted = await stream.acceptedSampleCount
        XCTAssertEqual(accepted, 0)
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
