import AppKit
import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class SelectionOverlayControllerTests: XCTestCase {
    func testPresentCreatesOneBorderlessOverlayWindowPerDisplay() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Built-in",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                scale: 2,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "External",
                frame: CGRect(x: 1440, y: 0, width: 800, height: 600),
                scale: 1,
                isPrimary: false
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)

        controller.present(displays: displays)

        XCTAssertEqual(factory.configurations.map(\.display), displays)
        XCTAssertTrue(factory.configurations.allSatisfy(\.isBorderless))
        XCTAssertTrue(factory.configurations.allSatisfy(\.isFloating))
        XCTAssertEqual(factory.windows.map(\.orderFrontCallCount), [1, 1])
    }

    func testSelectionChromeIsHiddenOnDisplaysThatDoNotIntersectSelection() {
        let displayA = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: 2,
            isPrimary: true
        )
        let displayB = ScreenshotDisplay(
            id: 2,
            name: "External",
            frame: CGRect(x: 100, y: 0, width: 100, height: 100),
            scale: 1,
            isPrimary: false
        )
        let state = SelectionState(
            displayFrame: displayA.frame.union(displayB.frame),
            displayScale: 2,
            startPoint: CGPoint(x: 10, y: 10),
            currentPoint: CGPoint(x: 40, y: 40)
        )

        XCTAssertTrue(
            SelectionOverlayDisplayGeometry.shouldDrawSelectionChrome(
                localSelectionRect: SelectionOverlayDisplayGeometry.localSelectionRect(for: state, on: displayA),
                visibleBounds: CGRect(origin: .zero, size: displayA.frame.size)
            )
        )
        XCTAssertFalse(
            SelectionOverlayDisplayGeometry.shouldDrawSelectionChrome(
                localSelectionRect: SelectionOverlayDisplayGeometry.localSelectionRect(for: state, on: displayB),
                visibleBounds: CGRect(origin: .zero, size: displayB.frame.size)
            )
        )
    }

    func testSelectionChromeCanRenderOnDisplaysIntersectingCrossDisplaySelection() {
        let displayA = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: 2,
            isPrimary: true
        )
        let displayB = ScreenshotDisplay(
            id: 2,
            name: "External",
            frame: CGRect(x: 100, y: 0, width: 100, height: 100),
            scale: 1,
            isPrimary: false
        )
        let state = SelectionState(
            displayFrame: displayA.frame.union(displayB.frame),
            displayScale: 2,
            startPoint: CGPoint(x: 80, y: 10),
            currentPoint: CGPoint(x: 120, y: 40)
        )

        XCTAssertTrue(
            SelectionOverlayDisplayGeometry.shouldDrawSelectionChrome(
                localSelectionRect: SelectionOverlayDisplayGeometry.localSelectionRect(for: state, on: displayA),
                visibleBounds: CGRect(origin: .zero, size: displayA.frame.size)
            )
        )
        XCTAssertTrue(
            SelectionOverlayDisplayGeometry.shouldDrawSelectionChrome(
                localSelectionRect: SelectionOverlayDisplayGeometry.localSelectionRect(for: state, on: displayB),
                visibleBounds: CGRect(origin: .zero, size: displayB.frame.size)
            )
        )
    }

    func testPresentFramesPassesFrozenSnapshotToOverlayWindows() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let snapshot = makeImage(width: 20, height: 10)
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)

        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])

        XCTAssertEqual(factory.configurations.map(\.display), [display])
        XCTAssertEqual(factory.configurations.first?.snapshotImage?.width, 20)
        XCTAssertEqual(factory.configurations.first?.snapshotImage?.height, 10)
    }

    func testMixedScaleDisplaysUsePerOverlaySnapshotScaleWhileSelectionUsesOutputScale() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "External 1x",
                frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                scale: 1,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Built-in 2x",
                frame: CGRect(x: 20, y: 0, width: 20, height: 20),
                scale: 2,
                isPrimary: false
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(frames: [
            ScreenshotDisplayFrame(display: displays[0], image: makeImage(width: 20, height: 20)),
            ScreenshotDisplayFrame(display: displays[1], image: makeImage(width: 40, height: 40)),
        ])

        controller.beginSelection(on: displays[0].id, at: CGPoint(x: 2, y: 3))
        controller.updateSelection(to: CGPoint(x: 30, y: 12))

        XCTAssertEqual(factory.configurations.map(\.snapshotScale), [1, 2])
        XCTAssertEqual(
            factory.windows.compactMap { $0.selectionStates.last ?? nil }.map(\.displayScale),
            [2, 2]
        )
        XCTAssertEqual(
            factory.configurations.map {
                SelectionOverlaySnapshotSampler.pixelPoint(
                    forOverlayPoint: CGPoint(x: 3, y: 4),
                    snapshotScale: $0.snapshotScale
                )
            },
            [CGPoint(x: 3, y: 4), CGPoint(x: 6, y: 8)]
        )
    }

    func testDragUpdatesSelectionStateOnMatchingDisplayWindow() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))

        XCTAssertEqual(
            factory.windows.first?.selectionStates.compactMap { $0 }.last?.normalizedRect,
            CGRect(x: 120, y: 80, width: 180, height: 140)
        )
    }

    func testManualSelectionCanSpanMultipleDisplays() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Left",
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                scale: 1,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Right",
                frame: CGRect(x: 100, y: 0, width: 100, height: 100),
                scale: 1,
                isPrimary: false
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: displays)

        controller.beginSelection(on: displays[0].id, at: CGPoint(x: 80, y: 20))
        controller.updateSelection(to: CGPoint(x: 120, y: 60))

        let expectedState = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
            displayScale: 1,
            startPoint: CGPoint(x: 80, y: 20),
            currentPoint: CGPoint(x: 120, y: 60)
        )
        XCTAssertEqual(factory.windows[0].selectionStates.compactMap { $0 }.last, expectedState)
        XCTAssertEqual(factory.windows[1].selectionStates.compactMap { $0 }.last, expectedState)
    }

    func testAppKitPointerRoutersContinueOneGlobalDragSessionAcrossOverlayWindows() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Left",
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                scale: 1,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Right",
                frame: CGRect(x: 100, y: 0, width: 100, height: 100),
                scale: 1,
                isPrimary: false
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: displays)
        let leftRouter = SelectionOverlayPointerEventRouter(eventHandler: factory.windows[0].emit)
        let rightRouter = SelectionOverlayPointerEventRouter(eventHandler: factory.windows[1].emit)

        leftRouter.mouseDown(atGlobalPoint: CGPoint(x: 80, y: 20))
        rightRouter.mouseDragged(atGlobalPoint: CGPoint(x: 140, y: 70))
        rightRouter.mouseUp(atGlobalPoint: CGPoint(x: 140, y: 70))

        let expectedState = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
            displayScale: 1,
            startPoint: CGPoint(x: 80, y: 20),
            currentPoint: CGPoint(x: 140, y: 70)
        )
        XCTAssertEqual(factory.windows[0].selectionStates.compactMap { $0 }.last, expectedState)
        XCTAssertEqual(factory.windows[1].selectionStates.compactMap { $0 }.last, expectedState)
    }

    func testAppKitOverlayAcceptsFirstMouseWithoutDelayingWindowOrdering() throws {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let view = SelectionOverlayContentView(
            configuration: SelectionOverlayWindowConfiguration(display: display),
            eventHandler: { _ in }
        )
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 20, y: 20),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        XCTAssertTrue(view.acceptsFirstMouse(for: event))
        XCTAssertFalse(view.shouldDelayWindowOrdering(for: event))
    }

    func testSelectionCursorResolverUsesMoveResizeAndMarqueeCursors() {
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
            displayScale: 1,
            startPoint: CGPoint(x: 100, y: 80),
            currentPoint: CGPoint(x: 300, y: 220)
        )

        XCTAssertEqual(
            SelectionOverlayCursorResolver.cursorKind(
                at: CGPoint(x: 200, y: 150),
                selectionState: state,
                isMovingSelection: false
            ),
            .openHand
        )
        XCTAssertEqual(
            SelectionOverlayCursorResolver.cursorKind(
                at: CGPoint(x: 200, y: 150),
                selectionState: state,
                isMovingSelection: true
            ),
            .closedHand
        )
        XCTAssertEqual(
            SelectionOverlayCursorResolver.cursorKind(
                at: CGPoint(x: 20, y: 20),
                selectionState: state,
                isMovingSelection: false
            ),
            .crosshair
        )

        let presentation = SelectionOverlayPresentation(state: state, handleSize: 16)
        let expectedHandleCursors: [SelectionOverlayCursorKind] = [
            .diagonalNorthwestSoutheast,
            .verticalResize,
            .diagonalNortheastSouthwest,
            .horizontalResize,
            .horizontalResize,
            .diagonalNortheastSouthwest,
            .verticalResize,
            .diagonalNorthwestSoutheast,
        ]
        XCTAssertEqual(
            presentation.resizeHandleRects.map { handleRect in
                SelectionOverlayCursorResolver.cursorKind(
                    at: CGPoint(x: handleRect.midX, y: handleRect.midY),
                    selectionState: state,
                    isMovingSelection: false
                )
            },
            expectedHandleCursors
        )
    }

    func testEscapeAndToolbarCancelCloseOverlayAndReportCancellation() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.handleKey(.escape)

        XCTAssertEqual(results, [.cancelled])
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
    }

    func testReturnDoubleClickAndToolbarCompleteCloseBeforeReportingSelection() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var closeCountDuringResult = 0
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            closeCountDuringResult = factory.windows.first?.closeCallCount ?? 0
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        controller.handleToolbarRole(.complete)

        XCTAssertEqual(closeCountDuringResult, 1)
        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 100, y: 80),
                        currentPoint: CGPoint(x: 240, y: 180)
                    )
                )
            ]
        )
    }

    func testDoubleClickInsideFinishedSelectionConfirmsCapture() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        factory.windows.first?.emit(.doubleClick(CGPoint(x: 170, y: 130)))

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 100, y: 80),
                        currentPoint: CGPoint(x: 240, y: 180)
                    )
                )
            ]
        )
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
    }

    func testSingleClickInsideFinishedSelectionDoesNotPreventDoubleClickConfirmation() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        factory.windows.first?.emit(.selectionBegan(CGPoint(x: 170, y: 130)))
        factory.windows.first?.emit(.selectionEnded(CGPoint(x: 170, y: 130)))
        factory.windows.first?.emit(.doubleClick(CGPoint(x: 170, y: 130)))

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 100, y: 80),
                        currentPoint: CGPoint(x: 240, y: 180)
                    )
                )
            ]
        )
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
    }

    func testDraggingInsideFinishedSelectionMovesSelectionInsteadOfResizingIt() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        factory.windows.first?.emit(.selectionBegan(CGPoint(x: 170, y: 130)))
        factory.windows.first?.emit(.selectionChanged(CGPoint(x: 190, y: 150)))
        factory.windows.first?.emit(.selectionEnded(CGPoint(x: 190, y: 150)))

        XCTAssertEqual(
            factory.windows.first?.selectionStates.compactMap { $0 }.last?.normalizedRect,
            CGRect(x: 120, y: 100, width: 140, height: 100)
        )
    }

    func testDraggingCornerHandleResizesFinishedSelection() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        factory.windows.first?.emit(.selectionBegan(CGPoint(x: 240, y: 180)))
        factory.windows.first?.emit(.selectionChanged(CGPoint(x: 260, y: 210)))
        factory.windows.first?.emit(.selectionEnded(CGPoint(x: 260, y: 210)))

        XCTAssertEqual(
            factory.windows.first?.selectionStates.compactMap { $0 }.last?.normalizedRect,
            CGRect(x: 100, y: 80, width: 160, height: 130)
        )
    }

    func testDraggingEdgeHandleResizesFinishedSelection() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        factory.windows.first?.emit(.selectionBegan(CGPoint(x: 100, y: 130)))
        factory.windows.first?.emit(.selectionChanged(CGPoint(x: 70, y: 130)))
        factory.windows.first?.emit(.selectionEnded(CGPoint(x: 70, y: 130)))

        XCTAssertEqual(
            factory.windows.first?.selectionStates.compactMap { $0 }.last?.normalizedRect,
            CGRect(x: 70, y: 80, width: 170, height: 100)
        )
    }

    func testDraggingInsideWindowTargetSelectionStartsNewManualSelection() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        factory.windows.first?.emit(
            .windowTargetSelected(CGRect(x: 100, y: 80, width: 220, height: 160))
        )

        factory.windows.first?.emit(.selectionBegan(CGPoint(x: 150, y: 110)))
        factory.windows.first?.emit(.selectionChanged(CGPoint(x: 210, y: 170)))
        factory.windows.first?.emit(.selectionEnded(CGPoint(x: 210, y: 170)))

        XCTAssertEqual(
            factory.windows.first?.selectionStates.compactMap { $0 }.last?.normalizedRect,
            CGRect(x: 150, y: 110, width: 60, height: 60)
        )
    }

    func testAnnotationToolbarRoleActivatesInlineToolWithoutClosingOverlay() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        controller.handleToolbarRole(.rectangle)

        XCTAssertEqual(results, [])
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.activeRole, .rectangle)
    }

    func testTextRecognitionToolbarRoleCompletesSelectionWithTextRecognitionSourceWithoutActivatingAnnotationTool() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        controller.handleToolbarRole(.textRecognition)

        XCTAssertEqual(factory.windows.first?.annotationStates.last?.activeRole, nil)
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
        XCTAssertEqual(
            results,
            [
                .acceptedTextRecognition(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 100, y: 80),
                        currentPoint: CGPoint(x: 240, y: 180)
                    )
                )
            ]
        )
    }

    func testTextRecognitionToolbarRoleCompletesAnnotatedSelectionWithTextRecognitionSource() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 30, y: 30))
        controller.handleToolbarRole(.rectangle)

        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 12, y: 13)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 20, y: 25)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 20, y: 25)))
        controller.handleToolbarRole(.textRecognition)

        guard case .acceptedAnnotatedTextRecognition(let state, let document) = results.first else {
            XCTFail("Expected annotated text recognition selection result")
            return
        }
        XCTAssertEqual(
            state,
            SelectionState(
                displayFrame: display.frame,
                displayScale: display.scale,
                startPoint: CGPoint(x: 10, y: 10),
                currentPoint: CGPoint(x: 30, y: 30)
            )
        )
        XCTAssertEqual(document.elements.count, 1)
    }

    func testTranslateToolbarRoleKeepsSelectionOpenAndAddsTranslatedOverlay() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        let translator = FakeInlineSelectionTranslator(
            overlay: TranslatedOverlayAnnotationElement(lines: [
                .init(bounds: CGRect(x: 2, y: 3, width: 20, height: 10), text: "你好")
            ])
        )
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            inlineTranslator: translator
        ) { result in
            results.append(result)
        }
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))

        controller.handleToolbarRole(.translate)
        await translator.waitForRequest()
        await Task.yield()

        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
        XCTAssertEqual(results, [])
        XCTAssertEqual(translator.receivedImageSizes, [CGSize(width: 50, height: 30)])
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.document.elements.count, 0)
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.translatedOverlay?.lines.map(\.text), ["你好"])
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.activeRole, .translate)
    }

    func testTranslateToolbarRoleShowsLoadingWhileInlineTranslationIsRunning() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        let translator = SuspendingInlineSelectionTranslator(
            overlay: TranslatedOverlayAnnotationElement(lines: [
                .init(bounds: CGRect(x: 2, y: 3, width: 20, height: 10), text: "你好")
            ])
        )
        let controller = SelectionOverlayController(
            windowFactory: factory,
            inlineTranslator: translator
        )
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))

        controller.handleToolbarRole(.translate)
        await translator.waitForRequest()

        XCTAssertEqual(factory.windows.first?.annotationStates.last?.activeRole, .translate)
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.inlineTranslationStatus, .loading)

        await translator.finish()
    }

    func testTranslateToolbarRoleCanReenableInlineTranslationAfterToggleOff() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        let translator = FakeInlineSelectionTranslator(
            overlay: TranslatedOverlayAnnotationElement(lines: [
                .init(bounds: CGRect(x: 2, y: 3, width: 20, height: 10), text: "你好")
            ])
        )
        let controller = SelectionOverlayController(
            windowFactory: factory,
            inlineTranslator: translator
        )
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))

        controller.handleToolbarRole(.translate)
        await translator.waitForRequest()
        await Task.yield()
        controller.handleToolbarRole(.translate)
        XCTAssertNil(factory.windows.first?.annotationStates.last?.translatedOverlay)
        controller.handleToolbarRole(.translate)
        await Task.yield()

        let elements = factory.windows.first?.annotationStates.last?.document.elements ?? []
        XCTAssertEqual(translator.receivedImageSizes.count, 1)
        XCTAssertEqual(elements.count, 0)
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.inlineTranslationStatus, .idle)
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.translatedOverlay?.lines.map(\.text), ["你好"])
    }

    func testCompletingAfterInlineTranslationReturnsTranslatedAnnotatedResultWithoutMutatingDocumentState() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        let translator = FakeInlineSelectionTranslator(
            overlay: TranslatedOverlayAnnotationElement(lines: [
                .init(bounds: CGRect(x: 2, y: 3, width: 20, height: 10), text: "你好")
            ])
        )
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            inlineTranslator: translator
        ) { result in
            results.append(result)
        }
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))

        controller.handleToolbarRole(.translate)
        await translator.waitForRequest()
        await Task.yield()
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(let state, let document) = results.first else {
            XCTFail("Expected translated overlay to complete as annotated result")
            return
        }
        XCTAssertEqual(
            state,
            SelectionState(
                displayFrame: display.frame,
                displayScale: display.scale,
                startPoint: CGPoint(x: 10, y: 10),
                currentPoint: CGPoint(x: 60, y: 40)
            )
        )
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.document.elements.count, 0)
        XCTAssertEqual(document.elements.count, 1)
        guard case .translatedOverlay(let overlay) = document.elements.first else {
            XCTFail("Expected translated overlay document element")
            return
        }
        XCTAssertEqual(overlay.lines.map(\.text), ["你好"])
    }

    func testCompletingAfterInlineTranslationKeepsUserAnnotationsAboveTranslatedOverlay() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        let translator = FakeInlineSelectionTranslator(
            overlay: TranslatedOverlayAnnotationElement(lines: [
                .init(bounds: CGRect(x: 2, y: 3, width: 20, height: 10), text: "你好")
            ])
        )
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            inlineTranslator: translator
        ) { result in
            results.append(result)
        }
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))
        controller.handleToolbarRole(.rectangle)
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 20, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 40, y: 30)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 40, y: 30)))

        controller.handleToolbarRole(.translate)
        await translator.waitForRequest()
        await Task.yield()
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first else {
            XCTFail("Expected annotated result")
            return
        }
        XCTAssertEqual(document.elements.map(\.kind), [.translatedOverlay, .rectangle])
    }

    func testSecondTranslateClickTogglesInlineTranslationBackToOriginalSelection() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        let translator = FakeInlineSelectionTranslator(
            overlay: TranslatedOverlayAnnotationElement(lines: [
                .init(bounds: CGRect(x: 2, y: 3, width: 20, height: 10), text: "你好")
            ])
        )
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            inlineTranslator: translator
        ) { result in
            results.append(result)
        }
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))

        controller.handleToolbarRole(.translate)
        await translator.waitForRequest()
        await Task.yield()
        controller.handleToolbarRole(.translate)

        XCTAssertNil(factory.windows.first?.annotationStates.last?.translatedOverlay)
        XCTAssertNil(factory.windows.first?.annotationStates.last?.activeRole)

        controller.handleToolbarRole(.complete)

        XCTAssertEqual(results, [
            .accepted(
                SelectionState(
                    displayFrame: display.frame,
                    displayScale: display.scale,
                    startPoint: CGPoint(x: 10, y: 10),
                    currentPoint: CGPoint(x: 60, y: 40)
                )
            )
        ])
    }

    func testTranslateToolbarRoleWithoutInlineTranslatorStaysInSelectionOverlay() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 100, height: 80),
            scale: 1,
            isPrimary: true
        )
        let snapshot = makeImage(width: 100, height: 80)
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(frames: [
            ScreenshotDisplayFrame(display: display, image: snapshot)
        ])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 60, y: 40))

        controller.handleToolbarRole(.translate)

        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
        XCTAssertEqual(results, [])
        XCTAssertEqual(
            factory.windows.first?.annotationStates.last?.inlineTranslationStatus,
            .failed("翻译服务未就绪")
        )
    }

    func testToolbarHasNoDefaultActiveTool() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        XCTAssertEqual(factory.windows.first?.annotationStates.last?.activeRole, nil)
    }

    func testCompleteToolbarRoleKeepsPlainAcceptedSelectionSource() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 80))
        controller.updateSelection(to: CGPoint(x: 240, y: 180))

        controller.handleToolbarRole(.complete)

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 100, y: 80),
                        currentPoint: CGPoint(x: 240, y: 180)
                    )
                )
            ]
        )
    }

    func testMosaicToolPublishesBrushPreviewWhilePointerIsInsideSelection() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 80, y: 80))

        controller.handleToolbarRole(.mosaic)
        factory.windows.first?.emit(.annotationHoverChanged(CGPoint(x: 30, y: 34)))

        XCTAssertEqual(
            factory.windows.first?.annotationStates.last?.brushPreview,
            AnnotationBrushPreview(center: CGPoint(x: 40, y: 48), size: 40)
        )

        factory.windows.first?.emit(.annotationHoverChanged(nil))

        XCTAssertNil(factory.windows.first?.annotationStates.last?.brushPreview)
    }

    func testInlineAnnotationDrawsInsideSelectionAndCompletesWithAnnotatedResult() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 30, y: 30))
        controller.handleToolbarRole(.rectangle)

        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 12, y: 13)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 20, y: 25)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 20, y: 25)))
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(let state, let document) = results.first else {
            XCTFail("Expected annotated selection result")
            return
        }
        XCTAssertEqual(
            state,
            SelectionState(
                displayFrame: display.frame,
                displayScale: display.scale,
                startPoint: CGPoint(x: 10, y: 10),
                currentPoint: CGPoint(x: 30, y: 30)
            )
        )
        XCTAssertEqual(document.elements.count, 1)
        guard case .rectangle(let element) = document.elements.first else {
            XCTFail("Expected rectangle annotation")
            return
        }
        XCTAssertEqual(element.rect, CGRect(x: 4, y: 6, width: 16, height: 24))
    }

    func testInlineTextAnnotationCommitsInsideSelection() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 40, y: 40))
        controller.handleToolbarRole(.text)

        factory.windows.first?.emit(.annotationTextCommitted(CGPoint(x: 12, y: 14), "  原因  "))
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first,
              case .text(let element) = document.elements.first else {
            XCTFail("Expected text annotation")
            return
        }
        XCTAssertEqual(element.position, CGPoint(x: 4, y: 8))
        XCTAssertEqual(element.content, "原因")
        XCTAssertEqual(element.style.fontSize, 28)
    }

    func testInlineToolbarFontSizeUpdatesNewTextAnnotations() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 80, y: 80))

        // Popover 模式：点击字号按钮打开 popover，再选 24（index=1，数组 [14,24,32]）。
        controller.handleToolbarRole(.fontSize)
        factory.windows.first?.emit(.popoverOptionSelected(.fontSize, 1))
        controller.handleToolbarRole(.text)
        factory.windows.first?.emit(.annotationTextCommitted(CGPoint(x: 20, y: 22), "字号"))
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first,
              case .text(let element) = document.elements.first else {
            XCTFail("Expected text annotation")
            return
        }
        XCTAssertEqual(element.style.fontSize, 48)  // 24 * scale(2) = 48
    }

    func testInlineSelectToolCanSelectAndDeleteExistingAnnotation() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 80, y: 80))
        controller.handleToolbarRole(.rectangle)
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 20, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 40, y: 40)))

        controller.handleToolbarRole(.select)
        factory.windows.first?.emit(.annotationSelectionRequested(CGPoint(x: 30, y: 30)))

        XCTAssertEqual(factory.windows.first?.annotationStates.last?.document.selectedElementIDs.count, 1)

        factory.windows.first?.emit(.deleteSelectedAnnotationRequested)
        controller.handleToolbarRole(.complete)

        guard case .accepted(let state) = results.first else {
            XCTFail("Expected empty annotation document to complete as plain accepted selection")
            return
        }
        XCTAssertEqual(state.normalizedRect, CGRect(x: 10, y: 10, width: 70, height: 70))
    }

    func testInlineSelectToolCanMoveExistingAnnotationByDragging() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 80, y: 80))
        controller.handleToolbarRole(.rectangle)
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 20, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 40, y: 40)))

        controller.handleToolbarRole(.select)
        factory.windows.first?.emit(.annotationSelectionRequested(CGPoint(x: 30, y: 30)))
        factory.windows.first?.emit(.annotationMoveBegan(CGPoint(x: 30, y: 30)))
        factory.windows.first?.emit(.annotationMoveChanged(CGPoint(x: 40, y: 35)))
        factory.windows.first?.emit(.annotationMoveEnded(CGPoint(x: 40, y: 35)))
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first,
              case .rectangle(let element) = document.elements.first else {
            XCTFail("Expected moved rectangle annotation")
            return
        }
        XCTAssertEqual(element.rect, CGRect(x: 40, y: 30, width: 40, height: 40))
        XCTAssertEqual(document.selectedElementIDs, [element.id])
    }

    func testInlineSelectToolCanResizeExistingAnnotationFromHandle() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 80, y: 80))
        controller.handleToolbarRole(.rectangle)
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 20, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 40, y: 40)))

        controller.handleToolbarRole(.select)
        factory.windows.first?.emit(.annotationSelectionRequested(CGPoint(x: 30, y: 30)))
        factory.windows.first?.emit(.annotationResizeBegan(.endPoint, CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationResizeChanged(CGPoint(x: 55, y: 50)))
        factory.windows.first?.emit(.annotationResizeEnded(CGPoint(x: 55, y: 50)))
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first,
              case .rectangle(let element) = document.elements.first else {
            XCTFail("Expected resized rectangle annotation")
            return
        }
        XCTAssertEqual(element.rect, CGRect(x: 20, y: 20, width: 70, height: 60))
        XCTAssertEqual(document.selectedElementIDs, [element.id])
    }

    func testInlineToolbarCanCopyPasteAndDuplicateSelectedAnnotation() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 100, y: 100))
        controller.handleToolbarRole(.rectangle)
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 20, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 40, y: 40)))

        controller.handleToolbarRole(.select)
        factory.windows.first?.emit(.annotationSelectionRequested(CGPoint(x: 30, y: 30)))
        controller.handleToolbarRole(.copy)
        controller.handleToolbarRole(.paste)
        controller.handleToolbarRole(.duplicate)
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first else {
            XCTFail("Expected annotated result")
            return
        }
        XCTAssertEqual(document.elements.map(\.bounds), [
            CGRect(x: 20, y: 20, width: 40, height: 40),
            CGRect(x: 35, y: 35, width: 40, height: 40),
            CGRect(x: 50, y: 50, width: 40, height: 40),
        ])
        XCTAssertEqual(document.selectedElementIDs, [document.elements[2].id])
    }

    func testInlineSelectToolCanShiftToggleAndMoveMultipleAnnotations() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 10, y: 10))
        controller.updateSelection(to: CGPoint(x: 120, y: 120))
        controller.handleToolbarRole(.rectangle)
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 20, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 40, y: 40)))
        factory.windows.first?.emit(.annotationBegan(CGPoint(x: 60, y: 20)))
        factory.windows.first?.emit(.annotationChanged(CGPoint(x: 80, y: 40)))
        factory.windows.first?.emit(.annotationEnded(CGPoint(x: 80, y: 40)))

        controller.handleToolbarRole(.select)
        factory.windows.first?.emit(.annotationSelectionRequested(CGPoint(x: 30, y: 30)))
        factory.windows.first?.emit(.annotationToggleSelectionRequested(CGPoint(x: 70, y: 30)))
        factory.windows.first?.emit(.annotationMoveBegan(CGPoint(x: 30, y: 30)))
        factory.windows.first?.emit(.annotationMoveChanged(CGPoint(x: 40, y: 35)))
        factory.windows.first?.emit(.annotationMoveEnded(CGPoint(x: 40, y: 35)))
        controller.handleToolbarRole(.complete)

        guard case .acceptedAnnotated(_, let document) = results.first else {
            XCTFail("Expected annotated result")
            return
        }
        XCTAssertEqual(document.elements.map(\.bounds), [
            CGRect(x: 40, y: 30, width: 40, height: 40),
            CGRect(x: 120, y: 30, width: 40, height: 40),
        ])
        XCTAssertEqual(document.selectedElementIDs, document.elements.map(\.id))
    }

    func testDownloadAttachesSavePanelToTriggeringOverlayAndClosesAfterSuccessfulSave() {
        let leftDisplay = ScreenshotDisplay(
            id: 1,
            name: "Left",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let rightDisplay = ScreenshotDisplay(
            id: 2,
            name: "Right",
            frame: CGRect(x: 20, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: false
        )
        let frozenImage = makeImage(width: 20, height: 20)
        let renderedImage = makeImage(width: 5, height: 4)
        let renderer = CapturingAnnotationRenderer(renderedImage: renderedImage)
        let factory = FakeSelectionOverlayWindowFactory()
        var overlayVisibilityDuringSave: [[Bool]] = []
        let saver = CapturingScreenshotSavePanelPresenter(result: true) { _ in
            overlayVisibilityDuringSave.append(factory.windows.map(\.isVisible))
        }
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            imageSaver: saver,
            annotationRenderer: renderer
        ) { result in
            results.append(result)
        }
        controller.present(frames: [
            ScreenshotDisplayFrame(display: leftDisplay, image: frozenImage),
            ScreenshotDisplayFrame(display: rightDisplay, image: frozenImage),
        ])
        controller.beginSelection(on: rightDisplay.id, at: CGPoint(x: 22, y: 3))
        controller.updateSelection(to: CGPoint(x: 32, y: 13))
        controller.handleToolbarRole(.rectangle)
        factory.windows[1].emit(.annotationBegan(CGPoint(x: 3, y: 4)))
        factory.windows[1].emit(.annotationChanged(CGPoint(x: 7, y: 8)))
        factory.windows[1].emit(.annotationEnded(CGPoint(x: 7, y: 8)))

        factory.windows[1].emit(.toolbarRole(.download))

        XCTAssertEqual(results, [.cancelled])
        XCTAssertEqual(factory.windows.map(\.closeCallCount), [1, 1])
        XCTAssertEqual(overlayVisibilityDuringSave, [[false, true]])
        XCTAssertEqual(factory.windows[0].visibilityChanges, [false])
        XCTAssertEqual(factory.windows[1].visibilityChanges, [])
        XCTAssertTrue(saver.hostWindows.first === factory.windows[1].savePanelHostWindow)
        XCTAssertEqual(renderer.receivedImageSizes, [CGSize(width: 10, height: 10)])
        XCTAssertEqual(renderer.receivedDocuments.map(\.elements.count), [1])
        XCTAssertEqual(saver.savedImageSizes, [CGSize(width: 5, height: 4)])
    }

    func testDownloadCancellationRestoresOtherOverlaysAndKeepsEditingOpen() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Left",
                frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                scale: 1,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Right",
                frame: CGRect(x: 20, y: 0, width: 20, height: 20),
                scale: 1,
                isPrimary: false
            ),
        ]
        let frozenImage = makeImage(width: 20, height: 20)
        let factory = FakeSelectionOverlayWindowFactory()
        let saver = CapturingScreenshotSavePanelPresenter(result: false)
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            imageSaver: saver
        ) { results.append($0) }
        controller.present(frames: displays.map {
            ScreenshotDisplayFrame(display: $0, image: frozenImage)
        })
        controller.beginSelection(on: displays[1].id, at: CGPoint(x: 22, y: 3))
        controller.updateSelection(to: CGPoint(x: 32, y: 13))

        factory.windows[1].emit(.toolbarRole(.download))

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(factory.windows.map(\.closeCallCount), [0, 0])
        XCTAssertEqual(factory.windows.map(\.isVisible), [true, true])
        XCTAssertEqual(factory.windows[0].visibilityChanges, [false, true])
        XCTAssertEqual(factory.windows[1].visibilityChanges, [true])
        XCTAssertTrue(saver.hostWindows.first === factory.windows[1].savePanelHostWindow)
    }

    func testWindowTargetSelectionKeepsOverlayOpenForAnnotationBeforeCompletion() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        factory.windows.first?.emit(
            .windowTargetSelected(CGRect(x: 120, y: 90, width: 300, height: 180))
        )

        XCTAssertEqual(
            factory.windows.first?.selectionStates.compactMap { $0 }.last,
            SelectionState(
                displayFrame: display.frame,
                displayScale: display.scale,
                startPoint: CGPoint(x: 120, y: 90),
                currentPoint: CGPoint(x: 420, y: 270)
            )
        )
        XCTAssertEqual(results, [])
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)

        controller.handleToolbarRole(.complete)

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 120, y: 90),
                        currentPoint: CGPoint(x: 420, y: 270)
                    )
                )
            ]
        )
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
    }

    func testDoubleClickInsideWindowTargetSelectionConfirmsCapture() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        factory.windows.first?.emit(
            .windowTargetSelected(CGRect(x: 120, y: 90, width: 300, height: 180))
        )

        factory.windows.first?.emit(.doubleClick(CGPoint(x: 170, y: 130)))

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 120, y: 90),
                        currentPoint: CGPoint(x: 420, y: 270)
                    )
                )
            ]
        )
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
    }

    func testFullScreenKeySelectsEntirePrimaryDisplayBeforeCompletion() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "External",
                frame: CGRect(x: -800, y: 0, width: 800, height: 600),
                scale: 1,
                isPrimary: false
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Built-in",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                scale: 2,
                isPrimary: true
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: displays)

        controller.handleKey(.fullScreen)

        XCTAssertEqual(
            factory.windows[1].selectionStates.compactMap { $0 }.last,
            SelectionState(
                displayFrame: displays[1].frame,
                displayScale: displays[1].scale,
                startPoint: CGPoint(x: displays[1].frame.minX, y: displays[1].frame.minY),
                currentPoint: CGPoint(x: displays[1].frame.maxX, y: displays[1].frame.maxY)
            )
        )
        XCTAssertEqual(results, [])
        XCTAssertEqual(factory.windows.map(\.closeCallCount), [0, 0])

        controller.handleToolbarRole(.complete)

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: displays[1].frame,
                        displayScale: displays[1].scale,
                        startPoint: CGPoint(x: displays[1].frame.minX, y: displays[1].frame.minY),
                        currentPoint: CGPoint(x: displays[1].frame.maxX, y: displays[1].frame.maxY)
                    )
                )
            ]
        )
        XCTAssertEqual(factory.windows.map(\.closeCallCount), [1, 1])
    }

    func testDoubleClickInsideFullScreenSelectionConfirmsCapture() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])
        controller.handleKey(.fullScreen)

        factory.windows.first?.emit(.doubleClick(CGPoint(x: 720, y: 450)))

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 0, y: 0),
                        currentPoint: CGPoint(x: 1440, y: 900)
                    )
                )
            ]
        )
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
    }

    func testFullScreenWindowEventSelectsThatOverlayDisplayBeforeCompletion() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "External",
                frame: CGRect(x: -800, y: 0, width: 800, height: 600),
                scale: 1,
                isPrimary: false
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Built-in",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                scale: 2,
                isPrimary: true
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: displays)

        factory.windows.first?.emit(.fullScreenRequested)

        XCTAssertEqual(
            factory.windows[0].selectionStates.compactMap { $0 }.last,
            SelectionState(
                displayFrame: displays[0].frame,
                displayScale: displays[0].scale,
                startPoint: CGPoint(x: displays[0].frame.minX, y: displays[0].frame.minY),
                currentPoint: CGPoint(x: displays[0].frame.maxX, y: displays[0].frame.maxY)
            )
        )
        XCTAssertEqual(results, [])

        controller.handleToolbarRole(.complete)

        XCTAssertEqual(
            results,
            [
                .accepted(
                    SelectionState(
                        displayFrame: displays[0].frame,
                        displayScale: displays[0].scale,
                        startPoint: CGPoint(x: displays[0].frame.minX, y: displays[0].frame.minY),
                        currentPoint: CGPoint(x: displays[0].frame.maxX, y: displays[0].frame.maxY)
                    )
                )
            ]
        )
    }

    func testTabTogglesWindowTargetingAcrossAllOverlayWindows() {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Built-in",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                scale: 2,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "External",
                frame: CGRect(x: 1440, y: 0, width: 800, height: 600),
                scale: 1,
                isPrimary: false
            ),
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: displays)

        controller.handleKey(.tab)

        XCTAssertEqual(factory.windows.map(\.windowTargetingStates), [[true, false], [true, false]])

        factory.windows.first?.emit(.windowTargetingToggleRequested)

        XCTAssertEqual(factory.windows.map(\.windowTargetingStates), [[true, false, true], [true, false, true]])
    }

    func testResetCursorRectsDoesNotCrashWhenSelectionIsOnAnotherDisplay() {
        // Reproduces the cross-screen crash: selection rect lives on display A (frame minX=0),
        // but resetCursorRects runs on display B's view (frame minX=1440).
        // Without the empty-rect guard, addCursorRect throws NSInvalidArgumentException on the
        // empty intersection and AppKit rethrows → abort.
        let displayB = ScreenshotDisplay(
            id: 2,
            name: "Right",
            frame: CGRect(x: 1440, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: false
        )
        let view = SelectionOverlayContentView(
            configuration: SelectionOverlayWindowConfiguration(display: displayB),
            eventHandler: { _ in }
        )
        view.frame = CGRect(origin: .zero, size: displayB.frame.size)
        // Selection is entirely on display A (global coords), so after offsetting by display B's
        // minX=1440, the local rect is at negative x — intersection with bounds is empty.
        view.selectionState = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 2880, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 400, y: 400)
        )

        // This must not throw/crash. If the fix is missing, the test process aborts here.
        view.resetCursorRects()
    }

    func testSingleClickWithoutDragDiscardsSelection() {
        // Reproduces the 0×0 selection bug: mouseDown(P) → mouseUp(P) with no drag
        // should discard the selection instead of leaving a 0×0 state stuck.
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        let window = factory.windows[0]
        let point = CGPoint(x: 200, y: 200)

        window.emit(.selectionBegan(point))
        window.emit(.selectionEnded(point))

        // A 0×0 selection should be discarded — updateSelection(nil) should have been called.
        let lastState = window.selectionStates.last ?? nil
        XCTAssertNil(lastState, "0×0 selection from single click should be discarded, got \(String(describing: lastState))")
    }

    func testScrollCaptureToolbarRoleEntersPassthroughModeAndCompletesWithStitchedImage() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            scale: 2,
            isPrimary: true
        )
        let stitchedImage = makeImage(width: 300, height: 1200)
        let factory = FakeSelectionOverlayWindowFactory()
        var requests: [ScrollingScreenshotRequest] = []
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            onResult: { result in
                results.append(result)
            },
            scrollingScreenshotCapture: { request in
                requests.append(request)
                return ScrollingScreenshotCaptureResult(image: stitchedImage)
            }
        )
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 100))
        controller.updateSelection(to: CGPoint(x: 500, y: 500))

        controller.handleToolbarRole(.scrollCapture)
        while results.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(requests.map(\.display), [display])
        XCTAssertEqual(requests.first?.selection.normalizedRect, CGRect(x: 100, y: 100, width: 400, height: 400))
        XCTAssertEqual(factory.windows.first?.scrollCaptureStates, [true, false])
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
        XCTAssertEqual(results, [.acceptedScrolling(ScrollingScreenshotCaptureResult(image: stitchedImage))])
    }

    func testCancelledScrollCaptureClosesWholeSelectionOverlay() async {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(
            windowFactory: factory,
            onResult: { result in
                results.append(result)
            },
            scrollingScreenshotCapture: { _ in nil }
        )
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 100))
        controller.updateSelection(to: CGPoint(x: 500, y: 500))

        controller.handleToolbarRole(.scrollCapture)
        while results.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(factory.windows.first?.scrollCaptureStates, [true, false])
        XCTAssertEqual(factory.windows.first?.closeCallCount, 1)
        XCTAssertEqual(results, [.cancelled])
    }

    // MARK: - Popover (color / lineWidth / fontSize)

    private func presentControllerWithSelection() -> (SelectionOverlayController, FakeSelectionOverlayWindowFactory, FakeSelectionOverlayWindow) {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            scale: 1,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])
        controller.beginSelection(on: display.id, at: CGPoint(x: 100, y: 100))
        controller.updateSelection(to: CGPoint(x: 500, y: 500))
        return (controller, factory, factory.windows[0])
    }

    func testColorToolbarRoleOpensPopoverAndSecondClickClosesIt() {
        let (controller, factory, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.color)
        XCTAssertEqual(window.annotationStates.last?.popoverRole, .color)

        controller.handleToolbarRole(.color)
        XCTAssertNil(window.annotationStates.last?.popoverRole)
    }

    func testLineWidthToolbarRoleOpensPopover() {
        let (controller, _, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.lineWidth)
        XCTAssertEqual(window.annotationStates.last?.popoverRole, .lineWidth)
    }

    func testFontSizeToolbarRoleOpensPopover() {
        let (controller, _, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.fontSize)
        XCTAssertEqual(window.annotationStates.last?.popoverRole, .fontSize)
    }

    func testPopoverOptionSelectedSetsColorAndClosesPopover() {
        let (controller, _, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.color)
        window.emit(.popoverOptionSelected(.color, 1)) // red

        XCTAssertEqual(window.annotationStates.last?.currentStyle.color, .red)
        XCTAssertNil(window.annotationStates.last?.popoverRole)
    }

    func testPopoverOptionSelectedSetsLineWidthAndClosesPopover() {
        let (controller, _, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.lineWidth)
        window.emit(.popoverOptionSelected(.lineWidth, 2)) // 10

        XCTAssertEqual(window.annotationStates.last?.currentStyle.lineWidth, 10)
        XCTAssertNil(window.annotationStates.last?.popoverRole)
    }

    func testPopoverOptionSelectedSetsFontSizeAndClosesPopover() {
        let (controller, _, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.fontSize)
        window.emit(.popoverOptionSelected(.fontSize, 2)) // 大 (32)

        XCTAssertEqual(window.annotationStates.last?.currentFontSize, 32)
        XCTAssertNil(window.annotationStates.last?.popoverRole)
    }

    func testPopoverDismissedClosesPopover() {
        let (controller, _, window) = presentControllerWithSelection()

        controller.handleToolbarRole(.color)
        XCTAssertEqual(window.annotationStates.last?.popoverRole, .color)

        window.emit(.popoverDismissed)
        XCTAssertNil(window.annotationStates.last?.popoverRole)
    }

    func testPopoverDismissedWhenNoPopoverIsOpenIsNoop() {
        let (controller, _, window) = presentControllerWithSelection()

        // No popover open — dismiss should not push a redundant state change.
        let stateCountBefore = window.annotationStates.count
        window.emit(.popoverDismissed)
        XCTAssertEqual(window.annotationStates.count, stateCountBefore)
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let data = Data(repeating: 0, count: width * height * bytesPerPixel)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

@MainActor
private final class FakeSelectionOverlayWindowFactory: SelectionOverlayWindowMaking {
    private(set) var configurations: [SelectionOverlayWindowConfiguration] = []
    private(set) var windows: [FakeSelectionOverlayWindow] = []

    func makeWindow(
        configuration: SelectionOverlayWindowConfiguration,
        eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void
    ) -> any SelectionOverlayWindowControlling {
        configurations.append(configuration)
        let window = FakeSelectionOverlayWindow(eventHandler: eventHandler)
        windows.append(window)
        return window
    }
}

@MainActor
private final class FakeSelectionOverlayWindow: SelectionOverlayWindowControlling {
    private let eventHandler: @MainActor (SelectionOverlayWindowEvent) -> Void
    private(set) var orderFrontCallCount = 0
    private(set) var closeCallCount = 0
    private(set) var isVisible = true
    private(set) var visibilityChanges: [Bool] = []
    private(set) var selectionStates: [SelectionState?] = []
    private(set) var windowTargetingStates = [true]
    private(set) var targetedSelectionReplacementStates = [false]
    private(set) var scrollCaptureStates: [Bool] = []
    private(set) var annotationStates: [SelectionAnnotationOverlayState] = []
    let savePanelHostWindow = NSWindow()

    init(eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void) {
        self.eventHandler = eventHandler
    }

    func orderFront() {
        orderFrontCallCount += 1
        isVisible = true
    }

    func setVisibleForModalPresentation(_ isVisible: Bool) {
        visibilityChanges.append(isVisible)
        self.isVisible = isVisible
        if isVisible {
            orderFront()
        }
    }

    func updateSelection(_ state: SelectionState?) {
        selectionStates.append(state)
    }

    func setWindowTargetingEnabled(_ isEnabled: Bool) {
        windowTargetingStates.append(isEnabled)
    }

    func setAllowsTargetedSelectionReplacement(_ isEnabled: Bool) {
        targetedSelectionReplacementStates.append(isEnabled)
    }

    func setScrollCaptureActive(_ isActive: Bool, selection: SelectionState?) {
        scrollCaptureStates.append(isActive)
    }

    func updateAnnotationState(_ state: SelectionAnnotationOverlayState) {
        annotationStates.append(state)
    }

    func commitInlineTextEditing() {
    }

    func close() {
        closeCallCount += 1
        isVisible = false
    }

    func emit(_ event: SelectionOverlayWindowEvent) {
        eventHandler(event)
    }
}

private final class CapturingScreenshotSavePanelPresenter: ScreenshotSavePanelPresenting {
    private(set) var savedImageSizes: [CGSize] = []
    private(set) var hostWindows: [NSWindow] = []
    private let result: Bool
    private let onSave: (NSWindow) -> Void

    init(result: Bool = true, onSave: @escaping (NSWindow) -> Void = { _ in }) {
        self.result = result
        self.onSave = onSave
    }

    func savePNG(image: CGImage) throws -> Bool {
        savedImageSizes.append(CGSize(width: image.width, height: image.height))
        return result
    }

    func savePNG(
        image: CGImage,
        attachedTo hostWindow: NSWindow,
        completion: @escaping (Result<Bool, any Error>) -> Void
    ) {
        hostWindows.append(hostWindow)
        onSave(hostWindow)
        savedImageSizes.append(CGSize(width: image.width, height: image.height))
        completion(.success(result))
    }
}

private final class CapturingAnnotationRenderer: AnnotationRendering {
    private(set) var receivedImageSizes: [CGSize] = []
    private(set) var receivedDocuments: [AnnotationDocument] = []
    private let renderedImage: CGImage

    init(renderedImage: CGImage) {
        self.renderedImage = renderedImage
    }

    func render(image: CGImage, document: AnnotationDocument) throws -> CGImage {
        receivedImageSizes.append(CGSize(width: image.width, height: image.height))
        receivedDocuments.append(document)
        return renderedImage
    }
}

@MainActor
private final class FakeInlineSelectionTranslator: InlineSelectionTranslating {
    private let overlay: TranslatedOverlayAnnotationElement
    private(set) var receivedImageSizes: [CGSize] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(overlay: TranslatedOverlayAnnotationElement) {
        self.overlay = overlay
    }

    func translatedOverlay(for image: CGImage) async throws -> TranslatedOverlayAnnotationElement {
        receivedImageSizes.append(CGSize(width: image.width, height: image.height))
        continuation?.resume()
        continuation = nil
        return overlay
    }

    func waitForRequest() async {
        if !receivedImageSizes.isEmpty {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

@MainActor
private final class SuspendingInlineSelectionTranslator: InlineSelectionTranslating {
    private let overlay: TranslatedOverlayAnnotationElement
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<TranslatedOverlayAnnotationElement, Never>?
    private var didReceiveRequest = false

    init(overlay: TranslatedOverlayAnnotationElement) {
        self.overlay = overlay
    }

    func translatedOverlay(for image: CGImage) async throws -> TranslatedOverlayAnnotationElement {
        didReceiveRequest = true
        requestContinuation?.resume()
        requestContinuation = nil
        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func waitForRequest() async {
        if didReceiveRequest {
            return
        }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func finish() async {
        finishContinuation?.resume(returning: overlay)
        finishContinuation = nil
        await Task.yield()
    }
}
