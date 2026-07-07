// DictusKeyboard/Models/RecentEmojis.swift
import Foundation
import Shared

/// Manages recently used emojis, persisted via App Group UserDefaults.
/// Cap at 30 emojis to keep the "Recents" section manageable.
enum RecentEmojis {
    private static let key = "recentEmojis"
    private static let maxCount = 30

    static func load() -> [String] {
        AppGroup.preferences.stringArray(forKey: key) ?? []
    }

    static func add(_ emoji: String) {
        var recents = load()
        // Remove duplicate if already present, then prepend
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        // Cap to max count
        if recents.count > maxCount {
            recents = Array(recents.prefix(maxCount))
        }
        AppGroup.preferences.set(recents, forKey: key)
    }
}
