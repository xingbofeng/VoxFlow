import XCTest
import VoxFlowDomain

final class VoxFlowDomainVoiceActionTests: XCTestCase {
    func testVoiceActionIsAvailableFromDomainTarget() throws {
        XCTAssertEqual(VoiceAction.allCases, [.dictation, .agentCompose, .agentDispatch])
        XCTAssertEqual(VoiceAction.dictation.rawValue, "dictation")
        XCTAssertEqual(VoiceAction.agentCompose.rawValue, "agentCompose")
        XCTAssertEqual(VoiceAction.agentDispatch.rawValue, "agentDispatch")

        let encoded = try JSONEncoder().encode(VoiceAction.agentDispatch)
        let decoded = try JSONDecoder().decode(VoiceAction.self, from: encoded)

        XCTAssertEqual(decoded, .agentDispatch)
    }
}
