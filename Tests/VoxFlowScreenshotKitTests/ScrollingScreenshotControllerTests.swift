import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotControllerTests: XCTestCase {
    func testGlobalReturnKeyFinishesActiveCapture() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 36)

        let result = await task.value
        XCTAssertEqual(result, ScrollingScreenshotCaptureResult(image: image))
        XCTAssertEqual(eventMonitor.removedMonitorCount, 5)
    }

    func testGlobalDoubleClickFinishesActiveCapture() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalLeftMouseDown(clickCount: 2)

        let result = await task.value
        XCTAssertEqual(result, ScrollingScreenshotCaptureResult(image: image))
        XCTAssertEqual(eventMonitor.removedMonitorCount, 5)
    }

    func testFinishCapturesAndStitchesLatestFrameBeforeCompleting() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let finalFrame = makeImage(width: 2, height: 3, seed: 40)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 1 })
        var captureCount = 0
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                return captureCount <= 2 ? firstFrame : finalFrame
            },
            stitcher: stitcher,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 36)

        let result = await task.value
        XCTAssertEqual(result?.image.height, 4)
    }

    func testPollingCapturesAndStitchesWithoutScrollEvent() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let scrolledFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 1 })
        var captureCount = 0
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                return captureCount <= 2 ? firstFrame : scrolledFrame
            },
            stitcher: stitcher,
            pollingInterval: 0.05,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()
        let deadline = Date().addingTimeInterval(2)
        while stitcher.currentImage?.height != 4, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(stitcher.currentImage?.height, 4)

        eventMonitor.emitGlobalKeyDown(keyCode: 36)

        let result = await task.value
        XCTAssertEqual(result?.image.height, 4)
    }

    func testAppendCaptureWaitsForStableFrameBeforeStitching() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let movingFrame = makeImage(width: 2, height: 3, seed: 40)
        let stableFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        var appendedFrames: [CGImage] = []
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, _ in
            appendedFrames.append(current)
            return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
        })
        var frames = [firstFrame, firstFrame, movingFrame, stableFrame, stableFrame]
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? stableFrame : frames.removeFirst() },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.scheduleCaptureForTesting()
        let deadline = Date().addingTimeInterval(1)
        while appendedFrames.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value
        XCTAssertEqual(appendedFrames.first?.dataProvider?.data, stableFrame.dataProvider?.data)
    }

    func testManualScrollCaptureUsesImmediateFrameDuringMovement() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let movingFrame = makeImage(width: 2, height: 3, seed: 40)
        let stableFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        var appendedFrames: [CGImage] = []
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, _ in
            appendedFrames.append(current)
            return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
        })
        var frames = [firstFrame, firstFrame, movingFrame, stableFrame, stableFrame]
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? stableFrame : frames.removeFirst() },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.handleManualScrollForTesting(deltaY: -12)
        let deadline = Date().addingTimeInterval(1)
        while appendedFrames.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value
        XCTAssertEqual(appendedFrames.first?.dataProvider?.data, movingFrame.dataProvider?.data)
    }

    func testManualScrollCaptureQueuesFollowUpWhenCaptureIsActive() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let firstScrollFrame = makeImage(width: 2, height: 3, seed: 40)
        let secondScrollFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        var suspendedCapture: CheckedContinuation<CGImage?, Never>?
        var appendedFrames: [CGImage] = []
        var captureCount = 0
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, _ in
            appendedFrames.append(current)
            return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
        })
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                switch captureCount {
                case 1, 2:
                    return firstFrame
                case 3:
                    return await withCheckedContinuation { continuation in
                        suspendedCapture = continuation
                    }
                default:
                    return secondScrollFrame
                }
            },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.handleManualScrollForTesting(deltaY: -12)
        let waitForSuspendedCapture = Date().addingTimeInterval(1)
        while suspendedCapture == nil, Date() < waitForSuspendedCapture {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        controller.handleManualScrollForTesting(deltaY: -12)
        suspendedCapture?.resume(returning: firstScrollFrame)

        let deadline = Date().addingTimeInterval(1)
        while appendedFrames.count < 2, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value
        XCTAssertEqual(appendedFrames.count, 2)
        XCTAssertEqual(appendedFrames[0].dataProvider?.data, firstScrollFrame.dataProvider?.data)
        XCTAssertEqual(appendedFrames[1].dataProvider?.data, secondScrollFrame.dataProvider?.data)
    }

    func testManualScrollCaptureRunsQueuedFrameAfterThrottleInterval() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let firstScrollFrame = makeImage(width: 2, height: 3, seed: 40)
        let secondScrollFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        var appendedFrames: [CGImage] = []
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, _ in
            appendedFrames.append(current)
            return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
        })
        var frames = [firstFrame, firstFrame, firstScrollFrame, secondScrollFrame]
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? secondScrollFrame : frames.removeFirst() },
            stitcher: stitcher,
            captureInterval: 0.2,
            pollingInterval: 10,
            settlementInterval: 10,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.handleManualScrollForTesting(deltaY: -12)
        let firstDeadline = Date().addingTimeInterval(1)
        while appendedFrames.count < 1, Date() < firstDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        controller.handleManualScrollForTesting(deltaY: -12)
        let secondDeadline = Date().addingTimeInterval(1)
        while appendedFrames.count < 2, Date() < secondDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let capturedSecondFrameBeforeFinishing = appendedFrames.count >= 2

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertTrue(capturedSecondFrameBeforeFinishing)
        XCTAssertEqual(appendedFrames.count, 2)
        XCTAssertEqual(appendedFrames[0].dataProvider?.data, firstScrollFrame.dataProvider?.data)
        XCTAssertEqual(appendedFrames[1].dataProvider?.data, secondScrollFrame.dataProvider?.data)
    }

    func testManualScrollSchedulesSettledCaptureAfterScrollingStops() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let movingFrame = makeImage(width: 2, height: 3, seed: 40)
        let settledFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        var appendedFrames: [CGImage] = []
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { current, _ in
            appendedFrames.append(current)
            return ScrollingScreenshotShiftEstimate(rows: 1, agreeingBandCount: 1, totalBandCount: 1)
        })
        var frames = [firstFrame, firstFrame, movingFrame, settledFrame, settledFrame]
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? settledFrame : frames.removeFirst() },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            settlementInterval: 0.05,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.handleManualScrollForTesting(deltaY: -12)
        let deadline = Date().addingTimeInterval(1)
        while appendedFrames.count < 2, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertEqual(appendedFrames.count, 2)
        XCTAssertEqual(appendedFrames[0].dataProvider?.data, movingFrame.dataProvider?.data)
        XCTAssertEqual(appendedFrames[1].dataProvider?.data, settledFrame.dataProvider?.data)
    }

    func testHeightLimitIsAppliedBeforeAppendingRows() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let scrolledFrame = makeImage(width: 2, height: 3, seed: 120)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 3 })
        var captureCount = 0
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                return captureCount <= 2 ? firstFrame : scrolledFrame
            },
            stitcher: stitcher,
            maxPixelHeight: 4,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 36)

        let result = await task.value
        XCTAssertEqual(result?.image.height, 4)
    }

    func testStableFrameChecksumRunsOffMainActor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("await Self.checksum(for: current)"))
        XCTAssertTrue(source.contains("Task.detached"))
    }

    func testStitchAnalysisRunsOffMainActor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let detachedRange = try XCTUnwrap(source.range(of: "let result = await Task.detached(priority: .userInitiated)"))
        let windowEnd = source.index(detachedRange.lowerBound, offsetBy: 320)
        let window = source[detachedRange.lowerBound..<windowEnd]
        XCTAssertTrue(window.contains("stitcher.appendAnalyzed("))
        XCTAssertTrue(window.contains("maxPixelHeight: maxPixelHeight"))
        XCTAssertTrue(window.contains("preferredScrollDirection: preferredScrollDirection"))
    }

    func testFinishStopsAutoScrollBeforeFinalSettledCapture() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let finishRange = try XCTUnwrap(source.range(of: "private func finishAfterCapturingLatestFrame() async"))
        let finalCaptureRange = try XCTUnwrap(source.range(
            of: "await captureAndAppendFrame",
            range: finishRange.upperBound..<source.endIndex
        ))
        let preFinalCaptureWindow = source[finishRange.lowerBound..<finalCaptureRange.lowerBound]
        XCTAssertTrue(preFinalCaptureWindow.contains("let runningAutoScrollTask = autoScrollTask"))
        XCTAssertTrue(preFinalCaptureWindow.contains("stopAutoScroll(health: .good)"))
        XCTAssertTrue(preFinalCaptureWindow.contains("await runningAutoScrollTask.value"))
    }

    func testScrollingCaptureActivatesTargetApplicationBeforeInstallingScrollMonitors() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let activationRange = try XCTUnwrap(source.range(of: "activateTargetApplicationUnderSelection()"))
        let monitorsRange = try XCTUnwrap(source.range(of: "installScrollMonitors()"))
        XCTAssertLessThan(activationRange.lowerBound, monitorsRange.lowerBound)
        XCTAssertTrue(source.contains("NSRunningApplication(processIdentifier: pid)?.activate"))
        XCTAssertTrue(source.contains("pid != currentPID"))
    }

    func testScrollingCaptureDoesNotShowFloatingPanelsByDefault() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("showsControlHUD: Bool = false"))
        XCTAssertTrue(source.contains("showsLivePreview: Bool = false"))
        let showPanelsRange = try XCTUnwrap(
            source.range(
                of: #"private func showPanels\(initialImage: CGImage\) \{[\s\S]*?\n    private func updatePanels"#,
                options: .regularExpression
            )
        )
        let showPanels = String(source[showPanelsRange])
        XCTAssertTrue(showPanels.contains("guard showsControlHUD || showsLivePreview else { return }"))
        XCTAssertTrue(showPanels.contains("if showsControlHUD {"))
        XCTAssertTrue(showPanels.contains("ScrollingScreenshotHUDPanel("))
        XCTAssertTrue(showPanels.contains("guard showsLivePreview else { return }"))
        XCTAssertTrue(showPanels.contains("ScrollingScreenshotPreviewPanel("))
    }

    func testScrollingRegionCaptureExcludesCurrentProcessWindowsByWindowID() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let regionCaptureRange = try XCTUnwrap(source.range(of: "public enum ScrollingScreenshotRegionCapturer"))
        let regionCaptureSource = String(source[regionCaptureRange.lowerBound..<source.endIndex])
        XCTAssertTrue(regionCaptureSource.contains("ScreenCaptureWindowExclusion.currentProcessWindowIDs()"))
        XCTAssertTrue(regionCaptureSource.contains("SCContentFilter(display: display, excludingWindows: excludedWindows)"))
        XCTAssertFalse(regionCaptureSource.contains("excludingApplications: excludedApplications"))
    }

    func testGlobalEscapeCancelsActiveScrollingCapture() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 53)

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(eventMonitor.removedMonitorCount, 5)
    }

    func testCaptureFrameWaitsForStableChecksum() async {
        let first = makeImage(width: 10, height: 10, seed: 1)
        let second = makeImage(width: 10, height: 10, seed: 2)
        let stable = makeImage(width: 10, height: 10, seed: 3)
        var frames = [first, second, stable, stable]
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.removeFirst() },
            eventMonitor: eventMonitor
        )

        let captured = await controller.captureStableFrameForTesting(maxAttempts: 4, initialDelayNanoseconds: 1)

        XCTAssertEqual(captured?.width, stable.width)
        XCTAssertEqual(captured?.height, stable.height)
    }

    func testCaptureFrameReturnsLastFrameWhenNoStablePairAppears() async {
        let first = makeImage(width: 10, height: 10, seed: 1)
        let second = makeImage(width: 10, height: 10, seed: 2)
        var frames = [first, second]
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? second : frames.removeFirst() },
            eventMonitor: eventMonitor
        )

        let captured = await controller.captureStableFrameForTesting(maxAttempts: 2, initialDelayNanoseconds: 1)

        XCTAssertEqual(captured?.width, second.width)
        XCTAssertEqual(captured?.height, second.height)
    }

    func testDuplicatePollingFramesDoNotSurfaceUnstableStatus() async {
        let image = makeImage(width: 10, height: 10, seed: 3)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        var statuses: [ScrollingScreenshotSessionStatus] = []
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            pollingInterval: 0.05,
            eventMonitor: eventMonitor
        )
        controller.onStatusChangedForTesting = { statuses.append($0) }

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()
        try? await Task.sleep(nanoseconds: 200_000_000)

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertFalse(statuses.contains { status in
            if case .unstable = status.health { return true }
            if case .paused = status.health { return true }
            return false
        })
    }

    func testConsecutiveFailedMatchesUpdateStatus() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let failedFrame = makeImage(width: 2, height: 3, seed: 100)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let stitcher = ScrollingScreenshotStitcher(shiftEstimator: { _, _ in nil })
        var statuses: [ScrollingScreenshotSessionStatus] = []
        var captureCount = 0
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                return captureCount <= 2 ? firstFrame : failedFrame
            },
            stitcher: stitcher,
            pollingInterval: 0.05,
            eventMonitor: eventMonitor
        )
        controller.onStatusChangedForTesting = { statuses.append($0) }

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()
        let deadline = Date().addingTimeInterval(1)
        while statuses.allSatisfy({ status in
            if case .unstable = status.health { return false }
            return true
        }), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertTrue(statuses.contains { status in
            if case .unstable(reason: .bandVoteDisagreed, consecutiveFailures: _) = status.health {
                return true
            }
            return false
        })
    }

    func testAutoScrollDoesNotStartWithoutAccessibilityPermission() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: false)
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            autoScroller: autoScroller
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.toggleAutoScrollForTesting()
        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertTrue(autoScroller.postedLines.isEmpty)
    }

    func testAutoScrollPostsTicksWhenPermissionGranted() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            autoScroller: autoScroller
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.toggleAutoScrollForTesting()
        let deadline = Date().addingTimeInterval(1)
        while autoScroller.postedLines.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertFalse(autoScroller.postedLines.isEmpty)
    }

    func testAutoScrollPostsTicksAtSelectionCenterWhenPermissionGranted() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)
        let request = makeRequest()
        let controller = ScrollingScreenshotController(
            request: request,
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            autoScroller: autoScroller
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.toggleAutoScrollForTesting()
        let deadline = Date().addingTimeInterval(1)
        while autoScroller.postedLocations.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertEqual(autoScroller.postedLocations.first, CGPoint(x: 200, y: 200))
    }

    func testAutoScrollUsesMostRecentManualDirectionForTicks() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            autoScroller: autoScroller
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.recordManualScrollDeltaYForTesting(12)
        controller.toggleAutoScrollForTesting()
        let deadline = Date().addingTimeInterval(1)
        while autoScroller.postedLines.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertEqual(autoScroller.postedLines.first, -1)
    }

    func testAutoScrollWaitsForCaptureBeforePostingNextTick() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let scrollFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let autoScroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 1 })
        var captureCount = 0
        var suspendedCapture: CheckedContinuation<CGImage?, Never>?
        var didSuspendCapture = false
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                if captureCount <= 2 {
                    return firstFrame
                }
                if !didSuspendCapture {
                    didSuspendCapture = true
                    return await withCheckedContinuation { continuation in
                        suspendedCapture = continuation
                    }
                }
                return scrollFrame
            },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            eventMonitor: eventMonitor,
            autoScroller: autoScroller
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.toggleAutoScrollForTesting()
        let waitForFirstTick = Date().addingTimeInterval(1)
        while autoScroller.postedLines.isEmpty, Date() < waitForFirstTick {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(autoScroller.postedLines.count, 1)

        let waitForSuspendedCapture = Date().addingTimeInterval(1)
        while suspendedCapture == nil, Date() < waitForSuspendedCapture {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(autoScroller.postedLines.count, 1)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(autoScroller.postedLines.count, 1)

        suspendedCapture?.resume(returning: scrollFrame)
        let waitForSecondTick = Date().addingTimeInterval(1)
        while autoScroller.postedLines.count < 2, Date() < waitForSecondTick {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertGreaterThanOrEqual(autoScroller.postedLines.count, 2)
    }

    func testHeightLimitPausesCaptureUntilUserFinishes() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let scrollFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 2 })
        var statuses: [ScrollingScreenshotSessionStatus] = []
        var frames = [firstFrame, firstFrame, scrollFrame, scrollFrame]
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? scrollFrame : frames.removeFirst() },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            maxPixelHeight: 4,
            eventMonitor: eventMonitor
        )
        controller.onStatusChangedForTesting = { statuses.append($0) }

        var didFinish = false
        let task = Task { @MainActor in
            let result = await controller.start()
            didFinish = true
            return result
        }
        await eventMonitor.waitUntilReady()

        controller.scheduleCaptureForTesting()
        let limitDeadline = Date().addingTimeInterval(1)
        while !statuses.contains(where: { $0.health == .reachedHeightLimit }), Date() < limitDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(stitcher.currentImage?.height, 4)
        XCTAssertTrue(statuses.contains { $0.health == .reachedHeightLimit })
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(didFinish)

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        let result = await task.value
        XCTAssertEqual(result?.image.height, 4)
    }

    func testAutoScrollModeRemovesManualScrollMonitorsWhileRunning() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let startRange = try XCTUnwrap(source.range(of: "private func startAutoScroll()"))
        let taskRange = try XCTUnwrap(source.range(of: "autoScrollTask = Task", range: startRange.upperBound..<source.endIndex))
        let preTaskWindow = source[startRange.lowerBound..<taskRange.lowerBound]
        XCTAssertTrue(preTaskWindow.contains("removeScrollMonitors()"))
    }

    func testAutoScrollModePausesPollingCaptureWhileRunning() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let startRange = try XCTUnwrap(source.range(of: "private func startAutoScroll()"))
        let taskRange = try XCTUnwrap(source.range(of: "autoScrollTask = Task", range: startRange.upperBound..<source.endIndex))
        let preTaskWindow = source[startRange.lowerBound..<taskRange.lowerBound]
        XCTAssertTrue(preTaskWindow.contains("pollingTask?.cancel()"))
        XCTAssertTrue(preTaskWindow.contains("pollingTask = nil"))
    }

    func testStoppingAutoScrollRestoresManualCaptureInputs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift"),
            encoding: .utf8
        )

        let stopRange = try XCTUnwrap(source.range(of: "private func stopAutoScroll"))
        let captureRange = try XCTUnwrap(source.range(of: "private func captureFrame", range: stopRange.upperBound..<source.endIndex))
        let stopWindow = source[stopRange.lowerBound..<captureRange.lowerBound]
        XCTAssertTrue(stopWindow.contains("installScrollMonitors()"))
        XCTAssertTrue(stopWindow.contains("startPollingCapture()"))
    }

    func testManualUpwardScrollDirectionAppliesToNextStitchOnly() async {
        let firstFrame = makeImage(width: 2, height: 3, seed: 10)
        let reversalFrame = makeImage(width: 2, height: 3, seed: 90)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in -1 })
        var frames = [firstFrame, firstFrame, reversalFrame, reversalFrame]
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in frames.isEmpty ? reversalFrame : frames.removeFirst() },
            stitcher: stitcher,
            captureInterval: 0,
            pollingInterval: 10,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        controller.recordManualScrollDeltaYForTesting(12)
        controller.scheduleCaptureForTesting()
        let deadline = Date().addingTimeInterval(1)
        while stitcher.lastScrollDirection != .upward, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value

        XCTAssertEqual(stitcher.lastScrollDirection, .upward)
    }

    func testManualReverseScrollIsConsumedAfterDirectionIsLocked() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            captureInterval: 10,
            pollingInterval: 10,
            eventMonitor: eventMonitor
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        XCTAssertFalse(eventMonitor.emitGlobalScroll(deltaY: -12))
        XCTAssertTrue(eventMonitor.emitGlobalScroll(deltaY: 12))

        eventMonitor.emitGlobalKeyDown(keyCode: 36)
        _ = await task.value
    }

    private func makeRequest() -> ScrollingScreenshotRequest {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            scale: 2,
            isPrimary: true
        )
        return ScrollingScreenshotRequest(
            selection: SelectionState(
                displayFrame: display.frame,
                displayScale: display.scale,
                startPoint: CGPoint(x: 100, y: 100),
                currentPoint: CGPoint(x: 300, y: 300)
            ),
            display: display
        )
    }
}

