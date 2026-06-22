import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
public protocol ScrollingScreenshotInputMonitoring {
    func addLocalKeyDownMonitor(_ handler: @escaping @MainActor (UInt16) -> Bool) -> Any
    func addGlobalKeyDownMonitor(_ handler: @escaping @MainActor (UInt16) -> Bool) -> Any
    func addLocalLeftMouseDownMonitor(_ handler: @escaping @MainActor (Int) -> Bool) -> Any
    func addGlobalLeftMouseDownMonitor(_ handler: @escaping @MainActor (Int) -> Bool) -> Any
    func removeMonitor(_ monitor: Any)
}

@MainActor
public final class AppKitScrollingScreenshotInputMonitor: ScrollingScreenshotInputMonitoring {
    public init() {}

    public func addLocalKeyDownMonitor(_ handler: @escaping @MainActor (UInt16) -> Bool) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event.keyCode) ? nil : event
        } as Any
    }

    public func addGlobalKeyDownMonitor(_ handler: @escaping @MainActor (UInt16) -> Bool) -> Any {
        let tap = ScrollingScreenshotInputEventTap(
            keyDownHandler: handler,
            leftMouseDownHandler: nil
        )
        tap.start()
        return tap
    }

    public func addLocalLeftMouseDownMonitor(_ handler: @escaping @MainActor (Int) -> Bool) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handler(event.clickCount) ? nil : event
        } as Any
    }

    public func addGlobalLeftMouseDownMonitor(_ handler: @escaping @MainActor (Int) -> Bool) -> Any {
        let tap = ScrollingScreenshotInputEventTap(
            keyDownHandler: nil,
            leftMouseDownHandler: handler
        )
        tap.start()
        return tap
    }

    public func removeMonitor(_ monitor: Any) {
        if let eventTap = monitor as? ScrollingScreenshotInputEventTap {
            eventTap.stop()
        } else {
            NSEvent.removeMonitor(monitor)
        }
    }
}

private final class ScrollingScreenshotInputEventTap: @unchecked Sendable {
    private let keyDownHandler: (@MainActor (UInt16) -> Bool)?
    private let leftMouseDownHandler: (@MainActor (Int) -> Bool)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        keyDownHandler: (@MainActor (UInt16) -> Bool)?,
        leftMouseDownHandler: (@MainActor (Int) -> Bool)?
    ) {
        self.keyDownHandler = keyDownHandler
        self.leftMouseDownHandler = leftMouseDownHandler
    }

    func start() {
        guard eventTap == nil else { return }
        let eventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    deinit {
        stop()
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<ScrollingScreenshotInputEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        let shouldConsume: Bool
        switch type {
        case .keyDown:
            guard let handler = tap.keyDownHandler else {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            shouldConsume = tap.callOnMainActor { handler(keyCode) }
        case .leftMouseDown:
            guard let handler = tap.leftMouseDownHandler else {
                return Unmanaged.passUnretained(event)
            }
            let clickCount = Int(event.getIntegerValueField(.mouseEventClickState))
            shouldConsume = tap.callOnMainActor { handler(clickCount) }
        default:
            return Unmanaged.passUnretained(event)
        }
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func callOnMainActor(_ body: @escaping @MainActor () -> Bool) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = body()
                }
            }
            return false
        }
        return MainActor.assumeIsolated {
            body()
        }
    }
}

public struct ScrollingScreenshotConfirmationResult: Equatable, @unchecked Sendable {
    public let image: CGImage?

    public static func accepted(_ image: CGImage) -> Self {
        Self(image: image)
    }

    public static var cancelled: Self {
        Self(image: nil)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.image, rhs.image) {
        case (nil, nil):
            return true
        case (.some(let lhsImage), .some(let rhsImage)):
            return lhsImage.width == rhsImage.width && lhsImage.height == rhsImage.height
        case (.some, nil), (nil, .some):
            return false
        }
    }
}

@MainActor
public protocol ScrollingScreenshotConfirmationPresenting: AnyObject {
    func confirm(image: CGImage, request: ScrollingScreenshotRequest) async -> ScrollingScreenshotConfirmationResult
}

// GPLv3-scoped behavior attribution:
// The manual scroll capture session, HUD, and preview behavior are adapted from sw33tLie/macshot.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: 34c9999625cfe9e8999c00358b3c172dfc00380c
// License: GPLv3

@MainActor
public final class ScrollingScreenshotController {
    public typealias RegionCapture = @MainActor (ScrollingScreenshotRequest) async -> CGImage?

