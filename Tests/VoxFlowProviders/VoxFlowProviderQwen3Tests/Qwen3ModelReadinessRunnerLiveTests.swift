@testable import VoxFlowProviderQwen3
import Foundation
import XCTest

final class Qwen3ModelReadinessRunnerLiveTests: XCTestCase {
    func testConfiguredQwen17ModelPassesSpeechSwiftPrewarmAndCanary() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VOICEINPUT_TEST_QWEN3_17_READINESS"] == "1" else {
            throw XCTSkip(
                "Set VOICEINPUT_TEST_QWEN3_17_READINESS=1 and VOICEINPUT_TEST_QWEN3_MODEL_PATH to run the 1.7B readiness smoke."
            )
        }
        guard let modelPath = environment["VOICEINPUT_TEST_QWEN3_MODEL_PATH"],
              !modelPath.isEmpty else {
            throw XCTSkip("Set VOICEINPUT_TEST_QWEN3_MODEL_PATH to the Qwen3-ASR 1.7B ModelStore directory.")
        }

        let report = try await Qwen3ModelReadinessRunner().prepare(
            modelURL: URL(fileURLWithPath: modelPath, isDirectory: true),
            variant: .qwen17SpeechSwift8Bit
        )

        XCTAssertGreaterThan(report.metrics.loadTime, Duration.zero)
        XCTAssertGreaterThan(report.metrics.canaryRTF, 0)
    }
}
