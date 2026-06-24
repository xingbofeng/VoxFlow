import XCTest

final class SelectionOverlaySourceTests: XCTestCase {
    func testAppKitOverlayWiresShotShotStyleResilienceHooks() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("SelectionWindowTargetResolver.live"))
        XCTAssertTrue(source.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(source.contains("NSEvent.addGlobalMonitorForEvents"))
        XCTAssertTrue(source.contains("CGEvent.tapCreate"))
        XCTAssertTrue(source.contains("CGEventType.keyDown"))
        XCTAssertTrue(source.contains("keyCode == 53"))
        XCTAssertTrue(source.contains("Thread.isMainThread"))
        XCTAssertTrue(source.contains("MainActor.assumeIsolated"))
        XCTAssertTrue(source.contains("NSWindow.didResignKeyNotification"))
        XCTAssertTrue(source.contains("NSApplication.didChangeScreenParametersNotification"))
        XCTAssertTrue(source.contains(".windowTargetSelected"))
    }

    func testScrollCaptureSuppressesMouseMovedEventsLikeMacshot() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)
        let method = try methodSource(
            named: "setScrollCaptureActive",
            endingBefore: "commitInlineTextEditing",
            in: source
        )

        XCTAssertTrue(method.contains("scrollMouseMoveSuppressor.start()"))
        XCTAssertTrue(method.contains("scrollMouseMoveSuppressor.stop()"))
        XCTAssertTrue(source.contains("CGEventType.mouseMoved"))
        XCTAssertTrue(source.contains("return nil"))
    }

    func testInlineTextEscapeCancelsWholeSelectionOverlay() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("field.onCancel = { [weak self] in"))
        XCTAssertTrue(source.contains("self?.eventHandler(.cancelRequested)"))
    }

    func testInlineTextEditingFocusesOverlayBeforeInstallingFirstResponder() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)
        let method = try methodSource(
            named: "beginInlineTextEditing",
            endingBefore: "commitInlineTextEditing",
            in: source
        )

        let activationRange = try XCTUnwrap(method.range(of: "NSApp.activate(ignoringOtherApps: true)"))
        let keyWindowRange = try XCTUnwrap(method.range(of: "window?.makeKeyAndOrderFront(nil)"))
        let firstResponderRange = try XCTUnwrap(method.range(of: "window?.makeFirstResponder(field)"))

        XCTAssertLessThan(activationRange.lowerBound, firstResponderRange.lowerBound)
        XCTAssertLessThan(keyWindowRange.lowerBound, firstResponderRange.lowerBound)
    }

    func testInlineMosaicPreviewUsesFrozenSnapshotPixels() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("private let snapshotImage: CGImage?"))
        XCTAssertTrue(source.contains("drawPixelatedMosaicAnnotation"))
        XCTAssertTrue(source.contains("context.interpolationQuality = .none"))
        XCTAssertTrue(source.contains("snapshotImage.cropping"))
        XCTAssertFalse(source.contains("NSColor.systemGreen.withAlphaComponent(alpha).setFill()"))
    }

    func testBrushMosaicDoesNotRenderRectangularSelectionChrome() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("guard element.kind != .mosaic else { continue }"))
        XCTAssertTrue(source.contains("case .pen, .mosaic:"))
    }

    func testMosaicToolRendersBrushPreviewFromPointerHover() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("acceptsMouseMovedEvents = true"))
        XCTAssertTrue(source.contains("eventHandler(.annotationHoverChanged(point))"))
        XCTAssertTrue(source.contains("drawMosaicBrushPreview"))
    }

    func testAppKitOverlayWiresMacshotStyleFullScreenAndWindowSnapKeys() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("case 48 where event.isPlainSelectionShortcut"))
        XCTAssertTrue(source.contains("case 3 where event.isPlainSelectionShortcut"))
        XCTAssertTrue(source.contains(".windowTargetingToggleRequested"))
        XCTAssertTrue(source.contains(".fullScreenRequested"))
        XCTAssertTrue(source.contains("setWindowTargetingEnabled"))
        XCTAssertTrue(source.contains("isWindowTargetingEnabled"))
        XCTAssertTrue(source.contains("isPlainSelectionShortcut"))
    }

    private func sourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Selection/SelectionOverlayController.swift")
    }

    private func methodSource(
        named methodName: String,
        endingBefore nextMethodName: String,
        in source: String
    ) throws -> Substring {
        let methodStart = try XCTUnwrap(
            source.range(of: "private func \(methodName)") ??
                source.range(of: "func \(methodName)")
        )
        let searchRange = methodStart.upperBound..<source.endIndex
        let methodEnd = try XCTUnwrap(
            source.range(of: "private func \(nextMethodName)", range: searchRange) ??
                source.range(of: "func \(nextMethodName)", range: searchRange)
        )
        return source[methodStart.lowerBound..<methodEnd.lowerBound]
    }
}
