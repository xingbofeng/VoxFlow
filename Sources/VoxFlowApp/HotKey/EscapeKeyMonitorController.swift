import AppKit
import CoreGraphics

@MainActor
final class EscapeKeyMonitorController {
    typealias LocalEventHandler = @MainActor (UInt16) -> Bool
    typealias GlobalEventHandler = (UInt16) -> Void
    typealias AddLocalMonitor = (@escaping LocalEventHandler) -> Any?
    typealias AddGlobalMonitor = (@escaping GlobalEventHandler) -> Any?
    typealias RemoveMonitor = (Any) -> Void
    typealias ScheduleOnMain = (@escaping @MainActor () -> Void) -> Void

    private let addLocalMonitor: AddLocalMonitor
    private let addGlobalMonitor: AddGlobalMonitor
    private let removeMonitor: RemoveMonitor
    private let scheduleOnMain: ScheduleOnMain

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(
        addLocalMonitor: @escaping AddLocalMonitor = { handler in
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = event.keyCode
                let shouldPassEvent = MainActor.assumeIsolated {
                    handler(keyCode)
                }
                return shouldPassEvent ? event : nil
            }
        },
        addGlobalMonitor: @escaping AddGlobalMonitor = { handler in
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                handler(event.keyCode)
            }
        },
        removeMonitor: @escaping RemoveMonitor = { monitor in
            NSEvent.removeMonitor(monitor)
        },
        scheduleOnMain: @escaping ScheduleOnMain = { action in
            Task { @MainActor in
                action()
            }
        }
    ) {
        self.addLocalMonitor = addLocalMonitor
        self.addGlobalMonitor = addGlobalMonitor
        self.removeMonitor = removeMonitor
        self.scheduleOnMain = scheduleOnMain
    }

    func start(onCancel: @escaping @MainActor () -> Void) {
        AppLogger.general.debug("EscapeKeyMonitorController start")
        stop()
        localMonitor = addLocalMonitor { keyCode in
            guard Self.routesToCancel(keyCode: keyCode) else {
                return true
            }
            AppLogger.general.debug("EscapeKeyMonitorController local cancel route keyCode=\(keyCode)")
            onCancel()
            return false
        }
        globalMonitor = addGlobalMonitor { [scheduleOnMain] keyCode in
            guard Self.routesToCancel(keyCode: keyCode) else { return }
            AppLogger.general.debug("EscapeKeyMonitorController global cancel route keyCode=\(keyCode)")
            scheduleOnMain {
                onCancel()
            }
        }
    }

    func stop() {
        AppLogger.general.debug("EscapeKeyMonitorController stop")
        if let monitor = globalMonitor {
            removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private static func routesToCancel(keyCode: UInt16) -> Bool {
        HotKeyRouter.route(
            keyCode: Int64(keyCode),
            flags: [],
            dictationKeyCode: ShortcutManager.shared.shortcutKeyCode(for: .dictation),
            agentComposeKeyCode: ShortcutManager.shared.shortcutKeyCode(for: .agentCompose)
        ) == .workflowShortcut(.cancel)
    }
}
