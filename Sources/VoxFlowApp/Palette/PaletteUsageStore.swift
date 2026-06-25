import Foundation

struct PaletteUsageSnapshot: Equatable, Codable, Sendable {
    static let empty = PaletteUsageSnapshot(useCount: 0, lastUsedAt: nil)

    var useCount: Int
    var lastUsedAt: Date?
}

struct PaletteQuerySelectionSnapshot: Equatable, Codable, Sendable {
    static let empty = PaletteQuerySelectionSnapshot(selectionCount: 0, lastSelectedAt: nil)

    var selectionCount: Int
    var lastSelectedAt: Date?
}

protocol PaletteUsageStoring: AnyObject {
    func usage(for id: PaletteRootItemID) -> PaletteUsageSnapshot
    func recordActivation(of id: PaletteRootItemID, at date: Date)
    func querySelection(for query: String, itemID: PaletteRootItemID) -> PaletteQuerySelectionSnapshot
    func recordSelection(query: String, itemID: PaletteRootItemID, at date: Date)
}

final class UserDefaultsPaletteUsageStore: PaletteUsageStoring {
    static let usageKey = "Palette.RootSearch.Usage"
    static let querySelectionKey = "Palette.RootSearch.QuerySelection"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func usage(for id: PaletteRootItemID) -> PaletteUsageSnapshot {
        usageRecords()[id.rawValue] ?? .empty
    }

    func recordActivation(of id: PaletteRootItemID, at date: Date) {
        var records = usageRecords()
        var snapshot = records[id.rawValue] ?? .empty
        snapshot.useCount += 1
        snapshot.lastUsedAt = date
        records[id.rawValue] = snapshot
        persist(records, key: Self.usageKey)
    }

    func querySelection(for query: String, itemID: PaletteRootItemID) -> PaletteQuerySelectionSnapshot {
        guard let queryKey = Self.normalizedQuery(query) else { return .empty }
        return querySelectionRecords()[queryKey]?[itemID.rawValue] ?? .empty
    }

    func recordSelection(query: String, itemID: PaletteRootItemID, at date: Date) {
        guard let queryKey = Self.normalizedQuery(query) else { return }
        var records = querySelectionRecords()
        var itemRecords = records[queryKey] ?? [:]
        var snapshot = itemRecords[itemID.rawValue] ?? .empty
        snapshot.selectionCount += 1
        snapshot.lastSelectedAt = date
        itemRecords[itemID.rawValue] = snapshot
        records[queryKey] = itemRecords
        persist(records, key: Self.querySelectionKey)
    }

    static func normalizedQuery(_ query: String) -> String? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func usageRecords() -> [String: PaletteUsageSnapshot] {
        guard let data = defaults.data(forKey: Self.usageKey),
              let records = try? decoder.decode([String: PaletteUsageSnapshot].self, from: data)
        else {
            return [:]
        }
        return records
    }

    private func querySelectionRecords() -> [String: [String: PaletteQuerySelectionSnapshot]] {
        guard let data = defaults.data(forKey: Self.querySelectionKey),
              let records = try? decoder.decode([String: [String: PaletteQuerySelectionSnapshot]].self, from: data)
        else {
            return [:]
        }
        return records
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
