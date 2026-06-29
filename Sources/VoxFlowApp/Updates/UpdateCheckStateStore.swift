import Foundation

final class UpdateCheckStateStore {
    private enum Key {
        static let lastAutomaticCheckAt = "VoxFlow.UpdateCheck.lastAutomaticCheckAt"
        static let lastAutomaticCheckVersion = "VoxFlow.UpdateCheck.lastAutomaticCheckVersion"
        static let ignoredVersion = "VoxFlow.UpdateCheck.ignoredVersion"
        static let deferredVersion = "VoxFlow.UpdateCheck.deferredVersion"
        static let deferredUntil = "VoxFlow.UpdateCheck.deferredUntil"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastAutomaticCheckAt: Date? {
        get {
            defaults.object(forKey: Key.lastAutomaticCheckAt) as? Date
        }
        set {
            setOptional(newValue, forKey: Key.lastAutomaticCheckAt)
        }
    }

    var lastAutomaticCheckVersion: String? {
        get {
            defaults.string(forKey: Key.lastAutomaticCheckVersion)
        }
        set {
            setOptional(newValue, forKey: Key.lastAutomaticCheckVersion)
        }
    }

    var ignoredVersion: String? {
        get {
            defaults.string(forKey: Key.ignoredVersion)
        }
        set {
            setOptional(newValue, forKey: Key.ignoredVersion)
        }
    }

    var deferredVersion: String? {
        get {
            defaults.string(forKey: Key.deferredVersion)
        }
        set {
            setOptional(newValue, forKey: Key.deferredVersion)
        }
    }

    var deferredUntil: Date? {
        get {
            defaults.object(forKey: Key.deferredUntil) as? Date
        }
        set {
            setOptional(newValue, forKey: Key.deferredUntil)
        }
    }

    private func setOptional(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
