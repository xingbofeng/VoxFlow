import XCTest
import VoxFlowDomain

final class VoxFlowDomainTextInputModeTests: XCTestCase {
    func testTextInputModesAreStableDomainContract() throws {
        XCTAssertEqual(TextInputMode.automatic.rawValue, "automatic")
        XCTAssertEqual(TextInputMode.fastPaste.rawValue, "fastPaste")
        XCTAssertEqual(TextInputMode.simulatedTyping.rawValue, "simulatedTyping")
        XCTAssertEqual(TextInputMode.allCases, [.automatic, .fastPaste, .simulatedTyping])

        let data = try JSONEncoder().encode(TextInputMode.simulatedTyping)
        let decoded = try JSONDecoder().decode(TextInputMode.self, from: data)

        XCTAssertEqual(decoded, .simulatedTyping)
    }
}
