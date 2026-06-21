import AppKit

@MainActor
private enum AppDelegateHolder {
    static let delegate = AppDelegate()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegateHolder.delegate }
app.delegate = delegate
app.setActivationPolicy(AppPresentationPolicy.activationPolicy)
app.run()