    private let request: ScrollingScreenshotRequest
    private let regionCapture: RegionCapture
    private let stitcher: ScrollingScreenshotStitcher
    private let captureInterval: TimeInterval
    private let pollingInterval: TimeInterval
    private let maxPixelHeight: Int
    private let eventMonitor: any ScrollingScreenshotInputMonitoring
    private let confirmationPresenter: any ScrollingScreenshotConfirmationPresenting
    private let autoScroller: any ScrollingScreenshotAutoScrolling

    private var hudPanel: ScrollingScreenshotHUDPanel?
    private var previewPanel: ScrollingScreenshotPreviewPanel?
    private var localScrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var inputEventMonitors: [Any] = []
    private var captureTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var autoScrollTask: Task<Void, Never>?
    private var finishContinuation: CheckedContinuation<ScrollingScreenshotCaptureResult?, Never>?
    private var lastCaptureTime: TimeInterval = 0
    private var isFinishing = false
    private var isAutoScrolling = false
    private var stripCount = 1
    private var consecutiveFailureCount = 0
    private var consecutiveZeroShiftCount = 0
    private let maxConsecutiveFailuresBeforePause = 6
    private let maxConsecutiveZeroShiftsBeforeEnd = 6

    var onStatusChangedForTesting: ((ScrollingScreenshotSessionStatus) -> Void)?

    public init(
        request: ScrollingScreenshotRequest,
        regionCapture: @escaping RegionCapture = ScrollingScreenshotRegionCapturer.capture,
        stitcher: ScrollingScreenshotStitcher = ScrollingScreenshotStitcher(),
        captureInterval: TimeInterval = 0.15,
        pollingInterval: TimeInterval = 0.25,
        maxPixelHeight: Int = 30_000,
        eventMonitor: any ScrollingScreenshotInputMonitoring = AppKitScrollingScreenshotInputMonitor(),
        confirmationPresenter: any ScrollingScreenshotConfirmationPresenting = ScrollingScreenshotConfirmationPanelPresenter(),
        autoScroller: any ScrollingScreenshotAutoScrolling = AppKitScrollingScreenshotAutoScroller()
    ) {
        self.request = request
        self.regionCapture = regionCapture
        self.stitcher = stitcher
        self.captureInterval = captureInterval
        self.pollingInterval = pollingInterval
        self.maxPixelHeight = maxPixelHeight
        self.eventMonitor = eventMonitor
        self.confirmationPresenter = confirmationPresenter
        self.autoScroller = autoScroller
    }

    public func start() async -> ScrollingScreenshotCaptureResult? {
        guard let firstFrame = await captureFrame() else {
            cleanup()
            return nil
        }

        stitcher.start(with: firstFrame)
        stripCount = 1
        consecutiveFailureCount = 0
        showPanels(initialImage: firstFrame)
        publishStatus(.good)
        installScrollMonitors()
        installInputMonitors()
        startPollingCapture()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finishContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    public func cancel() {
        guard !isFinishing else { return }
        isFinishing = true
        cleanupCaptureSession()
        finishContinuation?.resume(returning: nil)
        finishContinuation = nil
    }

    public func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        Task { @MainActor [weak self] in
            await self?.finishAfterCapturingLatestFrame()
        }
    }

    private func finishAfterCapturingLatestFrame() async {
        removeEventMonitors()
        pollingTask?.cancel()
        pollingTask = nil
        if let captureTask {
            await captureTask.value
        }
        captureTask = nil
        await captureAndAppendFrame()

        guard let image = stitcher.currentImage else {
            closePanels()
            finishContinuation?.resume(returning: nil)
            finishContinuation = nil
            return
        }
        closePanels()
        finishContinuation?.resume(returning: ScrollingScreenshotCaptureResult(image: image))
        finishContinuation = nil
    }

