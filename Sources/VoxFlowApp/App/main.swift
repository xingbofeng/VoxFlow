import AppKit

AppLogger.general.info("VoxFlow application bootstrap begin")

@MainActor
private enum AppDelegateHolder {
    static let delegate = AppDelegate()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegateHolder.delegate }
app.delegate = delegate
AppLogger.general.debug("Main application delegate configured")
AppPresentationPolicy.logConfiguration()
app.setActivationPolicy(AppPresentationPolicy.activationPolicy)
AppLogger.general.debug("Activation policy set to \(AppPresentationPolicy.activationPolicy)")
AppLogger.general.info("Running application event loop")
app.run()
