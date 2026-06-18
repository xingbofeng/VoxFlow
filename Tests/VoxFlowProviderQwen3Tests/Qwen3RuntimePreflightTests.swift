@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3RuntimePreflightTests: XCTestCase {
    func testRuntimePlansKeepCoreMLAndMLXRoutesSeparate() {
        let qwen06 = Qwen3RuntimePlan.plan(for: .qwen06CoreMLInt8)
        let qwen17 = Qwen3RuntimePlan.plan(for: .qwen17MLX4Bit)

        XCTAssertEqual(qwen06.route, .fluidAudioCoreML)
        XCTAssertEqual(qwen06.minimumMemoryBytes, 8 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(qwen17.route, .mlxWorker(executableName: "voxflow-qwen3-mlx-worker"))
        XCTAssertEqual(qwen17.minimumMemoryBytes, 16 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(qwen17.supportedArchitectures, [.arm64])
    }

    func testQwen17PreflightFailsWhenMLXWorkerIsMissing() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17MLX4Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .arm64,
                physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
                workerHealth: { _ in .missing }
            )
        )

        XCTAssertEqual(
            result,
            .runtimeUnsupported(reason: "Qwen3-ASR 1.7B 需要 MLX 本地 worker：voxflow-qwen3-mlx-worker。")
        )
    }

    func testQwen17PreflightFailsWhenMemoryIsTooSmall() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17MLX4Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .arm64,
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                workerHealth: { _ in .healthy }
            )
        )

        XCTAssertEqual(
            result,
            .hardwareUnsupported(reason: "Qwen3-ASR 1.7B 至少需要 16GB 内存。")
        )
    }

    func testQwen17PreflightPassesWhenArchitectureMemoryAndWorkerAreAvailable() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17MLX4Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .arm64,
                physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
                workerHealth: { $0 == "voxflow-qwen3-mlx-worker" ? .healthy : .missing }
            )
        )

        XCTAssertEqual(result, .supported)
    }

    func testQwen17PreflightFailsWhenWorkerHealthProbeReportsMissingMLX() {
        let result = Qwen3RuntimePreflight.evaluate(
            variant: .qwen17MLX4Bit,
            environment: Qwen3RuntimePreflight.Environment(
                architecture: .arm64,
                physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
                workerHealth: { _ in .unhealthy(reason: "mlx_lm is not installed") }
            )
        )

        XCTAssertEqual(
            result,
            .runtimeUnsupported(reason: "Qwen3-ASR 1.7B MLX worker 不可用：mlx_lm is not installed")
        )
    }
}
