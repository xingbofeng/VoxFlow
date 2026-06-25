import XCTest
@testable import VoxFlowApp

@MainActor
final class CapsLockRecordingIndicatorTests: XCTestCase {
    func testSetActiveCapturesCurrentStateAndRestoresItWhenInactive() {
        var capsLockState = false
        var writtenStates: [Bool] = []
        let indicator = CapsLockRecordingIndicator(
            readCapsLockState: { capsLockState },
            writeCapsLockState: { state in
                capsLockState = state
                writtenStates.append(state)
                return true
            }
        )

        indicator.setActive(true)
        indicator.setActive(false)

        XCTAssertEqual(writtenStates, [true, false])
        XCTAssertFalse(capsLockState)
    }

    func testSetActiveRestoresOriginallyEnabledState() {
        var capsLockState = true
        var writtenStates: [Bool] = []
        let indicator = CapsLockRecordingIndicator(
            readCapsLockState: { capsLockState },
            writeCapsLockState: { state in
                capsLockState = state
                writtenStates.append(state)
                return true
            }
        )

        indicator.setActive(true)
        indicator.setActive(false)

        XCTAssertEqual(writtenStates, [true, true])
        XCTAssertTrue(capsLockState)
    }

    func testSetActiveDoesNotWriteWhenCurrentStateCannotBeRead() {
        var writtenStates: [Bool] = []
        let indicator = CapsLockRecordingIndicator(
            readCapsLockState: { nil },
            writeCapsLockState: { state in
                writtenStates.append(state)
                return true
            }
        )

        indicator.setActive(true)
        indicator.setActive(false)

        XCTAssertTrue(writtenStates.isEmpty)
    }
}
