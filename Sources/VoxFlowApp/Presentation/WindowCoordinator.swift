import AppKit

@MainActor
final class WindowCoordinator {
    private static let logger = AppLogger.general
    private let environment: AppEnvironment
    private let asrRuntime: AppASRRuntime
    private let textRuntime: AppTextRuntime
    private let audioCaptureCoordinator: AudioCaptureCoordinator
    private let navigationRouter = WorkbenchNavigationRouter()
    private var mainWindowController: MainWindowController?

    init(
        environment: AppEnvironment,
        asrRuntime: AppASRRuntime,
        textRuntime: AppTextRuntime,
        audioCaptureCoordinator: AudioCaptureCoordinator
    ) {
        self.environment = environment
        self.asrRuntime = asrRuntime
        self.textRuntime = textRuntime
        self.audioCaptureCoordinator = audioCaptureCoordinator
    }

    func showMainWindow() {
        let createdWindow = mainWindowController == nil
        Self.logger.debug("show_main_window createdWindow=\(createdWindow)")
        if mainWindowController == nil {
            mainWindowController = MainWindowController(
                environment: environment,
                asrRuntime: asrRuntime,
                textRuntime: textRuntime,
                audioCaptureCoordinator: audioCaptureCoordinator,
                navigationRouter: navigationRouter
            )
        }
        guard let window = mainWindowController?.window else { return }
        let shouldCenterBeforeFirstReveal = createdWindow
        Self.logger.debug("show_main_window windowIsNil=\(mainWindowController?.window == nil) shouldCenter=\(shouldCenterBeforeFirstReveal)")
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
        Self.logger.debug("show_settings tab=\(tab)")
        showMainWindow()
        navigationRouter.showSettings(tab: tab)
    }

    func refreshScreenshotRecords() {
        mainWindowController?.refreshScreenshotRecords()
    }
}
