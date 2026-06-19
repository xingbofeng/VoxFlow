import XCTest

final class WindowPresentationChoreographyTests: XCTestCase {
    func testMainWindowDoesNotUseVisiblePostShowCorrection() throws {
        let coordinatorSource = try projectFile(
            "Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"
        )
        let mainWindowSource = try projectFile(
            "Sources/VoxFlowApp/Presentation/MainWindowController.swift"
        )

        XCTAssertFalse(
            coordinatorSource.contains("Task { @MainActor"),
            "Do not schedule a visible post-show repair for the main window; first launch must stay hidden until the final centered frame."
        )
        XCTAssertFalse(
            mainWindowSource.contains("windowDidBecomeKey"),
            "Do not correct the first main-window position from windowDidBecomeKey; that callback runs after the user can see the window."
        )
    }

    func testMainWindowCentersBeforeItIsShown() throws {
        let coordinatorSource = try projectFile(
            "Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"
        )

        let activateRange = try XCTUnwrap(
            coordinatorSource.range(of: "NSApp.activate(ignoringOtherApps: true)")
        )
        let centerRange = try XCTUnwrap(
            coordinatorSource.range(of: "WindowPlacementPolicy.centerOnMainScreen(window)")
        )
        let showRange = try XCTUnwrap(
            coordinatorSource.range(of: "window.makeKeyAndOrderFront(nil)")
        )
        let visibleRepairRange = try XCTUnwrap(
            coordinatorSource.range(of: "WindowPlacementPolicy.placeOnVisibleScreenIfNeeded(window)", options: .backwards)
        )
        let postOrderCenterRange = try XCTUnwrap(
            coordinatorSource.range(of: "WindowPlacementPolicy.centerOnMainScreen(window)", options: .backwards)
        )

        XCTAssertLessThan(
            activateRange.lowerBound,
            centerRange.lowerBound,
            "Activate the app before centering so AppKit cannot reposition a hidden main window after placement."
        )
        XCTAssertLessThan(
            centerRange.lowerBound,
            showRange.lowerBound,
            "The first ordered frame should be centered before makeKeyAndOrderFront, before AppKit performs any first-order adjustment."
        )
        XCTAssertLessThan(
            showRange.lowerBound,
            visibleRepairRange.lowerBound,
            "Reused windows may only be repaired with visible-screen clamping after ordering."
        )
        XCTAssertLessThan(
            showRange.lowerBound,
            postOrderCenterRange.lowerBound,
            "The first ordered workbench window must be centered again after AppKit's first-order placement, before it is revealed."
        )
    }

    func testInitialMainWindowContentSizeMatchesShellMinimumSize() throws {
        let mainWindowSource = try projectFile(
            "Sources/VoxFlowApp/Presentation/MainWindowController.swift"
        )
        let shellSource = try projectFile(
            "Sources/VoxFlowApp/Views/MainShellView.swift"
        )

        XCTAssertTrue(
            mainWindowSource.contains("width: 1_260, height: 720"),
            "Centering must use the shell's final minimum content size before the window is shown."
        )
        XCTAssertTrue(
            shellSource.contains(".frame(minWidth: 1_260, minHeight: 720)"),
            "Keep this in sync with MainWindowController's initial contentRect."
        )
    }

    func testFirstOrderedMainWindowStaysHiddenUntilFinalCenteredFrame() throws {
        let coordinatorSource = try projectFile(
            "Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"
        )

        let hideRange = try XCTUnwrap(
            coordinatorSource.range(of: "window.alphaValue = 0")
        )
        let showRange = try XCTUnwrap(
            coordinatorSource.range(of: "window.makeKeyAndOrderFront(nil)")
        )
        let deferredRange = try XCTUnwrap(
            coordinatorSource.range(of: "DispatchQueue.main.async")
        )
        let revealRange = try XCTUnwrap(
            coordinatorSource.range(of: "window.alphaValue = 1")
        )

        XCTAssertLessThan(
            hideRange.lowerBound,
            showRange.lowerBound,
            "The first ordered window must be transparent before AppKit gets a chance to place it."
        )
        XCTAssertLessThan(
            showRange.lowerBound,
            deferredRange.lowerBound,
            "Final centering should run after AppKit's first-order placement."
        )
        XCTAssertLessThan(
            deferredRange.lowerBound,
            revealRange.lowerBound,
            "Reveal the window only after the deferred final centering."
        )
    }

    private func projectFile(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
