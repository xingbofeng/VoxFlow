import VoxFlowASRCore
import VoxFlowModelStore
@testable import VoxFlowProviderR2T2
import XCTest

final class R2T2RuntimePreflightTests: XCTestCase {
    private let gibibyte: UInt64 = 1_024 * 1_024 * 1_024

    private func environment(
        architecture: ModelArchitecture = .arm64,
        memory: UInt64 = 32 * 1_024 * 1_024 * 1_024,
        macOSMajorVersion: Int = 15
    ) -> R2T2RuntimePreflight.Environment {
        R2T2RuntimePreflight.Environment(
            architecture: architecture,
            physicalMemoryBytes: memory,
            macOSMajorVersion: macOSMajorVersion
        )
    }

    func testSupportedMachineIsUsableWithoutCaveats() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(environment: environment()),
            .usable
        )
    }

    func testIntelMachineIsBlockedBecauseOnlyAppleSiliconIsSupported() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(environment: environment(architecture: .x86_64)),
            .blocked(.architectureUnsupported(required: [.arm64], actual: .x86_64))
        )
    }

    func testMacOSBelowFifteenIsBlocked() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(environment: environment(macOSMajorVersion: 14)),
            .blocked(.operatingSystemTooOld(requiredMajorVersion: 15, actualMajorVersion: 14))
        )
    }

    func testMemoryBelowAttemptFloorIsBlocked() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(environment: environment(memory: 8 * gibibyte)),
            .blocked(.insufficientMemory(requiredBytes: 16 * gibibyte, actualBytes: 8 * gibibyte))
        )
    }

    func testSixteenGigabytesIsExactlyAtTheAttemptFloor() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(environment: environment(memory: 16 * gibibyte)),
            .usableWithCaution(.memoryBelowRecommended(actualBytes: 16 * gibibyte))
        )
    }

    func testTwentyFourGigabytesIsExactlyAtTheRecommendedFloor() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(environment: environment(memory: 24 * gibibyte)),
            .usable
        )
    }

    func testUsableAndUsableWithCautionAreBothSelectableButBlockedIsNot() {
        XCTAssertTrue(R2T2RuntimePreflight.evaluate(environment: environment()).isUsable)
        XCTAssertTrue(
            R2T2RuntimePreflight.evaluate(environment: environment(memory: 16 * gibibyte)).isUsable
        )
        XCTAssertFalse(
            R2T2RuntimePreflight.evaluate(environment: environment(memory: 8 * gibibyte)).isUsable
        )
    }

    func testArchitectureIsCheckedBeforeMemorySoTheReasonIsTheRealOne() {
        XCTAssertEqual(
            R2T2RuntimePreflight.evaluate(
                environment: environment(architecture: .x86_64, memory: 4 * gibibyte)
            ),
            .blocked(.architectureUnsupported(required: [.arm64], actual: .x86_64))
        )
    }

    func testCurrentEnvironmentReportsThisMachinesRealValues() {
        let current = R2T2RuntimePreflight.Environment.current()
        let processInfo = ProcessInfo.processInfo

        XCTAssertEqual(current.physicalMemoryBytes, processInfo.physicalMemory)
        XCTAssertEqual(current.macOSMajorVersion, processInfo.operatingSystemVersion.majorVersion)
        #if arch(arm64)
        XCTAssertEqual(current.architecture, .arm64)
        #else
        XCTAssertEqual(current.architecture, .x86_64)
        #endif
    }

    func testBlockedOutcomeMapsToTheExistingASRErrorTaxonomyWithoutFreeText() {
        XCTAssertEqual(
            R2T2PreflightBlocker.architectureUnsupported(required: [.arm64], actual: .x86_64)
                .asrErrorCategory,
            .runtimeUnsupported
        )
        XCTAssertEqual(
            R2T2PreflightBlocker.operatingSystemTooOld(requiredMajorVersion: 15, actualMajorVersion: 14)
                .asrErrorCategory,
            .runtimeUnsupported
        )
        XCTAssertEqual(
            R2T2PreflightBlocker.insufficientMemory(
                requiredBytes: 16 * gibibyte,
                actualBytes: 8 * gibibyte
            ).asrErrorCategory,
            .hardwareUnsupported
        )
    }
}
