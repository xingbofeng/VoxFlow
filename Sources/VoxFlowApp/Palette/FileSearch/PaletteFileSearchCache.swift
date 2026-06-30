import Foundation

struct PaletteFileSearchCacheKey: Hashable, Sendable {
    let normalizedQuery: String
    let scope: PaletteFileSearchScope
    let strategy: PaletteFileSearchStrategy
}

final class PaletteFileSearchCache {
    private struct Entry {
        let items: [PaletteFileItem]
        let storedAt: Date
        var lastAccessedAt: Date
        var accessOrder: Int
    }

    private let capacity: Int
    private let ttl: TimeInterval
    private let now: () -> Date
    private var entries: [PaletteFileSearchCacheKey: Entry] = [:]
    private var nextAccessOrder = 0

    init(
        capacity: Int = 20,
        ttl: TimeInterval = 600,
        now: @escaping () -> Date = Date.init
    ) {
        self.capacity = max(capacity, 1)
        self.ttl = ttl
        self.now = now
    }

    func results(for key: PaletteFileSearchCacheKey) -> [PaletteFileItem]? {
        guard var entry = entries[key] else { return nil }
        let currentDate = now()
        guard currentDate.timeIntervalSince(entry.storedAt) <= ttl else {
            entries.removeValue(forKey: key)
            return nil
        }
        nextAccessOrder += 1
        entry.lastAccessedAt = currentDate
        entry.accessOrder = nextAccessOrder
        entries[key] = entry
        return entry.items
    }

    func store(_ items: [PaletteFileItem], for key: PaletteFileSearchCacheKey) {
        let currentDate = now()
        nextAccessOrder += 1
        entries[key] = Entry(
            items: items,
            storedAt: currentDate,
            lastAccessedAt: currentDate,
            accessOrder: nextAccessOrder
        )
        evictIfNeeded()
    }

    func removeAll() {
        entries.removeAll()
    }

    private func evictIfNeeded() {
        guard entries.count > capacity else { return }
        let overflow = entries.count - capacity
        let keysToRemove = entries
            .sorted { lhs, rhs in
                lhs.value.accessOrder < rhs.value.accessOrder
            }
            .prefix(overflow)
            .map(\.key)
        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
    }
}
