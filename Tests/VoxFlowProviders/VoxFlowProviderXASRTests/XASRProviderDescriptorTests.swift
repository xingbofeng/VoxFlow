import VoxFlowASRCore
@testable import VoxFlowProviderXASR
import XCTest

final class XASRDescriptorTests: XCTestCase {
    func testDescriptorDeclaresNativeStreamingAndChineseEnglishInput() {
        let descriptor = XASRProviderDescriptor.descriptor(modelInstallationState: .ready)
        XCTAssertEqual(descriptor.id.rawValue, "xasr")
        XCTAssertEqual(descriptor.displayName, "X-ASR-zh-en")
        XCTAssertEqual(descriptor.streamingSemantics, .nativeStreaming)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "en-US"])
        XCTAssertEqual(descriptor.timeoutPolicy, .standard)
    }

    func testDescriptorPreservesSuppliedInstallationState() {
        let states: [ASRModelInstallationState] = [.notInstalled, .downloading(progress: 0.5), .verifying, .prewarming, .ready, .corrupt]
        for state in states {
            XCTAssertEqual(XASRProviderDescriptor.descriptor(modelInstallationState: state).modelInstallationState, state)
        }
    }
}
