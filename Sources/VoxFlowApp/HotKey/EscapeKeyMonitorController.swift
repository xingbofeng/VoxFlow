import AppKit

enum EscapeEventRouting {
    static func isEscapeKey(_ keyCode: UInt16) -> Bool {
        keyCode == 53
    }
}

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
        stop()
        localMonitor = addLocalMonitor { keyCode in
            guard EscapeEventRouting.isEscapeKey(keyCode) else {
                return true
            }
            onCancel()
            return false
        }
        globalMonitor = addGlobalMonitor { [scheduleOnMain] keyCode in
            guard EscapeEventRouting.isEscapeKey(keyCode) else { return }
            scheduleOnMain {
                onCancel()
            }
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
