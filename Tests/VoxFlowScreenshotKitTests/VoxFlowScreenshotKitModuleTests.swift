import XCTest
@testable import VoxFlowScreenshotKit

final class VoxFlowScreenshotKitModuleTests: XCTestCase {
    func testModuleExposesInteractiveScreenshotProviderProtocol() {
        XCTAssertEqual(
            String(describing: InteractiveScreenshotProviding.self),
            "InteractiveScreenshotProviding"
        )
    }
}
