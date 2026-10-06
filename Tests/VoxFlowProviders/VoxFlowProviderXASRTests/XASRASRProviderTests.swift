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
        // 预检按架构→系统→内存顺序判定；注入可用环境，让本用例只隔离安装状态分支，
        // 不依赖宿主机硬件（CI runner 仅 7 GiB 物理 内存）。
        let provider = XASRASRProvider(
            descriptor: XASRProviderDescriptor.descriptor(modelInstallationState: .notInstalled),
            modelURL: nil,
            environment: .init(architecture: .arm64, physicalMemoryBytes: 48 * 1_024 * 1_024 * 1_024, macOSMajorVersion: 15)
        )
        guard case .unhealthy(let error) = await provider.healthCheck() else { return XCTFail("missing model was accepted") }
        XCTAssertEqual(error.category, .modelNotInstalled)
    }
}