@MainActor
private final class FakeScrollingScreenshotInputMonitor: ScrollingScreenshotInputMonitoring {
    private var localKeyDownHandlers: [(UInt16) -> Bool] = []
    private var globalKeyDownHandlers: [(UInt16) -> Bool] = []
    private var localLeftMouseDownHandlers: [(Int) -> Bool] = []
    private var globalLeftMouseDownHandlers: [(Int) -> Bool] = []
    private var globalScrollHandlers: [(CGFloat) -> Bool] = []
    private var monitorID = 0

    private(set) var removedMonitorCount = 0

    func addLocalKeyDownMonitor(_ handler: @escaping @MainActor (UInt16) -> Bool) -> Any {
        localKeyDownHandlers.append(handler)
        return nextMonitor()
    }

    func addGlobalKeyDownMonitor(_ handler: @escaping @MainActor (UInt16) -> Bool) -> Any {
        globalKeyDownHandlers.append(handler)
        return nextMonitor()
    }

    func addLocalLeftMouseDownMonitor(_ handler: @escaping @MainActor (Int) -> Bool) -> Any {
        localLeftMouseDownHandlers.append(handler)
        return nextMonitor()
    }

    func addGlobalLeftMouseDownMonitor(_ handler: @escaping @MainActor (Int) -> Bool) -> Any {
        globalLeftMouseDownHandlers.append(handler)
        return nextMonitor()
    }

