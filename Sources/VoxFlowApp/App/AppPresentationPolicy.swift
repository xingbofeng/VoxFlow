import AppKit

enum AppPresentationPolicy {
    private static let log = AppLogger.general

    static let activationPolicy: NSApplication.ActivationPolicy = .regular
    static let workbenchActivationPolicy: NSApplication.ActivationPolicy = .regular
    static let menuBarOnlyActivationPolicy: NSApplication.ActivationPolicy = .accessory
    static let usesMainMenu = true
    static let opensWorkbenchOnLaunch = true
    static let restoresWorkbenchOnReopen = true

    static func presentationPolicyAfterWorkbenchClose(
        hideDockWhenWorkbenchCloses: Bool
    ) -> NSApplication.ActivationPolicy {
        hideDockWhenWorkbenchCloses ? menuBarOnlyActivationPolicy : workbenchActivationPolicy
    }

    static func shouldDismissVoxFlowOverlaysBeforeScreenshotCapture(
        appIsFrontmost: Bool
    ) -> Bool {
        !appIsFrontmost
    }

    static func logConfiguration() {
        log.info(
            "AppPresentationPolicy usesMainMenu=\(usesMainMenu) " +
            "opensWorkbenchOnLaunch=\(opensWorkbenchOnLaunch) " +
            "restoresWorkbenchOnReopen=\(restoresWorkbenchOnReopen)"
        )
    }
}
