import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteKeyEventTextInputGuardTests: XCTestCase {
    func testReturnDefersToMarkedTextInput() {
        XCTAssertTrue(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 36, firstResponder: FakeMarkedTextProvider(marked: true)))
        XCTAssertTrue(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 76, firstResponder: FakeMarkedTextProvider(marked: true)))
    }

    func testNavigationKeysDeferToMarkedTextInput() {
        XCTAssertTrue(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 125, firstResponder: FakeMarkedTextProvider(marked: true)))
        XCTAssertTrue(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 126, firstResponder: FakeMarkedTextProvider(marked: true)))
        XCTAssertTrue(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 53, firstResponder: FakeMarkedTextProvider(marked: true)))
    }

    func testPaletteShortcutsContinueWhenNoMarkedTextExists() {
        XCTAssertFalse(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 36, firstResponder: FakeMarkedTextProvider(marked: false)))
        XCTAssertFalse(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 36, firstResponder: nil))
        XCTAssertFalse(PaletteKeyEventTextInputGuard.shouldDeferToMarkedText(keyCode: 0, firstResponder: FakeMarkedTextProvider(marked: true)))
    }
}

@MainActor
private final class FakeMarkedTextProvider: PaletteMarkedTextProviding {
    private let marked: Bool

    init(marked: Bool) {
        self.marked = marked
    }

    func hasMarkedText() -> Bool {
        marked
    }
}
