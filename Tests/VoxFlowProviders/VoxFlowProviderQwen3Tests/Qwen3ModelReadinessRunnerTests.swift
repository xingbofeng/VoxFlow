import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3ModelReadinessRunnerTests: XCTestCase {
    func testSpeechSwiftRuntimeProbeCanaryIsNonSilentAndUsesExpectedSampleRate() {
        let canary = Qwen3ModelCanaryAudio.speechSwiftRuntimeProbe
        let rms = sqrt(
            canary.samples.reduce(0) { $0 + Double($1 * $1) }
                / Double(canary.samples.count)
        )

        XCTAssertEqual(canary.sampleRate, 16_000)
        XCTAssertEqual(canary.samples.count, 12_800)
        XCTAssertGreaterThan(rms, 0.01)
        XCTAssertTrue(canary.expectedTokens.isEmpty)
    }

    func testPrepareBuildsInstallationFromVariantMetadataAndRunsCanary() async throws {
        let runtime = CapturingReadinessRuntime(transcript: "ready token")
        let factory = CapturingReadinessRuntimeFactory(runtime: runtime)
        let canary = ModelCanaryAudio(
            samples: [0.1, 0.2],
            sampleRate: 16_000,
            expectedTokens: ["ready"]
        )
        let runner = Qwen3ModelReadinessRunner(
            runtimeFactory: factory.makeRuntime(modelURL:variant:),
            canaryAudioFactory: { variant in
                XCTAssertEqual(variant, .qwen06SpeechSwift4Bit)
                return canary
            }
        )
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-readiness-runner", isDirectory: true)

        let report = try await runner.prepare(
            modelURL: modelURL,
            variant: .qwen06SpeechSwift4Bit
        )

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.transcript, "ready token")
        XCTAssertEqual(factory.modelURLs, [modelURL])
        XCTAssertEqual(factory.variants, [.qwen06SpeechSwift4Bit])
        let loaded = await runtime.loadedInstallations
        let compiled = await runtime.compiledInstallations
        let canaries = await runtime.canaryInputs
        XCTAssertEqual(loaded.map(\.installedRoot), [modelURL])
        XCTAssertEqual(loaded.map(\.modelID.rawValue), ["qwen3-asr-0.6b-mlx-4bit"])
        XCTAssertEqual(compiled.map(\.installedRoot), [modelURL])
        XCTAssertEqual(canaries, [canary])
    }

    func testPrepareRoutesQwen17ThroughSpeechSwiftVariantMetadata() async throws {
        let runtime = CapturingReadinessRuntime(transcript: "speech swift ready")
        let factory = CapturingReadinessRuntimeFactory(runtime: runtime)
        let runner = Qwen3ModelReadinessRunner(
            runtimeFactory: factory.makeRuntime(modelURL:variant:)
        )
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-readiness-runner-speech-swift", isDirectory: true)

        let report = try await runner.prepare(
            modelURL: modelURL,
            variant: .qwen17SpeechSwift8Bit
        )

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(factory.modelURLs, [modelURL])
        XCTAssertEqual(factory.variants, [.qwen17SpeechSwift8Bit])
        let loaded = await runtime.loadedInstallations
        XCTAssertEqual(loaded.map(\.modelID.rawValue), ["qwen3-asr-1.7b-mlx-8bit"])
    }
}

private final class CapturingReadinessRuntimeFactory: @unchecked Sendable {
    private let runtime: CapturingReadinessRuntime
    private(set) var modelURLs: [URL] = []
    private(set) var variants: [Qwen3ModelVariant] = []

    init(runtime: CapturingReadinessRuntime) {
        self.runtime = runtime
    }

    func makeRuntime(
        modelURL: URL,
        variant: Qwen3ModelVariant
    ) -> any ModelRuntimePreparing {
        modelURLs.append(modelURL)
        variants.append(variant)
        return runtime
    }
}

private actor CapturingReadinessRuntime: ModelRuntimePreparing {
    private let transcript: String
    private(set) var loadedInstallations: [ModelInstallation] = []
    private(set) var compiledInstallations: [ModelInstallation] = []
    private(set) var canaryInputs: [ModelCanaryAudio] = []

    init(transcript: String) {
        self.transcript = transcript
    }

    func load(installation: ModelInstallation) async throws {
        loadedInstallations.append(installation)
    }

    func compile(installation: ModelInstallation) async throws {
        compiledInstallations.append(installation)
    }

    func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        canaryInputs.append(audio)
        return transcript
    }
}
