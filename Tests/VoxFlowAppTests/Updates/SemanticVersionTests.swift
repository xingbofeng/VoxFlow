import XCTest
@testable import VoxFlowApp

final class SemanticVersionTests: XCTestCase {
    func testPatchComparisonTreatsTenAsGreaterThanTwo() throws {
        let newer = try XCTUnwrap(SemanticVersion("1.6.10"))
        let older = try XCTUnwrap(SemanticVersion("1.6.2"))

        XCTAssertGreaterThan(newer, older)
    }

    func testLeadingVIsIgnored() throws {
        let newer = try XCTUnwrap(SemanticVersion("v1.7.0"))
        let older = try XCTUnwrap(SemanticVersion("1.6.9"))

        XCTAssertGreaterThan(newer, older)
    }

    func testEquivalentWithAndWithoutLeadingV() throws {
        XCTAssertEqual(SemanticVersion("1.6.1"), SemanticVersion("v1.6.1"))
    }

    func testInvalidVersionReturnsNil() {
        XCTAssertNil(SemanticVersion("1.6"))
        XCTAssertNil(SemanticVersion("1.6.beta"))
        XCTAssertNil(SemanticVersion(""))
    }
}
