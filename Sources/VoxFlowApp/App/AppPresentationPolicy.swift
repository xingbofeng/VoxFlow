import AppKit

enum AppPresentationPolicy {
    private static let log = AppLogger.general

    static let activationPolicy: NSApplication.ActivationPolicy = .regular
    static let usesMainMenu = true
    static let opensWorkbenchOnLaunch = true
    static let restoresWorkbenchOnReopen = true

    static func logConfiguration() {
        log.info(
            "AppPresentationPolicy usesMainMenu=\(usesMainMenu) " +
            "opensWorkbenchOnLaunch=\(opensWorkbenchOnLaunch) " +
            "restoresWorkbenchOnReopen=\(restoresWorkbenchOnReopen)"
        )
    }
}
