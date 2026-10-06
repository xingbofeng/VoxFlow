import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
import XCTest
@testable import VoxFlowProviderXASR

final class XASRASRProviderTests: XCTestCase, @unchecked Sendable {
    func testUnsupportedArchitectureOverridesStoredReadyState() async {
        let provider = XASRASRProvider(
            descriptor: XASRProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/xasr-ready"),
            environment: .init(architecture: .x86_64, physicalMemoryBytes: 48 * 1_024 * 1_024 * 1_024, macOSMajorVersion: 15)
        )
        guard case .unhealthy(let error) = await provider.healthCheck() else { return XCTFail("Intel was accepted") }
        XCTAssertEqual(error.category, .runtimeUnsupported)
    }

    func testNotInstalledProviderFailsBeforeCreatingStream() async {
        let provider = XASRASRProvider(descriptor: XASRProviderDescriptor.descriptor(modelInstallationState: .notInstalled), modelURL: nil)
        guard case .unhealthy(let error) = await provider.healthCheck() else { return XCTFail("missing model was accepted") }
        XCTAssertEqual(error.category, .modelNotInstalled)
    }
}
