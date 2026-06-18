import CoreGraphics
import XCTest
@testable import VoxFlowApp

final class PasteLastResultHotKeyTests: XCTestCase {
    func testCommandShiftVMatchesPasteLastResultShortcut() {
        XCTAssertTrue(
            PasteLastResultShortcut.matches(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift]
            )
        )
    }

    func testShortcutIgnoresPlainVCommandVAndControlShiftV() {
        XCTAssertFalse(
            PasteLastResultShortcut.matches(
                keyCode: 0x09,
                flags: []
            )
        )
        XCTAssertFalse(
            PasteLastResultShortcut.matches(
                keyCode: 0x09,
                flags: [.maskCommand]
            )
        )
        XCTAssertFalse(
            PasteLastResultShortcut.matches(
                keyCode: 0x09,
                flags: [.maskControl, .maskShift]
            )
        )
    }
}
