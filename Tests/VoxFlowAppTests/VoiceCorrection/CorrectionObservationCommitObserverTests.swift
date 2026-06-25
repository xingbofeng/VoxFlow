import AppKit
import Carbon.HIToolbox
import XCTest
@testable import VoxFlowApp

final class CorrectionObservationCommitObserverTests: XCTestCase {
    func testReturnAndTabKeysMapToCommitSignals() {
        XCTAssertEqual(
            CorrectionObservationKeyCommitMapper.signal(forKeyCode: UInt16(kVK_Return)),
            .returnKey
        )
        XCTAssertEqual(
            CorrectionObservationKeyCommitMapper.signal(forKeyCode: UInt16(kVK_ANSI_KeypadEnter)),
            .returnKey
        )
        XCTAssertEqual(
            CorrectionObservationKeyCommitMapper.signal(forKeyCode: UInt16(kVK_Tab)),
            .tabKey
        )
    }

    func testOtherKeysDoNotMapToCommitSignals() {
        XCTAssertNil(CorrectionObservationKeyCommitMapper.signal(forKeyCode: 0))
    }
}
