import XCTest
import VoxFlowDomain

final class VoxFlowDomainProductBrandTests: XCTestCase {
    func testProductBrandIsAvailableFromDomainTarget() {
        XCTAssertEqual(ProductBrand.englishName, "VoxFlow")
        XCTAssertEqual(ProductBrand.chineseDisplayName, "随声写")
        XCTAssertEqual(ProductBrand.bundleIdentifier, "com.voxflow.app")
        XCTAssertEqual(ProductBrand.legacyBundleIdentifier, "com.voiceinput.app")
    }
}
