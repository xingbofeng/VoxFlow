import XCTest
@testable import VoiceInputApp

final class AppDelegateEventRoutingTests: XCTestCase {
    func testEscapeKeyRoutingMatchesMacEscapeKeyCode() {
        XCTAssertTrue(EscapeEventRouting.isEscapeKey(53))
        XCTAssertFalse(EscapeEventRouting.isEscapeKey(36))
    }
}
