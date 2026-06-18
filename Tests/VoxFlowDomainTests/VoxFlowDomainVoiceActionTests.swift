import XCTest
import VoxFlowDomain

final class VoxFlowDomainVoiceActionTests: XCTestCase {
    func testVoiceActionIsAvailableFromDomainTarget() throws {
        XCTAssertEqual(VoiceAction.allCases, [.dictation, .agentCompose])
        XCTAssertEqual(VoiceAction.dictation.rawValue, "dictation")
        XCTAssertEqual(VoiceAction.agentCompose.rawValue, "agentCompose")

        let encoded = try JSONEncoder().encode(VoiceAction.agentCompose)
        let decoded = try JSONDecoder().decode(VoiceAction.self, from: encoded)

        XCTAssertEqual(decoded, .agentCompose)
    }
}
