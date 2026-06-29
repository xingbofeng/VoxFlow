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
    func addGlobalScrollWheelMonitor(_ handler: @escaping @MainActor (CGFloat) -> Bool) -> Any
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
            leftMouseDownHandler: handler,
            scrollWheelHandler: nil
        )
        tap.start()
        return tap
    }

    public func addGlobalScrollWheelMonitor(_ handler: @escaping @MainActor (CGFloat) -> Bool) -> Any {
        let tap = ScrollingScreenshotInputEventTap(
            keyDownHandler: nil,
            leftMouseDownHandler: nil,
            scrollWheelHandler: handler
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
    private let scrollWheelHandler: (@MainActor (CGFloat) -> Bool)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        keyDownHandler: (@MainActor (UInt16) -> Bool)?,
        leftMouseDownHandler: (@MainActor (Int) -> Bool)?,
        scrollWheelHandler: (@MainActor (CGFloat) -> Bool)? = nil
    ) {
        self.keyDownHandler = keyDownHandler
        self.leftMouseDownHandler = leftMouseDownHandler
        self.scrollWheelHandler = scrollWheelHandler
    }

    func start() {
        guard eventTap == nil else { return }
        var eventMask = CGEventMask(0)
        if keyDownHandler != nil {
            eventMask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
        }
        if leftMouseDownHandler != nil {
            eventMask |= CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        }
        if scrollWheelHandler != nil {
            eventMask |= CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        }
        guard eventMask != 0 else { return }
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
        case .scrollWheel:
            guard let handler = tap.scrollWheelHandler else {
                return Unmanaged.passUnretained(event)
            }
            let deltaY = tap.scrollWheelDeltaY(from: event)
            shouldConsume = tap.callOnMainActor { handler(deltaY) }
        default:
            return Unmanaged.passUnretained(event)
        }
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func scrollWheelDeltaY(from event: CGEvent) -> CGFloat {
        let pointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if abs(pointDelta) > 0.1 {
            return CGFloat(pointDelta)
        }
        let fixedDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        if abs(fixedDelta) > 0.1 {
            return CGFloat(fixedDelta)
        }
        return CGFloat(event.getDoubleValueField(.scrollWheelEventDeltaAxis1))
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

// GPLv3-scoped behavior attribution:
// The manual scroll capture session, HUD, and preview behavior are adapted from sw33tLie/macshot.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: b8ebcb454f957fda011821fbf9c104580592d135
// License: GPLv3

@MainActor
public final class ScrollingScreenshotController {
    public typealias RegionCapture = @MainActor (ScrollingScreenshotRequest) async -> CGImage?

    private enum CaptureMode: Sendable {
        case immediate
        case settled

        var name: String {
            switch self {
            case .immediate: "immediate"
            case .settled: "settled"
            }
        }

        func merged(with other: CaptureMode) -> CaptureMode {
            self == .immediate || other == .immediate ? .immediate : .settled
        }
    }

    private struct ScheduledCapture: Sendable {
        let mode: CaptureMode
        let preferredScrollDirection: ScrollingScreenshotScrollDirection?

        func merged(with other: ScheduledCapture) -> ScheduledCapture {
            ScheduledCapture(
                mode: mode.merged(with: other.mode),
                preferredScrollDirection: other.preferredScrollDirection ?? preferredScrollDirection
            )
        }
    }

    private let request: ScrollingScreenshotRequest
    private let regionCapture: RegionCapture
    private let stitcher: ScrollingScreenshotStitcher
    private let captureInterval: TimeInterval
    private let pollingInterval: TimeInterval
    private let settlementInterval: TimeInterval
    private let maxPixelHeight: Int
    private let eventMonitor: any ScrollingScreenshotInputMonitoring
    private let autoScroller: any ScrollingScreenshotAutoScrolling
    private let showsControlHUD: Bool
    private let showsLivePreview: Bool
    private let activatesTargetApplication: Bool

    private var hudPanel: ScrollingScreenshotHUDPanel?
    private var previewPanel: ScrollingScreenshotPreviewPanel?
    private var localScrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var inputEventMonitors: [Any] = []
    private var captureTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var autoScrollTask: Task<Void, Never>?
    private var settlementTask: Task<Void, Never>?
    private var deferredCaptureTask: Task<Void, Never>?
    private var pendingCapture: ScheduledCapture?
    private var lockedManualScrollDirection: ScrollingScreenshotScrollDirection?
    private var finishContinuation: CheckedContinuation<ScrollingScreenshotCaptureResult?, Never>?
    private var lastCaptureTime: TimeInterval = 0
    private var isFinishing = false
    private var isAutoScrolling = false
    private var pendingManualScrollDirection: ScrollingScreenshotScrollDirection?
    private var stripCount = 1
    private var hasReachedHeightLimit = false
    private var consecutiveFailureCount = 0
    private var consecutiveZeroShiftCount = 0
    private let minConsecutiveFailuresBeforeUnstable = 3
    private let maxConsecutiveFailuresBeforePause = 6
    private let maxConsecutiveZeroShiftsBeforeEnd = 6

    var onStatusChangedForTesting: ((ScrollingScreenshotSessionStatus) -> Void)?

    public init(
        request: ScrollingScreenshotRequest,
        regionCapture: @escaping RegionCapture = ScrollingScreenshotRegionCapturer.capture,
        stitcher: ScrollingScreenshotStitcher = ScrollingScreenshotStitcher(),
        captureInterval: TimeInterval = 0.15,
        pollingInterval: TimeInterval = 0.25,
        settlementInterval: TimeInterval = 0.25,
        maxPixelHeight: Int = 30_000,
        eventMonitor: any ScrollingScreenshotInputMonitoring = AppKitScrollingScreenshotInputMonitor(),
        autoScroller: any ScrollingScreenshotAutoScrolling = AppKitScrollingScreenshotAutoScroller(),
        showsControlHUD: Bool = false,
        showsLivePreview: Bool = false,
        activatesTargetApplication: Bool? = nil
    ) {
        self.request = request
        self.regionCapture = regionCapture
        self.stitcher = stitcher
        self.captureInterval = captureInterval
        self.pollingInterval = pollingInterval
        self.settlementInterval = settlementInterval
        self.maxPixelHeight = maxPixelHeight
        self.eventMonitor = eventMonitor
        self.autoScroller = autoScroller
        self.showsControlHUD = showsControlHUD
        self.showsLivePreview = showsLivePreview
        self.activatesTargetApplication = activatesTargetApplication ?? !Self.isRunningUnderXCTest
    }

    public func start() async -> ScrollingScreenshotCaptureResult? {
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_start selection=\(ScrollingScreenshotDiagnostics.rect(self.request.selection.normalizedRect), privacy: .public) displayFrame=\(ScrollingScreenshotDiagnostics.rect(self.request.display.frame), privacy: .public) overlayFrame=\(ScrollingScreenshotDiagnostics.rect(self.request.display.overlayFrame), privacy: .public)"
        )
        guard let firstFrame = await captureFrame(mode: .settled) else {
            ScrollingScreenshotDiagnostics.logger.warning("scrolling_start_failed firstFrame=nil")
            cleanup()
            return nil
        }

        stitcher.start(with: firstFrame)
        stripCount = 1
        consecutiveFailureCount = 0
        hasReachedHeightLimit = false
        pendingManualScrollDirection = nil
        lockedManualScrollDirection = nil
        pendingCapture = nil
        settlementTask = nil
        deferredCaptureTask = nil
        showPanels(initialImage: firstFrame)
        publishStatus(.good)
        if activatesTargetApplication {
            activateTargetApplicationUnderSelection()
        }
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
        ScrollingScreenshotDiagnostics.logger.info("scrolling_finish_begin current=\(ScrollingScreenshotDiagnostics.size(self.stitcher.currentImage), privacy: .public)")
        let runningAutoScrollTask = autoScrollTask
        stopAutoScroll(health: .good)
        if let runningAutoScrollTask {
            await runningAutoScrollTask.value
        }
        removeEventMonitors()
        pollingTask?.cancel()
        pollingTask = nil
        settlementTask?.cancel()
        settlementTask = nil
        deferredCaptureTask?.cancel()
        deferredCaptureTask = nil
        if let captureTask {
            await captureTask.value
        }
        captureTask = nil
        await captureAndAppendFrame(
            mode: .settled,
            preferredScrollDirection: pendingManualScrollDirection
        )

        guard let image = stitcher.currentImage else {
            ScrollingScreenshotDiagnostics.logger.warning("scrolling_finish_no_image")
            closePanels()
            finishContinuation?.resume(returning: nil)
            finishContinuation = nil
            return
        }
        closePanels()
        ScrollingScreenshotDiagnostics.logger.info("scrolling_finish_completed image=\(ScrollingScreenshotDiagnostics.size(image), privacy: .public)")
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
                guard self.settlementTask == nil else { continue }
                self.scheduleCapture(mode: .settled)
            }
        }
    }

    private func installScrollMonitors() {
        if localScrollMonitor == nil {
            localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                ScrollingScreenshotDiagnostics.logger.debug(
                    "scrolling_event localScroll deltaX=\(event.scrollingDeltaX, privacy: .public) deltaY=\(event.scrollingDeltaY, privacy: .public)"
                )
                return self?.handleManualScroll(deltaY: event.scrollingDeltaY) == true ? nil : event
            }
        }

        if globalScrollMonitor == nil {
            globalScrollMonitor = eventMonitor.addGlobalScrollWheelMonitor { [weak self] deltaY in
                ScrollingScreenshotDiagnostics.logger.debug(
                    "scrolling_event globalScroll deltaY=\(deltaY, privacy: .public)"
                )
                return self?.handleManualScroll(deltaY: deltaY) ?? false
            }
        }
    }

    private func activateTargetApplicationUnderSelection() {
        let selectionCenter = CGPoint(
            x: request.selection.normalizedRect.midX,
            y: request.selection.normalizedRect.midY
        )
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }

        let currentPID = NSRunningApplication.current.processIdentifier
        for windowInfo in windowInfoList {
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let ownerPID = Self.integer(windowInfo[kCGWindowOwnerPID as String]),
                  let x = Self.number(bounds["X"]),
                  let y = Self.number(bounds["Y"]),
                  let width = Self.number(bounds["Width"]),
                  let height = Self.number(bounds["Height"]) else {
                continue
            }

            let pid = pid_t(ownerPID)
            guard pid != currentPID else { continue }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            guard frame.contains(selectionCenter) else { continue }

            let activated = NSRunningApplication(processIdentifier: pid)?.activate() ?? false
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_target_activate pid=\(pid, privacy: .public) activated=\(activated, privacy: .public)"
            )
            return
        }

        ScrollingScreenshotDiagnostics.logger.info("scrolling_target_activate skipped=no_window")
    }

    private static func number(_ value: Any?) -> CGFloat? {
        switch value {
        case let value as CGFloat:
            value
        case let value as Double:
            CGFloat(value)
        case let value as Float:
            CGFloat(value)
        case let value as Int:
            CGFloat(value)
        case let value as NSNumber:
            CGFloat(truncating: value)
        default:
            nil
        }
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as NSNumber:
            value.intValue
        default:
            nil
        }
    }

    func handleManualScrollForTesting(deltaY: CGFloat) {
        handleManualScroll(deltaY: deltaY)
    }

    @discardableResult
    private func handleManualScroll(deltaY: CGFloat) -> Bool {
        guard let direction = Self.scrollDirection(forDeltaY: deltaY) else { return false }
        if let lockedManualScrollDirection, direction != lockedManualScrollDirection {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_reverse_scroll_consumed locked=\(String(describing: lockedManualScrollDirection), privacy: .public) attempted=\(String(describing: direction), privacy: .public) deltaY=\(deltaY, privacy: .public)"
            )
            return true
        }
        recordManualScrollDirection(direction, deltaY: deltaY)
        scheduleCapture(mode: .immediate)
        scheduleSettledCaptureAfterManualScroll()
        return false
    }

    func recordManualScrollDeltaYForTesting(_ deltaY: CGFloat) {
        guard let direction = Self.scrollDirection(forDeltaY: deltaY) else { return }
        recordManualScrollDirection(direction, deltaY: deltaY)
    }

    private static func scrollDirection(forDeltaY deltaY: CGFloat) -> ScrollingScreenshotScrollDirection? {
        guard abs(deltaY) > 0.1 else { return nil }
        return deltaY > 0 ? .upward : .downward
    }

    private func recordManualScrollDirection(
        _ direction: ScrollingScreenshotScrollDirection,
        deltaY: CGFloat
    ) {
        if lockedManualScrollDirection == nil {
            lockedManualScrollDirection = direction
        }
        pendingManualScrollDirection = direction
        ScrollingScreenshotDiagnostics.logger.debug(
            "scrolling_manual_direction deltaY=\(deltaY, privacy: .public) direction=\(String(describing: direction), privacy: .public) locked=\(String(describing: self.lockedManualScrollDirection), privacy: .public)"
        )
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

    private func scheduleCapture(mode: CaptureMode = .settled) {
        guard !isFinishing, !hasReachedHeightLimit else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= captureInterval else {
            if mode == .immediate {
                queuePendingCapture(ScheduledCapture(
                    mode: mode,
                    preferredScrollDirection: pendingManualScrollDirection
                ))
                scheduleDeferredCapture(after: captureInterval - (now - lastCaptureTime))
            }
            ScrollingScreenshotDiagnostics.logger.debug("scrolling_schedule_skip interval mode=\(mode.name, privacy: .public)")
            return
        }
        lastCaptureTime = now
        guard captureTask == nil else {
            queuePendingCapture(ScheduledCapture(
                mode: mode,
                preferredScrollDirection: pendingManualScrollDirection
            ))
            ScrollingScreenshotDiagnostics.logger.debug("scrolling_schedule_skip activeTask mode=\(mode.name, privacy: .public)")
            return
        }

        ScrollingScreenshotDiagnostics.logger.debug("scrolling_schedule_capture mode=\(mode.name, privacy: .public)")
        let capture = pendingCapture?.merged(with: ScheduledCapture(
            mode: mode,
            preferredScrollDirection: pendingManualScrollDirection
        ))
        ?? ScheduledCapture(
            mode: mode,
            preferredScrollDirection: pendingManualScrollDirection
        )
        pendingCapture = nil
        deferredCaptureTask?.cancel()
        deferredCaptureTask = nil
        launchCapture(capture)
    }

    private func queuePendingCapture(_ capture: ScheduledCapture) {
        pendingCapture = pendingCapture?.merged(with: capture) ?? capture
    }

    private func scheduleDeferredCapture(after interval: TimeInterval) {
        guard deferredCaptureTask == nil else { return }
        let interval = max(interval, 0.01)
        deferredCaptureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.isFinishing else { return }
            self.deferredCaptureTask = nil
            guard self.captureTask == nil, let pendingCapture = self.pendingCapture else {
                return
            }
            self.pendingCapture = nil
            self.lastCaptureTime = ProcessInfo.processInfo.systemUptime
            ScrollingScreenshotDiagnostics.logger.debug(
                "scrolling_schedule_run_deferred mode=\(pendingCapture.mode.name, privacy: .public)"
            )
            self.launchCapture(pendingCapture)
        }
    }

    private func scheduleSettledCaptureAfterManualScroll() {
        settlementTask?.cancel()
        let interval = max(settlementInterval, 0.01)
        settlementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.isFinishing else { return }
            self.settlementTask = nil
            self.scheduleCapture(mode: .settled)
        }
    }

    private func launchCapture(_ scheduledCapture: ScheduledCapture) {
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.captureAndAppendFrame(
                mode: scheduledCapture.mode,
                preferredScrollDirection: scheduledCapture.preferredScrollDirection
            )
            self.captureTask = nil
            guard !self.isFinishing, let pendingCapture = self.pendingCapture else {
                return
            }
            self.pendingCapture = nil
            self.deferredCaptureTask?.cancel()
            self.deferredCaptureTask = nil
            self.lastCaptureTime = ProcessInfo.processInfo.systemUptime
            ScrollingScreenshotDiagnostics.logger.debug(
                "scrolling_schedule_run_pending mode=\(pendingCapture.mode.name, privacy: .public)"
            )
            self.launchCapture(pendingCapture)
        }
    }

    func scheduleCaptureForTesting() {
        scheduleCapture(mode: .settled)
    }

    private func captureAndAppendFrame(
        mode: CaptureMode = .settled,
        preferredScrollDirection: ScrollingScreenshotScrollDirection? = nil
    ) async {
        guard !hasReachedHeightLimit else { return }
        guard let frame = await captureFrame(mode: mode) else {
            ScrollingScreenshotDiagnostics.logger.warning("scrolling_append_capture_failed")
            recordFailedAppend(.captureUnavailable)
            return
        }
        let stitcher = stitcher
        let maxPixelHeight = maxPixelHeight
        let result = await Task.detached(priority: .userInitiated) {
            stitcher.appendAnalyzed(
                frame,
                maxPixelHeight: maxPixelHeight,
                preferredScrollDirection: preferredScrollDirection
            )
        }.value
        if let stitched = result.image {
            if preferredScrollDirection == pendingManualScrollDirection {
                pendingManualScrollDirection = nil
            }
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_append_ok mode=\(mode.name, privacy: .public) frame=\(ScrollingScreenshotDiagnostics.size(frame), privacy: .public) stitched=\(ScrollingScreenshotDiagnostics.size(stitched), privacy: .public) rows=\(result.estimate?.rows ?? 0, privacy: .public)"
            )
            stripCount += 1
            consecutiveFailureCount = 0
            consecutiveZeroShiftCount = 0
            updatePanels(image: stitched, scrollDirection: stitcher.lastScrollDirection)
            if stitched.height >= maxPixelHeight {
                hasReachedHeightLimit = true
                if isAutoScrolling {
                    stopAutoScroll(health: .reachedHeightLimit)
                } else {
                    publishStatus(.reachedHeightLimit)
                }
            } else {
                publishStatus(.good)
            }
        } else {
            ScrollingScreenshotDiagnostics.logger.info(
                "scrolling_append_skip frame=\(ScrollingScreenshotDiagnostics.size(frame), privacy: .public) reason=\(String(describing: result.failureReason), privacy: .public)"
            )
            recordFailedAppend(result.failureReason ?? .shiftNotDetected)
        }
    }

    private func recordFailedAppend(_ reason: ScrollingScreenshotMatchFailureReason) {
        if reason == .duplicateFrame || reason == .shiftTooSmall(0) {
            consecutiveZeroShiftCount += 1
            if isAutoScrolling && consecutiveZeroShiftCount >= maxConsecutiveZeroShiftsBeforeEnd {
                stopAutoScroll(health: .reachedEnd)
                return
            }
            return
        } else {
            consecutiveZeroShiftCount = 0
        }

        consecutiveFailureCount += 1
        if isAutoScrolling && consecutiveFailureCount >= maxConsecutiveFailuresBeforePause {
            stopAutoScroll(health: .paused(reason: reason, consecutiveFailures: consecutiveFailureCount))
            return
        }
        guard consecutiveFailureCount >= minConsecutiveFailuresBeforeUnstable else {
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
            ScrollingScreenshotDiagnostics.logger.warning(
                "scrolling_autoscroll_blocked reason=accessibility_permission"
            )
            autoScroller.requestAccessibilityPermissionPrompt()
            publishStatus(.paused(reason: .captureUnavailable, consecutiveFailures: consecutiveFailureCount))
            return
        }
        guard autoScrollTask == nil else { return }

        removeScrollMonitors()
        pollingTask?.cancel()
        pollingTask = nil
        settlementTask?.cancel()
        settlementTask = nil
        deferredCaptureTask?.cancel()
        deferredCaptureTask = nil
        pendingCapture = nil
        isAutoScrolling = true
        publishStatus(.good)
        let scrollLocation = CGPoint(
            x: request.selection.normalizedRect.midX,
            y: request.selection.normalizedRect.midY
        )
        let scrollDirection = pendingManualScrollDirection ?? lockedManualScrollDirection ?? .downward
        let scrollLines: Int32 = scrollDirection == .downward ? 1 : -1
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_autoscroll_start direction=\(String(describing: scrollDirection), privacy: .public) location=x=\(scrollLocation.x, privacy: .public) y=\(scrollLocation.y, privacy: .public)"
        )
        autoScrollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let captureTask = self.captureTask {
                await captureTask.value
                self.captureTask = nil
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            while !Task.isCancelled && self.isAutoScrolling && !self.isFinishing {
                self.autoScroller.postScrollTick(lines: scrollLines, at: scrollLocation)
                await self.captureAndAppendFrame(
                    mode: .settled,
                    preferredScrollDirection: scrollDirection
                )
                guard !Task.isCancelled, self.isAutoScrolling, !self.isFinishing else { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func stopAutoScroll(health: ScrollingScreenshotCaptureHealth) {
        let wasAutoScrolling = isAutoScrolling
        isAutoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
        guard !isFinishing else { return }
        if wasAutoScrolling {
            installScrollMonitors()
            startPollingCapture()
        }
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_autoscroll_stop health=\(String(describing: health), privacy: .public)"
        )
        publishStatus(health)
    }

    private func captureFrame(mode: CaptureMode) async -> CGImage? {
        switch mode {
        case .immediate:
            await regionCapture(request)
        case .settled:
            await captureStableFrame(maxAttempts: 10, initialDelayNanoseconds: 30_000_000)
        }
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

            guard let checksum = await Self.checksum(for: current) else {
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

    nonisolated static func checksum(for image: CGImage) async -> ScrollingScreenshotFrameChecksum? {
        await Task.detached(priority: .userInitiated) {
            checksumSync(for: image)
        }.value
    }

    nonisolated private static func checksumSync(for image: CGImage) -> ScrollingScreenshotFrameChecksum? {
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
        ScrollingScreenshotDiagnostics.logger.info("scrolling_show_panels initial=\(ScrollingScreenshotDiagnostics.size(initialImage), privacy: .public)")
        guard showsControlHUD || showsLivePreview else { return }

        if showsControlHUD {
            let hud = ScrollingScreenshotHUDPanel()
            hud.hudView.onCancel = { [weak self] in self?.cancel() }
            hud.hudView.onToggleAutoScroll = { [weak self] in self?.toggleAutoScroll() }
            hud.hudView.onStop = { [weak self] in self?.finish() }
            hud.position(relativeTo: request.selection.normalizedRect, display: request.display)
            hud.orderFrontRegardless()
            hud.update(image: initialImage, scale: request.selection.displayScale)
            hudPanel = hud
        }

        guard showsLivePreview else { return }
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
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_update_panels image=\(ScrollingScreenshotDiagnostics.size(image), privacy: .public) direction=\(String(describing: scrollDirection), privacy: .public) hasPreview=\(self.previewPanel != nil, privacy: .public)"
        )
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
        pendingCapture = nil
        deferredCaptureTask?.cancel()
        deferredCaptureTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        settlementTask?.cancel()
        settlementTask = nil
        removeEventMonitors()
        closePanels()
    }

    private func removeEventMonitors() {
        removeScrollMonitors()
        inputEventMonitors.forEach { eventMonitor.removeMonitor($0) }
        inputEventMonitors.removeAll()
    }

    private func removeScrollMonitors() {
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
            self.localScrollMonitor = nil
        }
        if let globalScrollMonitor {
            eventMonitor.removeMonitor(globalScrollMonitor)
            self.globalScrollMonitor = nil
        }
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

            let ownWindowIDs = Set(ScreenCaptureWindowExclusion.currentProcessWindowIDs())
            let excludedWindows = content.windows.filter { window in
                ownWindowIDs.contains(window.windowID)
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
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
