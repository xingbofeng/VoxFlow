@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3StreamingSessionFactoryProviderTests: XCTestCase {
    func testVariantFactoryRoutesCoreMLAndMLXSeparately() {
        let coreMLFactory = Qwen3StreamingSessionFactoryProvider.factory(for: .qwen06CoreMLInt8)
        let mlxFactory = Qwen3StreamingSessionFactoryProvider.factory(for: .qwen17MLX4Bit)

        XCTAssertTrue(coreMLFactory is FluidAudioQwen3StreamingSessionFactory)
        XCTAssertTrue(mlxFactory is Qwen3MLXWorkerStreamingSessionFactory)
    }
}
