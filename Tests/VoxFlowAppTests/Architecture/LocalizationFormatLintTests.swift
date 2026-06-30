import XCTest
@testable import VoxFlowApp

final class LocalizationFormatLintTests: XCTestCase {
    func testUnsafeLocalizedStringFormatIsRejected() {
        let source = #"Text(String(format: L10n.localize("smart.config.discovered_format", comment: ""), count))"#

        let violations = LocalizationFormatLint.violations(in: source)

        XCTAssertEqual(violations.count, 1)
    }

    func testGeneratedTypedLocalizationFormatIsAllowed() {
        let source = #"Text(L10n.Localizable.Smart.Config.discoveredFormat(count))"#

        XCTAssertTrue(LocalizationFormatLint.violations(in: source).isEmpty)
    }
}
