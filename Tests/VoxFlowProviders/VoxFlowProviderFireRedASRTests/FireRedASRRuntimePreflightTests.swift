import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRRuntimePreflightTests: XCTestCase {
    private func environment(
        memory: UInt64 = FireRedASRRuntimePreflight.requiredMemoryBytes,
        macOSMajorVersion: Int = FireRedASRRuntimePreflight.requiredMacOSMajorVersion,
        architecture: ModelArchitecture = .arm64
    ) -> FireRedASRRuntimePreflight.Environment {
        FireRedASRRuntimePreflight.Environment(
            architecture: architecture,
            physicalMemoryBytes: memory,
            macOSMajorVersion: macOSMajorVersion
        )
    }

    func testUsableWhenEveryGateIsMet() {
        let outcome = FireRedASRRuntimePreflight.evaluate(environment: environment())

        XCTAssertEqual(outcome, .usable)
        XCTAssertTrue(outcome.isUsable)
    }

    func testSixteenGigabytesIsExactlyEnoughAndFifteenIsNot() {
        XCTAssertEqual(
            FireRedASRRuntimePreflight.evaluate(
                environment: environment(memory: 16 * 1_024 * 1_024 * 1_024)
            ),
            .usable
        )

        let blocked = FireRedASRRuntimePreflight.evaluate(
            environment: environment(memory: 15 * 1_024 * 1_024 * 1_024)
        )
        XCTAssertFalse(blocked.isUsable)
        XCTAssertEqual(
            blocked,
            .blocked(
                .insufficientMemory(
                    requiredBytes: 16 * 1_024 * 1_024 * 1_024,
                    actualBytes: 15 * 1_024 * 1_024 * 1_024
                )
            )
        )
    }

    func testUnsatisfiedMemoryIsReportedAsStructuredDataNotFreeText() {
        guard case .blocked(.insufficientMemory(let requiredBytes, _)) =
            FireRedASRRuntimePreflight.evaluate(environment: environment(memory: 8 * 1_024 * 1_024 * 1_024))
        else {
            return XCTFail("expected insufficientMemory")
        }

        // 门槛必须与清单同源，不能两处各写一份。
        XCTAssertEqual(requiredBytes, UInt64(FireRedASRManifestCatalog.minimumMemoryBytes))
    }

    func testOldOperatingSystemAndUnsupportedArchitectureAreBlockers() {
        XCTAssertEqual(
            FireRedASRRuntimePreflight.evaluate(
                environment: environment(
                    macOSMajorVersion: FireRedASRRuntimePreflight.requiredMacOSMajorVersion - 1
                )
            ),
            .blocked(
                .operatingSystemTooOld(
                    requiredMajorVersion: FireRedASRRuntimePreflight.requiredMacOSMajorVersion,
                    actualMajorVersion: FireRedASRRuntimePreflight.requiredMacOSMajorVersion - 1
                )
            )
        )
    }

    func testBothSupportedArchitecturesPassTheArchitectureGate() {
        for architecture in FireRedASRRuntimePreflight.supportedArchitectures {
            XCTAssertEqual(
                FireRedASRRuntimePreflight.evaluate(environment: environment(architecture: architecture)),
                .usable,
                "\(architecture.rawValue) 应当被支持"
            )
        }
        XCTAssertEqual(FireRedASRRuntimePreflight.supportedArchitectures.sorted { $0.rawValue < $1.rawValue },
                       [.arm64, .x86_64])
    }

    func testBlockerCategoriesFeedTheSharedErrorVocabulary() {
        // App 层按 category 出文案；这里保证「内存」与「架构/系统」不会被归成同一类。
        XCTAssertEqual(
            FireRedASRPreflightBlocker.insufficientMemory(requiredBytes: 1, actualBytes: 0).asrErrorCategory,
            .hardwareUnsupported
        )
        XCTAssertEqual(
            FireRedASRPreflightBlocker
                .operatingSystemTooOld(requiredMajorVersion: 15, actualMajorVersion: 14)
                .asrErrorCategory,
            .runtimeUnsupported
        )
        XCTAssertEqual(
            FireRedASRPreflightBlocker
                .architectureUnsupported(required: [.arm64], actual: .x86_64)
                .asrErrorCategory,
            .runtimeUnsupported
        )
    }

    func testBlockerDescriptionsStayDiagnosticNotUserFacing() {
        // 这些字符串只进日志；不能出现面向用户的中文文案，否则 Provider 会越过 L10n 出文案。
        let descriptions = [
            FireRedASRPreflightBlocker.insufficientMemory(requiredBytes: 100, actualBytes: 1).description,
            FireRedASRPreflightBlocker
                .operatingSystemTooOld(requiredMajorVersion: 15, actualMajorVersion: 14).description,
            FireRedASRPreflightBlocker
                .architectureUnsupported(required: [.arm64], actual: .x86_64).description,
        ]

        for description in descriptions {
            XCTAssertFalse(
                description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) },
                "\(description) 含 CJK，应由 App 层出文案"
            )
        }
    }
}
