import XCTest
import VoxFlowDomain

final class VoxFlowDomainProductBrandTests: XCTestCase {
    func testProductBrandIsAvailableFromDomainTarget() {
        let preferredLocale = Bundle.main.preferredLocalizations.first ?? "en"
        let expectedDisplayName = preferredLocale.lowercased().hasPrefix("zh")
            ? Bundle.main.localizedString(forKey: "product.brand.chinese_display_name", value: "码上写", table: "Localizable")
            : ProductBrand.englishName

        XCTAssertEqual(ProductBrand.englishName, Bundle.main.localizedString(forKey: "product.brand.english_name", value: "VoxFlow", table: "Localizable"))
        XCTAssertEqual(ProductBrand.chineseDisplayName, Bundle.main.localizedString(forKey: "product.brand.chinese_display_name", value: "码上写", table: "Localizable"))
        XCTAssertEqual(ProductBrand.displayName, expectedDisplayName)
        XCTAssertEqual(ProductBrand.bundleIdentifier, "com.voxflow.app")
    }
}
