import AppKit

@MainActor
final class WindowCoordinator {
    private let environment: AppEnvironment
    private var mainWindowController: MainWindowController?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func showMainWindow() {
        let createdWindow = mainWindowController == nil
        if mainWindowController == nil {
            mainWindowController = MainWindowController(environment: environment)
        }
        guard let window = mainWindowController?.window else { return }
        let shouldCenterBeforeFirstReveal = createdWindow
        NSApp.activate(ignoringOtherApps: true)
        if createdWindow {
            // AppKit can adjust a newly ordered SwiftUI window on its first pass.
            // Keep that pass hidden, then reveal only after the final centered frame.
            window.alphaValue = 0
            WindowPlacementPolicy.centerOnMainScreen(window)
        } else {
            WindowPlacementPolicy.placeOnVisibleScreenIfNeeded(window)
        }
        window.makeKeyAndOrderFront(nil)
        if shouldCenterBeforeFirstReveal {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak window] in
                guard let window else { return }
                WindowPlacementPolicy.centerOnMainScreen(window)
                window.alphaValue = 1
            }
        } else {
            WindowPlacementPolicy.placeOnVisibleScreenIfNeeded(window)
        }
    }

    func showSettings(tab: SettingsTab = .asr) {
        showMainWindow()
    }
}
