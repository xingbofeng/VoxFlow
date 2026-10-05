import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRModelReadinessRunnerTests: XCTestCase {
    func testCanaryAudioIsOneSecondOfOneKilohertz() {
        let audio = FireRedASRModelReadinessRunner.canaryAudio

        XCTAssertEqual(audio.sampleRate, 16_000)
        XCTAssertEqual(audio.samples.count, 16_000)
        XCTAssertTrue(audio.expectedTokens.isEmpty)
        XCTAssertGreaterThan(audio.samples.map(abs).max() ?? 0, 0)
    }

    func testPrepareLoadsRuntimeAndReportsReadyWhenTheCanaryProducesText() async throws {
        let preparer = RecordingRuntimePreparer(canaryTranscript: "<sil>")
        let runner = FireRedASRModelReadinessRunner(runtimeFactory: { _ in preparer })

        let report = try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/fireredasr"))

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.transcript, "<sil>")
        XCTAssertEqual(preparer.calls, ["load", "compile", "transcribeCanary"])
    }

    func testEmptyCanaryOutputFails() async {
        let preparer = RecordingRuntimePreparer(canaryTranscript: "   ")
        let runner = FireRedASRModelReadinessRunner(runtimeFactory: { _ in preparer })

        await XCTAssertThrowsErrorAsync(
            try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/fireredasr"))
        ) { error in
            XCTAssertEqual(error as? ModelPrewarmError, .emptyCanaryOutput)
        }
    }

    func testRuntimeLoadFailurePropagates() async {
        let preparer = RecordingRuntimePreparer(canaryTranscript: "ok", loadError: true)
        let runner = FireRedASRModelReadinessRunner(runtimeFactory: { _ in preparer })

        await XCTAssertThrowsErrorAsync(
            try await runner.prepare(modelURL: URL(fileURLWithPath: "/tmp/fireredasr"))
        ) { error in
            XCTAssertEqual(error as? FireRedASRProviderError, .preparationFailed("boom"))
        }
    }
}

/// 记录 `ModelRuntimePreparing` 的调用顺序，让 canary 流程可以脱离模型被测试。
private final class RecordingRuntimePreparer: ModelRuntimePreparing, @unchecked Sendable {
    private let lock = NSLock()
    private let canaryTranscript: String
    private let loadError: Bool
    private var storage: [String] = []

    var calls: [String] {
        lock.withLock { storage }
    }

    init(canaryTranscript: String, loadError: Bool = false) {
        self.canaryTranscript = canaryTranscript
        self.loadError = loadError
    }

    func load(installation: ModelInstallation) async throws {
        lock.withLock { storage.append("load") }
        if loadError {
            throw FireRedASRProviderError.preparationFailed("boom")
        }
    }

    func compile(installation: ModelInstallation) async throws {
        lock.withLock { storage.append("compile") }
    }

    func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        lock.withLock { storage.append("transcribeCanary") }
        return canaryTranscript
    }
}
