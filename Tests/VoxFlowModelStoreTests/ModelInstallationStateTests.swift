import XCTest
import VoxFlowModelStore

final class ModelInstallationStateTests: XCTestCase {
    func testLifecycleStateDistinguishesAllRequiredDownloadAndRuntimePhases() {
        let progress = ModelDownloadProgress(
            bytesWritten: 512,
            totalBytes: 1_024,
            componentID: ModelComponentID(rawValue: "encoder")
        )
        let readyInstallation = ModelInstallation(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
            version: "2026.06.01",
            installedRoot: URL(fileURLWithPath: "/tmp/Models/qwen3-asr-0.6b")
        )

        let states: [ModelInstallationState] = [
            .notInstalled,
            .insufficientDisk(requiredBytes: 2_048, availableBytes: 1_024),
            .downloading(progress: progress),
            .paused(progress: progress),
            .verifying,
            .extracting,
            .compiling,
            .warmingUp,
            .canaryTesting,
            .deleting(readyInstallation),
            .ready(readyInstallation),
            .corrupt(reason: "sha256 mismatch"),
            .runtimeUnsupported(reason: "runtime missing"),
            .hardwareUnsupported(reason: "requires Neural Engine"),
            .failed(message: "network offline"),
        ]

        XCTAssertEqual(states.count, 15)
        XCTAssertTrue(ModelInstallationState.ready(readyInstallation).isReady)
        XCTAssertFalse(ModelInstallationState.deleting(readyInstallation).isReady)
        XCTAssertFalse(ModelInstallationState.canaryTesting.isReady)
        XCTAssertTrue(ModelInstallationState.runtimeUnsupported(reason: "macOS").isUnsupported)
        XCTAssertTrue(ModelInstallationState.hardwareUnsupported(reason: "RAM").isUnsupported)
        XCTAssertFalse(ModelInstallationState.failed(message: "checksum").isUnsupported)
    }

    func testDownloadProgressReportsFractionAndUnknownTotal() {
        let known = ModelDownloadProgress(
            bytesWritten: 256,
            totalBytes: 1_024,
            componentID: ModelComponentID(rawValue: "decoder")
        )
        let unknown = ModelDownloadProgress(
            bytesWritten: 256,
            totalBytes: nil,
            componentID: ModelComponentID(rawValue: "decoder")
        )

        XCTAssertEqual(known.fractionCompleted, 0.25)
        XCTAssertNil(unknown.fractionCompleted)
    }
}
