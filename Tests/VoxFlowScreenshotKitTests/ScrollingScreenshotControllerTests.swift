import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotControllerTests: XCTestCase {
    func testGlobalReturnKeyFinishesActiveCapture() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let confirmationPresenter = FakeScrollingScreenshotConfirmationPresenter()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            confirmationPresenter: confirmationPresenter
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 36)

        let result = await task.value
        XCTAssertEqual(result, ScrollingScreenshotCaptureResult(image: image))
        XCTAssertEqual(eventMonitor.removedMonitorCount, 4)
        XCTAssertNil(confirmationPresenter.requestedImage)
    }

    func testGlobalDoubleClickFinishesActiveCapture() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let confirmationPresenter = FakeScrollingScreenshotConfirmationPresenter()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            confirmationPresenter: confirmationPresenter
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalLeftMouseDown(clickCount: 2)

        let result = await task.value
        XCTAssertEqual(result, ScrollingScreenshotCaptureResult(image: image))
        XCTAssertEqual(eventMonitor.removedMonitorCount, 4)
        XCTAssertNil(confirmationPresenter.requestedImage)
    }

    func testFinishCapturesAndStitchesLatestFrameBeforeConfirmation() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let finalFrame = makeImage(width: 2, height: 3, seed: 40)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let confirmationPresenter = FakeScrollingScreenshotConfirmationPresenter()
        let stitcher = ScrollingScreenshotStitcher(shiftDetector: { _, _ in 1 })
        var captureCount = 0
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in
                captureCount += 1
                return captureCount <= 2 ? firstFrame : finalFrame
            },
            stitcher: stitcher,
            eventMonitor: eventMonitor,
            confirmationPresenter: confirmationPresenter
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 36)

        let result = await task.value
        XCTAssertEqual(result?.image.height, 4)
        XCTAssertNil(confirmationPresenter.requestedImage)
    }

    func testPollingCapturesAndStitchesWithoutScrollEvent() async {
        let firstFrame = makeImage(width: 2, height: 3)
        let scrolledFrame = makeImage(width: 2, height: 3, seed: 80)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let confirmationPresenter = FakeScrollingScreenshotConfirmationPresenter()
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
            eventMonitor: eventMonitor,
            confirmationPresenter: confirmationPresenter
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
        XCTAssertNil(confirmationPresenter.requestedImage)
    }

    func testGlobalEscapeCancelsActiveScrollingCapture() async {
        let image = makeImage(width: 120, height: 160)
        let eventMonitor = FakeScrollingScreenshotInputMonitor()
        let confirmationPresenter = FakeScrollingScreenshotConfirmationPresenter()
        let controller = ScrollingScreenshotController(
            request: makeRequest(),
            regionCapture: { _ in image },
            eventMonitor: eventMonitor,
            confirmationPresenter: confirmationPresenter
        )

        let task = Task { await controller.start() }
        await eventMonitor.waitUntilReady()

        eventMonitor.emitGlobalKeyDown(keyCode: 53)

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(eventMonitor.removedMonitorCount, 4)
        XCTAssertNil(confirmationPresenter.requestedImage)
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
            eventMonitor: eventMonitor,
            confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter()
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
            eventMonitor: eventMonitor,
            confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter()
        )

        let captured = await controller.captureStableFrameForTesting(maxAttempts: 2, initialDelayNanoseconds: 1)

        XCTAssertEqual(captured?.width, second.width)
        XCTAssertEqual(captured?.height, second.height)
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
            eventMonitor: eventMonitor,
            confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter()
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
            confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter(),
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
            confirmationPresenter: FakeScrollingScreenshotConfirmationPresenter(),
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
private final class FakeScrollingScreenshotConfirmationPresenter: ScrollingScreenshotConfirmationPresenting {
    private var continuation: CheckedContinuation<ScrollingScreenshotConfirmationResult, Never>?
    private(set) var requestedImage: CGImage?

    func confirm(
        image: CGImage,
        request: ScrollingScreenshotRequest
    ) async -> ScrollingScreenshotConfirmationResult {
        requestedImage = image
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilConfirmationRequested() async {
        while requestedImage == nil || continuation == nil {
            await Task.yield()
        }
    }

    func complete(with action: ScrollingScreenshotConfirmationResult) {
        continuation?.resume(returning: action)
        continuation = nil
    }
}

@MainActor
private final class FakeScrollingScreenshotInputMonitor: ScrollingScreenshotInputMonitoring {
    private var localKeyDownHandlers: [(UInt16) -> Bool] = []
    private var globalKeyDownHandlers: [(UInt16) -> Bool] = []
    private var localLeftMouseDownHandlers: [(Int) -> Bool] = []
    private var globalLeftMouseDownHandlers: [(Int) -> Bool] = []
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

    func removeMonitor(_ monitor: Any) {
        removedMonitorCount += 1
    }

    func waitUntilReady() async {
        while localKeyDownHandlers.isEmpty ||
            globalKeyDownHandlers.isEmpty ||
            localLeftMouseDownHandlers.isEmpty ||
            globalLeftMouseDownHandlers.isEmpty {
            await Task.yield()
        }
    }

    func emitGlobalKeyDown(keyCode: UInt16) {
        globalKeyDownHandlers.forEach { _ = $0(keyCode) }
    }

    func emitGlobalLeftMouseDown(clickCount: Int) {
        globalLeftMouseDownHandlers.forEach { _ = $0(clickCount) }
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
