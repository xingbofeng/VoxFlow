import XCTest
import VoxFlowDomain

final class VoxFlowDomainContextSnapshotTests: XCTestCase {
    func testContextSnapshotIsAvailableFromDomainTarget() {
        let snapshot = ContextSnapshot(
            windowTitle: "Editor",
            targetAppBundleID: "com.example.editor",
            targetAppName: "Example Editor",
            visibleText: String(repeating: "a", count: 30),
            selectedText: String(repeating: "b", count: 10),
            inputAreaText: String(repeating: "c", count: 15),
            visualContentAvailable: true,
            sources: [.windowMetadata, .accessibilityVisibleText],
            trimmedLength: 55,
            warnings: ["truncated"]
        )

        XCTAssertEqual(snapshot.totalTextLength, 55)
        XCTAssertTrue(snapshot.hasAccessibilityContent)
        XCTAssertEqual(snapshot.sources, [.windowMetadata, .accessibilityVisibleText])
        XCTAssertEqual(snapshot.warnings, ["truncated"])
    }

    func testContextSnapshotCodableRoundTrip() throws {
        let snapshot = ContextSnapshot(
            targetAppName: "Terminal",
            selectedText: "swift test",
            sources: [.accessibilitySelectedText],
            trimmedLength: 10
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ContextSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
