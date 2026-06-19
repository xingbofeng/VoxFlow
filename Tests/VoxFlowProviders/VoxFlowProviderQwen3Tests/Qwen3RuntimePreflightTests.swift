@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3RuntimePreflightTests: XCTestCase {
    func testRuntimePlansUseSpeechSwiftForBothModelSizes() {
        let qwen06 = Qwen3RuntimePlan.plan(for: .qwen06SpeechSwift4Bit)
        let qwen17 = Qwen3RuntimePlan.plan(for: .qwen17SpeechSwift8Bit)

        XCTAssertEqual(
            qwen06.route,
            .speechSwiftQwen3ASR(modelID: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
        )
        XCTAssertEqual(qwen06.minimumMemoryBytes, 8 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(
            qwen17.route,
            .speechSwiftQwen3ASR(modelID: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit")
        )
        XCTAssertEqual(qwen17.minimumMemoryBytes, 16 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(qwen17.supportedArchitectures, [.arm64])
    }

    func testQwen17PreflightFailsWhenMemoryIsTooSmall() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17SpeechSwift8Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .arm64,
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024
            )
        )

        XCTAssertEqual(
            result,
            .hardwareUnsupported(reason: "Qwen3-ASR 1.7B 至少需要 16GB 内存。")
        )
    }

    func testQwen17PreflightPassesOnSupportedAppleSiliconHardware() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17SpeechSwift8Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .arm64,
                physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024
            )
        )

        XCTAssertEqual(result, .supported)
    }

    func testQwen17PreflightFailsOnIntel() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17SpeechSwift8Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .x86_64,
                physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024
            )
        )

        XCTAssertEqual(
            result,
            .hardwareUnsupported(reason: "Qwen3-ASR 1.7B 不支持当前架构。")
        )
    }
}
