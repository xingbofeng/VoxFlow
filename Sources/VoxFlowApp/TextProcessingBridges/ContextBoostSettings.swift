import Foundation

enum ContextBoostSettings {
    static let enabledDefaultsKey = "ContextBoost_CurrentWindowOCREnabled"
    static let defaultEnabled = false

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledDefaultsKey) as? Bool ?? defaultEnabled
    }
}

private final class ContextBoostSuppressionStore: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: Set<String> = []

    func setSuppressed(_ suppressed: Bool, reason: String) {
        lock.lock()
        defer { lock.unlock() }
        if suppressed {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }
    }

    func isSuppressed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !reasons.isEmpty
    }
}

enum ContextBoostSuppression {
    private static let store = ContextBoostSuppressionStore()

    static func setSuppressed(_ suppressed: Bool, reason: String) {
        store.setSuppressed(suppressed, reason: reason)
    }

    static func isSuppressed() -> Bool {
        store.isSuppressed()
    }
}