    func addGlobalScrollWheelMonitor(_ handler: @escaping @MainActor (CGFloat) -> Bool) -> Any {
        globalScrollHandlers.append(handler)
        return nextMonitor()
    }

    func removeMonitor(_ monitor: Any) {
        removedMonitorCount += 1
    }

    func waitUntilReady() async {
        while localKeyDownHandlers.isEmpty ||
            globalKeyDownHandlers.isEmpty ||
            localLeftMouseDownHandlers.isEmpty ||
            globalLeftMouseDownHandlers.isEmpty ||
            globalScrollHandlers.isEmpty {
            await Task.yield()
        }
    }

    func emitGlobalKeyDown(keyCode: UInt16) {
        globalKeyDownHandlers.forEach { _ = $0(keyCode) }
    }

    func emitGlobalLeftMouseDown(clickCount: Int) {
        globalLeftMouseDownHandlers.forEach { _ = $0(clickCount) }
    }

    func emitGlobalScroll(deltaY: CGFloat) -> Bool {
        globalScrollHandlers.reduce(false) { consumed, handler in
            handler(deltaY) || consumed
        }
    }

    private func nextMonitor() -> Any {
        monitorID += 1
        return monitorID
    }
}

private func makeImage(width: Int, height: Int, seed: Int = 0) -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var data = Data(repeating: 0, count: height * bytesPerRow)
    data.withUnsafeMutableBytes { bytes in
        guard let buffer = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                buffer[offset] = UInt8((x + y + seed) % 255)
                buffer[offset + 1] = UInt8((x + seed) % 255)
                buffer[offset + 2] = UInt8((y + seed) % 255)
                buffer[offset + 3] = 255
            }
        }
    }
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
