@preconcurrency import Cocoa
import CoreGraphics

fileprivate let _kAXPrompt: String = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

enum PasteLastResultShortcut {
    static let keyCode: Int64 = 0x09

    static func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Self.keyCode
            && flags.contains(.maskCommand)
            && flags.contains(.maskShift)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
    }
}

final class PasteLastResultHotKeyMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onPasteLastResult: (() -> Void)?

    @MainActor
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let options = [_kAXPrompt: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return false
        }

        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PasteLastResultHotKeyMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard PasteLastResultShortcut.matches(keyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }

        let passThrough = MainActor.assumeIsolated {
            let appBundleID = Bundle.main.bundleIdentifier ?? ProductBrand.bundleIdentifier
            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return ShortcutEventRouting.shouldPassThrough(
                appIsActive: NSApp.isActive,
                appIsFrontmost: frontmostBundleID == appBundleID,
                isCapturingShortcut: ShortcutCaptureState.shared.isCapturing
            )
        }
        if passThrough {
            return Unmanaged.passUnretained(event)
        }

        let handler = onPasteLastResult
        DispatchQueue.main.async {
            handler?()
        }
        return nil
    }
}
