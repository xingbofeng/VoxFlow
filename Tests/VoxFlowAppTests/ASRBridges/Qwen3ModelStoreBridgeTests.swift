import VoxFlowProviderQwen3
import XCTest
@testable import VoxFlowApp

final class Qwen3ModelStoreBridgeTests: XCTestCase {
    func testLiveQwenDownloaderUsesModelStoreBackedPathByDefault() {
        let downloader = Qwen3ModelDownloader.live()

        XCTAssertTrue(downloader is Qwen3ModelStoreBackedDownloader)
    }
}
