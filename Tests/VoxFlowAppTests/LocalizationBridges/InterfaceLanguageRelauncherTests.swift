import XCTest
@testable import VoxFlowApp

final class InterfaceLanguageRelauncherTests: XCTestCase {
    func testRelaunchCommandWaitsForCurrentProcessBeforeOpeningNewInstance() {
        let command = InterfaceLanguageRelauncher.shellCommand(
            bundlePath: "/tmp/Vox Flow Dev.app",
            currentProcessIdentifier: 12345
        )

        XCTAssertTrue(command.contains("while /bin/kill -0 12345"))
        XCTAssertTrue(command.contains("/usr/bin/open -n '/tmp/Vox Flow Dev.app'"))
        XCTAssertTrue(command.contains("sleep 0.1"))
    }
}
