import Foundation

final class UpdateCheckStateStore {
    private enum Key {
        static let lastAutomaticCheckAt = "VoxFlow.UpdateCheck.lastAutomaticCheckAt"
        static let ignoredVersion = "VoxFlow.UpdateCheck.ignoredVersion"
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
            defaults.set(newValue, forKey: Key.lastAutomaticCheckAt)
        }
    }

    var ignoredVersion: String? {
        get {
            defaults.string(forKey: Key.ignoredVersion)
        }
        set {
            defaults.set(newValue, forKey: Key.ignoredVersion)
        }
    }
}
