import XCTest
@testable import VoxFlowApp

final class DictationStateMachineTests: XCTestCase {
    func testStateMachineAllowsExpectedCoreFlow() {
        var machine = DictationStateMachine()

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.startRecording())
        XCTAssertEqual(machine.state, .recording)
        XCTAssertTrue(machine.waitForFinalResult())
        XCTAssertEqual(machine.state, .waitingForFinal)
        XCTAssertTrue(machine.startProcessing())
        XCTAssertEqual(machine.state, .processing)
        XCTAssertTrue(machine.startInjecting())
        XCTAssertEqual(machine.state, .injecting)
        machine.finish()
        XCTAssertEqual(machine.state, .idle)
    }

    func testStateMachineRejectsInvalidTransitions() {
        var machine = DictationStateMachine()

        XCTAssertFalse(machine.waitForFinalResult())
        XCTAssertFalse(machine.startProcessing())
        XCTAssertFalse(machine.startInjecting())
        XCTAssertEqual(machine.state, .idle)

        XCTAssertTrue(machine.startRecording())
        XCTAssertFalse(machine.startInjecting())
        XCTAssertEqual(machine.state, .recording)
    }

    func testFailedStateCanBeResetToIdle() {
        var machine = DictationStateMachine()

        machine.fail(message: "boom")
        XCTAssertEqual(machine.state, .failed("boom"))

        machine.reset()
        XCTAssertEqual(machine.state, .idle)
    }
}
