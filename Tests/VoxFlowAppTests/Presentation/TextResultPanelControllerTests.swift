import AppKit
import SwiftUI
import XCTest
@testable import VoxFlowApp

@MainActor
final class TextResultPanelControllerTests: XCTestCase {
    func testReusedPanelResizesFromThumbnailToExpandedContentBeforePlacement() {
        let controller = TextResultPanelController(title: "TextResultPanelControllerTests")
        defer { controller.close() }

        controller.present(
            rootView: Color.clear.frame(width: 260, height: 150),
            contentSize: NSSize(width: 260, height: 150),
            placement: .bottomTrailing(bottomMargin: 28),
            onCancel: {}
        )

        guard let thumbnailWindow = NSApp.windows
            .compactMap({ $0 as? TextResultPanel })
            .first(where: { $0.title == "TextResultPanelControllerTests" }) else {
            XCTFail("Expected thumbnail panel window")
            return
        }
        XCTAssertEqual(thumbnailWindow.frame.size.width, 260, accuracy: 1)
        XCTAssertEqual(thumbnailWindow.frame.size.height, 150, accuracy: 1)

        controller.present(
            rootView: Color.clear.frame(width: 440, height: 560),
            contentSize: NSSize(width: 440, height: 560),
            accessoryView: NSView(),
            onCancel: {}
        )

        XCTAssertEqual(thumbnailWindow.frame.size.width, 440, accuracy: 1)
        XCTAssertEqual(thumbnailWindow.frame.size.height, 560, accuracy: 1)
    }
}
