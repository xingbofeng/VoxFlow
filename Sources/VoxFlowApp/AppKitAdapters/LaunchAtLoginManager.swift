import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    private let logger = AppLogger.general

    var isEnabled: Bool {
        let enabled = SMAppService.mainApp.status == .enabled
        logger.debug("SystemLaunchAtLoginManager isEnabled=\(enabled)")
        return enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        logger.debug("SystemLaunchAtLoginManager setEnabled requested: enabled=\(enabled)")
        if enabled {
            guard SMAppService.mainApp.status != .enabled else {
                logger.debug("SystemLaunchAtLoginManager register skipped: already enabled")
                return
            }
            try SMAppService.mainApp.register()
            logger.info("SystemLaunchAtLoginManager register success")
        } else {
            guard SMAppService.mainApp.status == .enabled else {
                logger.debug("SystemLaunchAtLoginManager unregister skipped: already disabled")
                return
            }
            try SMAppService.mainApp.unregister()
            logger.info("SystemLaunchAtLoginManager unregister success")
        }
    }
}
