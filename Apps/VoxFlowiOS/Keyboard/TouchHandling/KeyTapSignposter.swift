// DictusKeyboard/TouchHandling/KeyTapSignposter.swift
import os

/// OSSignposter instrumentation for keyboard touch pipeline latency measurement.
///
/// WHY OSSignposter (not print timestamps):
/// OSSignposter integrates with Xcode Instruments for sub-microsecond precision,
/// visual timeline display, and zero runtime overhead when not actively profiling.
/// This is Apple's recommended approach for performance measurement.
///
/// USAGE: Profile on physical device with:
/// Xcode > Product > Profile (Cmd+I) > Blank template > Add "os_signpost" instrument
/// Type rapidly for 10+ seconds, then analyze signpost intervals.
///
/// TARGET LATENCIES from issue #44:
/// - T1 (touchDown -> highlight): <= 16.67ms (one frame at 60fps)
/// - T2 (touchDown -> haptic): <= 16.67ms
/// - T3 (touchUp -> insertText): <= 33ms (two frames)
enum KeyTapSignposter {
    private static let signposter = OSSignposter(
        subsystem: "com.mashangxie.ios.keyboard",
        category: "KeyPress"
    )

    /// Begin a touchDown interval. Returns a state to pass to endTouchDown.
    static func beginTouchDown() -> OSSignpostIntervalState {
        let id = signposter.makeSignpostID()
        return signposter.beginInterval("touchDown", id: id)
    }

    /// Emit an event marking when highlight (visual feedback) occurred within a touchDown interval.
    static func emitHighlight(_ state: OSSignpostIntervalState) {
        signposter.emitEvent("highlight")
    }

    /// Emit an event marking when haptic feedback fired within a touchDown interval.
    static func emitHaptic(_ state: OSSignpostIntervalState) {
        signposter.emitEvent("haptic")
    }

    /// End the touchDown interval (all touchDown work complete).
    static func endTouchDown(_ state: OSSignpostIntervalState) {
        signposter.endInterval("touchDown", state)
    }

    /// Begin a touchUp interval. Returns state for endTouchUp.
    static func beginTouchUp() -> OSSignpostIntervalState {
        let id = signposter.makeSignpostID()
        return signposter.beginInterval("touchUp", id: id)
    }

    /// End the touchUp interval (insertText complete).
    static func endTouchUp(_ state: OSSignpostIntervalState) {
        signposter.endInterval("touchUp", state)
    }
}
