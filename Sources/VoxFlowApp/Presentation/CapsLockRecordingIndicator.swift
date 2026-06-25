import Foundation
import IOKit
import IOKit.hidsystem

@MainActor
final class CapsLockRecordingIndicator {
    private static let logger = AppLogger.audio

    private let readCapsLockState: () -> Bool?
    private let writeCapsLockState: (Bool) -> Bool
    private var originalState: Bool?
    private var isActive = false

    init(
        readCapsLockState: @escaping () -> Bool?,
        writeCapsLockState: @escaping (Bool) -> Bool
    ) {
        self.readCapsLockState = readCapsLockState
        self.writeCapsLockState = writeCapsLockState
    }

    static func live() -> CapsLockRecordingIndicator {
        let client = HIDCapsLockStateClient()
        return CapsLockRecordingIndicator(
            readCapsLockState: { client.currentState() },
            writeCapsLockState: { client.setState($0) }
        )
    }

    func setActive(_ active: Bool) {
        if active {
            begin()
        } else {
            end()
        }
    }

    private func begin() {
        guard !isActive else { return }
        guard let currentState = readCapsLockState() else {
            Self.logger.warning("CapsLock recording indicator skipped because current state could not be read.")
            return
        }
        guard writeCapsLockState(true) else {
            Self.logger.warning("CapsLock recording indicator could not enable CapsLock state.")
            return
        }
        originalState = currentState
        isActive = true
    }

    private func end() {
        guard isActive, let originalState else { return }
        guard writeCapsLockState(originalState) else {
            Self.logger.warning("CapsLock recording indicator could not restore CapsLock state.")
            return
        }
        self.originalState = nil
        isActive = false
    }
}

private struct HIDCapsLockStateClient {
    private static let logger = AppLogger.audio

    func currentState() -> Bool? {
        guard let connection = openConnection() else { return nil }
        defer { IOServiceClose(connection) }

        var state = false
        let result = IOHIDGetModifierLockState(
            connection,
            Int32(kIOHIDCapsLockState),
            &state
        )
        guard result == KERN_SUCCESS else {
            Self.logger.warning("IOHIDGetModifierLockState failed result=\(result)")
            return nil
        }
        return state
    }

    func setState(_ enabled: Bool) -> Bool {
        guard let connection = openConnection() else { return false }
        defer { IOServiceClose(connection) }

        let result = IOHIDSetModifierLockState(
            connection,
            Int32(kIOHIDCapsLockState),
            enabled
        )
        guard result == KERN_SUCCESS else {
            Self.logger.warning("IOHIDSetModifierLockState failed result=\(result)")
            return false
        }
        return true
    }

    private func openConnection() -> io_connect_t? {
        guard let matching = IOServiceMatching(kIOHIDSystemClass) else {
            Self.logger.warning("IOServiceMatching failed for IOHIDSystem.")
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            Self.logger.warning("IOServiceGetMatchingService did not find IOHIDSystem.")
            return nil
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(
            service,
            mach_task_self_,
            UInt32(kIOHIDParamConnectType),
            &connection
        )
        guard result == KERN_SUCCESS else {
            Self.logger.warning("IOServiceOpen failed for IOHIDSystem result=\(result)")
            return nil
        }
        return connection
    }
}
