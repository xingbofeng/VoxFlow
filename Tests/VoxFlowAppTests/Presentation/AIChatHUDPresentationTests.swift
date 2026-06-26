import XCTest
@testable import VoxFlowApp

final class AIChatHUDPresentationTests: XCTestCase {
    func testAIChatPanelReusesTextResultPanelControllerWithAIChatContent() throws {
        let source = try Self.source(
            "Sources/VoxFlowApp/Presentation/AIChatPanelController.swift"
        )

        XCTAssertTrue(source.contains("TextResultPanelController(title: \"问 AI\")"))
        XCTAssertTrue(source.contains("AIChatPanelView("))
        XCTAssertTrue(source.contains("panelController.present("))
        XCTAssertTrue(source.contains("viewModel.send(prompt)"))
    }

    func testAppDelegateRoutesAskAIIntoAIChatPanelController() throws {
        let source = try Self.source("Sources/VoxFlowApp/App/AppDelegate.swift")

        XCTAssertTrue(source.contains("private lazy var aiChatPanelController = AIChatPanelController()"))
        XCTAssertTrue(source.contains("aiChatPanelController.present(viewModel: aiChatViewModel, prompt: prompt)"))
        XCTAssertFalse(source.contains("overlayController.showAIChat(viewModel: aiChatViewModel, prompt: prompt)"))
    }

    func testOverlayNoLongerOwnsAIChatPresentationState() throws {
        let source = try Self.source(
            "Sources/VoxFlowApp/Presentation/OverlayWindowController.swift"
        )

        XCTAssertFalse(source.contains("showAIChat"))
        XCTAssertFalse(source.contains("hideAIChat"))
        XCTAssertFalse(source.contains("aiChatHostingView"))
        XCTAssertFalse(source.contains("aiChatActive"))
    }

    func testAIChatPanelAutoScrollsAndUsesChatMessageLayout() throws {
        let source = try Self.source("Sources/VoxFlowApp/AIChat/AIChatHUDView.swift")

        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("AIChatPanelConstants.bottomAnchorID"))
        XCTAssertTrue(source.contains("scrollToBottom"))
        XCTAssertTrue(source.contains("onChange(of: viewModel.messages.last?.content)"))
        XCTAssertTrue(source.contains("AIChatMessageBubble"))
        XCTAssertTrue(source.contains("AIChatRoleBadge"))
    }

    func testAIChatPanelShowsCopyActionAndStreamingStopButton() throws {
        let source = try Self.source("Sources/VoxFlowApp/AIChat/AIChatHUDView.swift")

        XCTAssertTrue(source.contains("Label(\"复制回复\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(source.contains("copyToPasteboard(message.content)"))
        XCTAssertTrue(source.contains("viewModel.isStreaming ? \"stop.circle.fill\" : \"arrow.up.circle.fill\""))
        XCTAssertTrue(source.contains("if viewModel.isStreaming"))
        XCTAssertTrue(source.contains("viewModel.stop()"))
    }

    private static func source(_ relativePath: String) throws -> String {
        let url = try repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "AIChatHUDPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
