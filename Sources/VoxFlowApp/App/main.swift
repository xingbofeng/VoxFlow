import AppKit

@MainActor
private enum AppRuntime {
    static let delegate = AppDelegate()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppRuntime.delegate }
app.delegate = delegate
app.setActivationPolicy(AppPresentationPolicy.activationPolicy)
app.run()
