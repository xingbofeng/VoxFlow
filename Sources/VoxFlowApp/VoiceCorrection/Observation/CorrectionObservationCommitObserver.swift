import AppKit
import Carbon.HIToolbox
import Foundation

enum CorrectionObservationCommitSignal: Equatable, Sendable {
    case returnKey
    case tabKey
    case activeApplicationChanged
}

enum CorrectionObservationKeyCommitMapper {
    static func signal(forKeyCode keyCode: UInt16) -> CorrectionObservationCommitSignal? {
        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return .returnKey
        case kVK_Tab:
            return .tabKey
        default:
            return nil
        }
    }
}

@MainActor
protocol CorrectionObservationCommitObserving: AnyObject {
    var onSignal: ((CorrectionObservationCommitSignal) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class AppKitCorrectionObservationCommitObserver: CorrectionObservationCommitObserving {
    var onSignal: ((CorrectionObservationCommitSignal) -> Void)?

    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    func start() {
        stop()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSignal?(.activeApplicationChanged)
            }
        }
    }

    func stop() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let signal = CorrectionObservationKeyCommitMapper.signal(forKeyCode: event.keyCode) else {
            return
        }
        onSignal?(signal)
    }
}
