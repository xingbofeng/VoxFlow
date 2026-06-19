import XCTest
import VoxFlowModelStore

final class ModelPrewarmCanaryRunnerTests: XCTestCase {
    func testRunnerLoadsCompilesRunsCanaryAndRecordsMetrics() async throws {
        let runtime = CapturingPrewarmRuntime(transcript: "hello qwen ready")
        let report = try await ModelPrewarmCanaryRunner().prepare(
            installation: installation(),
            canaryAudio: ModelCanaryAudio(
                samples: Array(repeating: 0.1, count: 32_000),
                sampleRate: 16_000,
                expectedTokens: ["hello", "ready"]
            ),
            runtime: runtime
        )

        let calls = await runtime.recordedCalls()
        XCTAssertEqual(calls, [.load, .compile, .canary])
        XCTAssertEqual(report.transcript, "hello qwen ready")
        XCTAssertGreaterThan(report.metrics.loadTime, Duration.zero)
        XCTAssertGreaterThan(report.metrics.canaryRTF, 0)
        XCTAssertTrue(report.isReady)
    }

    func testRunnerAllowsEmptyCanaryOutputWhenNoExpectedTokensAreConfigured() async throws {
        let runtime = CapturingPrewarmRuntime(transcript: "   ")

        let report = try await ModelPrewarmCanaryRunner().prepare(
            installation: installation(),
            canaryAudio: ModelCanaryAudio(samples: [0.1], sampleRate: 16_000, expectedTokens: []),
            runtime: runtime
        )

        XCTAssertEqual(report.transcript, "   ")
        XCTAssertFalse(report.isReady)
    }

    func testRunnerRejectsEmptyCanaryOutputWhenExpectedTokensRequireTranscript() async throws {
        let runtime = CapturingPrewarmRuntime(transcript: "   ")

        do {
            _ = try await ModelPrewarmCanaryRunner().prepare(
                installation: installation(),
                canaryAudio: ModelCanaryAudio(samples: [0.1], sampleRate: 16_000, expectedTokens: ["ready"]),
                runtime: runtime
            )
            XCTFail("Expected empty canary output to fail.")
        } catch let error as ModelPrewarmError {
            XCTAssertEqual(error, .emptyCanaryOutput)
        }
    }

    func testRunnerRejectsMissingExpectedToken() async throws {
        let runtime = CapturingPrewarmRuntime(transcript: "hello qwen")

        do {
            _ = try await ModelPrewarmCanaryRunner().prepare(
                installation: installation(),
                canaryAudio: ModelCanaryAudio(samples: [0.1], sampleRate: 16_000, expectedTokens: ["ready"]),
                runtime: runtime
            )
            XCTFail("Expected missing token to fail.")
        } catch let error as ModelPrewarmError {
            XCTAssertEqual(error, .missingExpectedToken("ready"))
        }
    }

    private func installation() -> ModelInstallation {
        ModelInstallation(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
            version: "2026.06.01",
            installedRoot: URL(fileURLWithPath: "/tmp/qwen")
        )
    }
}

private actor CapturingPrewarmRuntime: ModelRuntimePreparing {
    enum Call: Equatable {
        case load
        case compile
        case canary
    }

    private(set) var calls: [Call] = []
    private let transcript: String

    init(transcript: String) {
        self.transcript = transcript
    }

    func load(installation: ModelInstallation) async throws {
        calls.append(.load)
        try await Task.sleep(nanoseconds: 1_000_000)
    }

    func compile(installation: ModelInstallation) async throws {
        calls.append(.compile)
    }

    func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        calls.append(.canary)
        try await Task.sleep(nanoseconds: 1_000_000)
        return transcript
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
