import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class SelectionWindowTargetResolverTests: XCTestCase {
    func testTopmostCaptureWorthyWindowAtPointIsReturned() {
        let resolver = SelectionWindowTargetResolver(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowsInFrontToBackOrder: [
                SelectionWindowInfo(
                    id: 1,
                    frame: CGRect(x: 80, y: 90, width: 400, height: 260),
                    name: "Document",
                    ownerName: "TextEdit",
                    layer: 0
                ),
            ],
            ownWindowID: 99
        )

        let target = resolver.targetWindow(at: CGPoint(x: 120, y: 120))

        XCTAssertEqual(target?.id, 1)
        XCTAssertEqual(target?.frame, CGRect(x: 80, y: 90, width: 400, height: 260))
    }

    func testExcludedForegroundWindowPreventsFallingThroughToHiddenWindow() {
        let resolver = SelectionWindowTargetResolver(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowsInFrontToBackOrder: [
                SelectionWindowInfo(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 880),
                    name: nil,
                    ownerName: "Dock",
                    layer: 0
                ),
                SelectionWindowInfo(
                    id: 2,
                    frame: CGRect(x: 120, y: 140, width: 500, height: 320),
                    name: "Hidden Behind Dock Layer",
                    ownerName: "TextEdit",
                    layer: 0
                ),
            ],
            ownWindowID: 99
        )

        let target = resolver.targetWindow(at: CGPoint(x: 180, y: 180))

        XCTAssertNil(target)
    }

    func testOwnWindowAndNonLayerZeroWindowsAreIgnoredForTargetingAndOcclusion() {
        let resolver = SelectionWindowTargetResolver(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowsInFrontToBackOrder: [
                SelectionWindowInfo(
                    id: 99,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    name: "VoxFlow Overlay",
                    ownerName: "码上写",
                    layer: 0
                ),
                SelectionWindowInfo(
                    id: 4,
                    frame: CGRect(x: 90, y: 90, width: 300, height: 200),
                    name: "Floating HUD",
                    ownerName: "码上写",
                    layer: 25
                ),
                SelectionWindowInfo(
                    id: 2,
                    frame: CGRect(x: 120, y: 140, width: 500, height: 320),
                    name: "Document",
                    ownerName: "TextEdit",
                    layer: 0
                ),
            ],
            ownWindowID: 99
        )

        let target = resolver.targetWindow(at: CGPoint(x: 180, y: 180))

        XCTAssertEqual(target?.id, 2)
    }

    func testFinderDesktopAndTinyWindowsAreNotCaptureWorthy() {
        let resolver = SelectionWindowTargetResolver(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowsInFrontToBackOrder: [
                SelectionWindowInfo(
                    id: 1,
                    frame: CGRect(x: 20, y: 20, width: 40, height: 40),
                    name: "Tiny",
                    ownerName: "TextEdit",
                    layer: 0
                ),
                SelectionWindowInfo(
                    id: 2,
                    frame: CGRect(x: 60, y: 60, width: 600, height: 400),
                    name: nil,
                    ownerName: "Finder",
                    layer: 0
                ),
            ],
            ownWindowID: 99
        )

        XCTAssertNil(resolver.targetWindow(at: CGPoint(x: 30, y: 30)))
        XCTAssertNil(resolver.targetWindow(at: CGPoint(x: 100, y: 100)))
    }

    func testFullScreenApplicationWindowCanBeTargeted() {
        let resolver = SelectionWindowTargetResolver(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowsInFrontToBackOrder: [
                SelectionWindowInfo(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    name: "Presentation",
                    ownerName: "Keynote",
                    layer: 0
                ),
            ],
            ownWindowID: 99
        )

        let target = resolver.targetWindow(at: CGPoint(x: 720, y: 450))

        XCTAssertEqual(target?.id, 1)
        XCTAssertEqual(target?.frame, CGRect(x: 0, y: 0, width: 1440, height: 900))
    }
}
