import VoxFlowASRCore
import VoxFlowModelStore
@testable import VoxFlowProviderXASR
import XCTest

final class XASRPreflightTests: XCTestCase {
    private let minimum: UInt64 = 8 * 1_024 * 1_024 * 1_024

    func testIntelOrRosettaIsBlockedBeforeOtherHardwareChecks() {
        let result = XASRRuntimePreflight.evaluate(environment: .init(architecture: .x86_64, physicalMemoryBytes: 0, macOSMajorVersion: 14))
        XCTAssertEqual(result, .blocked(.architectureUnsupported(required: [.arm64], actual: .x86_64)))
        XCTAssertFalse(result.isUsable)
        XCTAssertEqual(XASRPreflightBlocker.architectureUnsupported(required: [.arm64], actual: .x86_64).asrErrorCategory, .runtimeUnsupported)
    }

    func testOldOSIsBlockedBeforeMemoryCheck() {
        XCTAssertEqual(XASRRuntimePreflight.evaluate(environment: .init(architecture: .arm64, physicalMemoryBytes: 0, macOSMajorVersion: 14)),
            .blocked(.operatingSystemTooOld(requiredMajorVersion: 15, actualMajorVersion: 14)))
        XCTAssertEqual(XASRPreflightBlocker.operatingSystemTooOld(requiredMajorVersion: 15, actualMajorVersion: 14).asrErrorCategory, .runtimeUnsupported)
    }

    func testMemoryBelowEightGiBIsAHardBlocker() {
        XCTAssertEqual(XASRRuntimePreflight.evaluate(environment: .init(architecture: .arm64, physicalMemoryBytes: minimum - 1, macOSMajorVersion: 15)),
            .blocked(.insufficientMemory(requiredBytes: minimum, actualBytes: minimum - 1)))
        XCTAssertEqual(XASRPreflightBlocker.insufficientMemory(requiredBytes: minimum, actualBytes: minimum - 1).asrErrorCategory, .hardwareUnsupported)
    }

    func testBoundaryAndNewerSupportedEnvironmentsAreUsable() {
        for majorVersion in [15, 26] {
            XCTAssertTrue(XASRRuntimePreflight.evaluate(environment: .init(architecture: .arm64, physicalMemoryBytes: minimum, macOSMajorVersion: majorVersion)).isUsable)
        }
        XCTAssertEqual(XASRRuntimePreflight.requiredMemoryBytes, UInt64(XASRManifestCatalog.minimumMemoryBytes))
        XCTAssertEqual(XASRRuntimePreflight.supportedArchitectures, XASRManifestCatalog.supportedArchitectures)
    }
}
