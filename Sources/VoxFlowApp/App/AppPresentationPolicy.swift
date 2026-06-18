import AppKit

enum AppPresentationPolicy {
    static let activationPolicy: NSApplication.ActivationPolicy = .regular
    static let usesMainMenu = true
    static let opensWorkbenchOnLaunch = true
    static let restoresWorkbenchOnReopen = true
}