    private func startPollingCapture() {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && !self.isFinishing {
                let interval = max(self.pollingInterval, 0.05)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, !self.isFinishing else { break }
                self.scheduleCapture()
            }
        }
    }

    private func installScrollMonitors() {
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.scheduleCapture()
            return event
        }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.scheduleCapture()
        }
    }

    private func installInputMonitors() {
        inputEventMonitors.append(
            eventMonitor.addLocalKeyDownMonitor { [weak self] keyCode in
                self?.handleKeyDown(keyCode) ?? false
            }
        )
        inputEventMonitors.append(
            eventMonitor.addGlobalKeyDownMonitor { [weak self] keyCode in
                self?.handleKeyDown(keyCode) ?? false
            }
        )
        inputEventMonitors.append(
            eventMonitor.addLocalLeftMouseDownMonitor { [weak self] clickCount in
                self?.handleLeftMouseDown(clickCount: clickCount) ?? false
            }
        )
        inputEventMonitors.append(
            eventMonitor.addGlobalLeftMouseDownMonitor { [weak self] clickCount in
                self?.handleLeftMouseDown(clickCount: clickCount) ?? false
            }
        )
    }

    private func handleKeyDown(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36, 76:
            finish()
            return true
        case 53:
            cancel()
            return true
        default:
            return false
        }
    }

    private func handleLeftMouseDown(clickCount: Int) -> Bool {
        guard clickCount >= 2 else { return false }
        finish()
        return true
    }

    private func scheduleCapture() {
        guard !isFinishing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= captureInterval else { return }
        lastCaptureTime = now
        guard captureTask == nil else { return }

        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.captureTask = nil }
            await self.captureAndAppendFrame()
        }
    }

    private func captureAndAppendFrame() async {
        guard let frame = await captureFrame() else {
            recordFailedAppend(.captureUnavailable)
            return
        }
        let result = stitcher.appendAnalyzed(frame)
        if let stitched = result.image {
            stripCount += 1
            consecutiveFailureCount = 0
            consecutiveZeroShiftCount = 0
            updatePanels(image: stitched, scrollDirection: stitcher.lastScrollDirection)
            publishStatus(stitched.height >= maxPixelHeight ? .reachedHeightLimit : .good)
            if stitched.height >= maxPixelHeight {
                finish()
            }
        } else {
            recordFailedAppend(result.failureReason ?? .shiftNotDetected)
        }
    }

    private func recordFailedAppend(_ reason: ScrollingScreenshotMatchFailureReason) {
        consecutiveFailureCount += 1
        if reason == .duplicateFrame || reason == .shiftTooSmall(0) {
            consecutiveZeroShiftCount += 1
            if isAutoScrolling && consecutiveZeroShiftCount >= maxConsecutiveZeroShiftsBeforeEnd {
                stopAutoScroll(health: .reachedEnd)
                return
            }
        } else {
            consecutiveZeroShiftCount = 0
        }

        if isAutoScrolling && consecutiveFailureCount >= maxConsecutiveFailuresBeforePause {
            stopAutoScroll(health: .paused(reason: reason, consecutiveFailures: consecutiveFailureCount))
            return
        }

        let health: ScrollingScreenshotCaptureHealth = consecutiveFailureCount >= maxConsecutiveFailuresBeforePause
            ? .paused(reason: reason, consecutiveFailures: consecutiveFailureCount)
            : .unstable(reason: reason, consecutiveFailures: consecutiveFailureCount)
        publishStatus(health)
    }

    private func currentStatus(
        health: ScrollingScreenshotCaptureHealth,
        isAutoScrolling: Bool? = nil
    ) -> ScrollingScreenshotSessionStatus {
        ScrollingScreenshotSessionStatus(
            stripCount: stripCount,
            pixelHeight: stitcher.currentImage?.height ?? 0,
            health: health,
            isAutoScrolling: isAutoScrolling ?? self.isAutoScrolling
        )
    }

    private func publishStatus(_ health: ScrollingScreenshotCaptureHealth) {
        let status = currentStatus(health: health)
        hudPanel?.update(status: status, image: stitcher.currentImage, scale: request.selection.displayScale)
        onStatusChangedForTesting?(status)
    }

    func toggleAutoScrollForTesting() {
        toggleAutoScroll()
    }

    private func toggleAutoScroll() {
        if isAutoScrolling {
            stopAutoScroll(health: .good)
        } else {
            startAutoScroll()
        }
    }

    private func startAutoScroll() {
        guard autoScroller.hasAccessibilityPermission else {
            publishStatus(.paused(reason: .captureUnavailable, consecutiveFailures: consecutiveFailureCount))
            return
        }

        isAutoScrolling = true
        publishStatus(.good)
        autoScrollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isAutoScrolling && !self.isFinishing {
                self.autoScroller.postScrollTick(lines: 1)
                self.scheduleCapture()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func stopAutoScroll(health: ScrollingScreenshotCaptureHealth) {
        isAutoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
        guard !isFinishing else { return }
        publishStatus(health)
    }

    private func captureFrame() async -> CGImage? {
        await captureStableFrame(maxAttempts: 10, initialDelayNanoseconds: 30_000_000)
    }

    func captureStableFrameForTesting(
        maxAttempts: Int,
        initialDelayNanoseconds: UInt64
    ) async -> CGImage? {
        await captureStableFrame(maxAttempts: maxAttempts, initialDelayNanoseconds: initialDelayNanoseconds)
    }

    private func captureStableFrame(
        maxAttempts: Int,
        initialDelayNanoseconds: UInt64
    ) async -> CGImage? {
        var previousChecksum: ScrollingScreenshotFrameChecksum?
        var previousFrame: CGImage?
        var delay = initialDelayNanoseconds

        for _ in 0..<max(1, maxAttempts) {
            guard let current = await regionCapture(request) else {
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 3 / 2, 80_000_000)
                continue
            }

            guard let checksum = Self.checksum(for: current) else {
                previousFrame = current
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 3 / 2, 80_000_000)
                continue
            }

            if checksum == previousChecksum {
                return current
            }

            previousChecksum = checksum
            previousFrame = current
            try? await Task.sleep(nanoseconds: delay)
            delay = min(delay * 3 / 2, 80_000_000)
        }

        return previousFrame
    }

    static func checksum(for image: CGImage) -> ScrollingScreenshotFrameChecksum? {
        guard let data = image.dataProvider?.data as Data? else { return nil }
        let rowLength = image.width * 4
        guard image.bitsPerPixel == 32,
              image.bytesPerRow >= rowLength,
              data.count >= image.bytesPerRow * image.height else {
            return nil
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in 0..<image.height {
                let rowBase = base.advanced(by: row * image.bytesPerRow)
                for col in 0..<rowLength {
                    hash ^= UInt64(rowBase[col])
                    hash = hash &* prime
                }
            }
        }

        return ScrollingScreenshotFrameChecksum(
            width: image.width,
            height: image.height,
            bytesPerRow: rowLength,
            value: hash
        )
    }

    private func showPanels(initialImage: CGImage) {
        let hud = ScrollingScreenshotHUDPanel()
        hud.hudView.onCancel = { [weak self] in self?.cancel() }
        hud.hudView.onToggleAutoScroll = { [weak self] in self?.toggleAutoScroll() }
        hud.hudView.onStop = { [weak self] in self?.finish() }
        hud.position(relativeTo: request.selection.normalizedRect, display: request.display)
        hud.orderFrontRegardless()
        hud.update(image: initialImage, scale: request.selection.displayScale)
        hudPanel = hud

        let preview = ScrollingScreenshotPreviewPanel(
            captureRect: request.selection.normalizedRect,
            display: request.display
        )
        preview?.orderFrontRegardless()
        preview?.updatePreview(image: initialImage, scale: request.selection.displayScale, scrollAnchor: .top)
        previewPanel = preview
    }

    private func updatePanels(
        image: CGImage,
        scrollDirection: ScrollingScreenshotScrollDirection?
    ) {
        hudPanel?.update(image: image, scale: request.selection.displayScale)
        let scrollAnchor: ScrollingScreenshotPreviewScrollAnchor = switch scrollDirection {
        case .downward:
            .bottom
        case .upward:
            .top
        case nil:
            .preserve
        }
        previewPanel?.updatePreview(
            image: image,
            scale: request.selection.displayScale,
            scrollAnchor: scrollAnchor
        )
    }

    private func cleanupCaptureSession() {
        stopAutoScroll(health: .good)
        captureTask?.cancel()
        captureTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        removeEventMonitors()
        closePanels()
    }

    private func removeEventMonitors() {
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
            self.localScrollMonitor = nil
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
            self.globalScrollMonitor = nil
        }
        inputEventMonitors.forEach { eventMonitor.removeMonitor($0) }
        inputEventMonitors.removeAll()
    }

    private func closePanels() {
        hudPanel?.close()
        hudPanel = nil
        previewPanel?.close()
        previewPanel = nil
    }

    private func cleanup() {
        cleanupCaptureSession()
    }
}

public enum ScrollingScreenshotRegionCapturer {
    @MainActor
    public static func capture(_ request: ScrollingScreenshotRequest) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else {
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == request.display.id }) else {
                return nil
            }

            let currentPID = NSRunningApplication.current.processIdentifier
            let excludedApplications = content.applications.filter { $0.processID == currentPID }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let sourceRect = request.selection.normalizedRect.offsetBy(
                dx: -request.display.frame.minX,
                dy: -request.display.frame.minY
            )
            let scale = max(request.selection.displayScale, request.display.scale, 1)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = sourceRect
            configuration.width = max(1, Int(sourceRect.width * scale))
            configuration.height = max(1, Int(sourceRect.height * scale))
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.captureResolution = .best
            configuration.colorSpaceName = CGColorSpace.sRGB
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }
}
