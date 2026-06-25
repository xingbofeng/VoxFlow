import Foundation
import FuzzyMatch

enum PaletteRootSectionKind: Equatable, Sendable {
    case favorites
    case favoriteHint
    case suggestions
    case searchResults
}

struct PaletteRootSection: Equatable, Sendable {
    let kind: PaletteRootSectionKind
    let items: [PaletteRootItem]
}

struct PaletteRootSearchIndex {
    private let matcher = FuzzyMatcher()

    func sections(
        for items: [PaletteRootItem],
        query: String,
        favoriteIDs: [PaletteRootItemID],
        usageStore: any PaletteUsageStoring,
        now: Date
    ) -> [PaletteRootSection] {
        let items = deduplicated(items)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuery.isEmpty {
            return emptyQuerySections(
                for: items,
                favoriteIDs: favoriteIDs,
                usageStore: usageStore,
                now: now
            )
        }

        let favorites = Set(favoriteIDs)
        let ranked = items
            .compactMap { item -> RankedRootItem? in
                guard let score = matchScore(for: item, query: normalizedQuery) else { return nil }
                let totalScore = score
                    + (favorites.contains(item.id) ? 0.03 : 0)
                    + usageScore(for: item.id, usageStore: usageStore, now: now) * 0.08
                    + querySelectionScore(for: item.id, query: normalizedQuery, usageStore: usageStore, now: now) * 0.12
                return RankedRootItem(item: item, score: totalScore)
            }
            .sorted(by: rankedSort)
            .map(\.item)

        return ranked.isEmpty ? [] : [PaletteRootSection(kind: .searchResults, items: ranked)]
    }

    private func deduplicated(_ items: [PaletteRootItem]) -> [PaletteRootItem] {
        var seenIDs = Set<PaletteRootItemID>()
        return items.filter { item in
            seenIDs.insert(item.id).inserted
        }
    }

    private func emptyQuerySections(
        for items: [PaletteRootItem],
        favoriteIDs: [PaletteRootItemID],
        usageStore: any PaletteUsageStoring,
        now: Date
    ) -> [PaletteRootSection] {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let favorites = favoriteIDs.compactMap { itemByID[$0] }
        let favoriteSet = Set(favorites.map(\.id))
        let suggestions = items
            .filter { !favoriteSet.contains($0.id) }
            .enumerated()
            .map { index, item in
                RankedRootItem(
                    item: item,
                    score: usageScore(for: item.id, usageStore: usageStore, now: now),
                    originalIndex: index
                )
            }
            .sorted(by: rankedSort)
            .map(\.item)

        var sections: [PaletteRootSection] = []
        if favorites.isEmpty {
            sections.append(PaletteRootSection(kind: .favoriteHint, items: []))
        } else {
            sections.append(PaletteRootSection(kind: .favorites, items: favorites))
        }
        sections.append(PaletteRootSection(kind: .suggestions, items: suggestions))
        return sections
    }

    private func matchScore(for item: PaletteRootItem, query: String) -> Double? {
        let candidates = [item.title, item.subtitle] + item.aliases
        let bestScore = candidates.compactMap { candidate -> Double? in
            if candidate.localizedCaseInsensitiveContains(query) {
                return 1.0
            }
            return matcher.score(candidate, against: query)?.score
        }.max()
        return bestScore
    }

    private func usageScore(
        for id: PaletteRootItemID,
        usageStore: any PaletteUsageStoring,
        now: Date
    ) -> Double {
        let snapshot = usageStore.usage(for: id)
        guard snapshot.useCount > 0 else { return 0 }
        let countScore = min(Double(snapshot.useCount), 10) / 10
        let recencyScore: Double
        if let lastUsedAt = snapshot.lastUsedAt {
            let ageHours = max(now.timeIntervalSince(lastUsedAt) / 3_600, 0)
            recencyScore = 1 / (1 + ageHours)
        } else {
            recencyScore = 0
        }
        return countScore + recencyScore
    }

    private func querySelectionScore(
        for id: PaletteRootItemID,
        query: String,
        usageStore: any PaletteUsageStoring,
        now: Date
    ) -> Double {
        let snapshot = usageStore.querySelection(for: query, itemID: id)
        guard snapshot.selectionCount > 0 else { return 0 }
        let countScore = min(Double(snapshot.selectionCount), 10) / 10
        let recencyScore: Double
        if let lastSelectedAt = snapshot.lastSelectedAt {
            let ageHours = max(now.timeIntervalSince(lastSelectedAt) / 3_600, 0)
            recencyScore = 1 / (1 + ageHours)
        } else {
            recencyScore = 0
        }
        return countScore + recencyScore
    }

    private func rankedSort(_ lhs: RankedRootItem, _ rhs: RankedRootItem) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.originalIndex != rhs.originalIndex {
            return lhs.originalIndex < rhs.originalIndex
        }
        return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
    }

    private struct RankedRootItem {
        let item: PaletteRootItem
        let score: Double
        var originalIndex: Int = 0
    }
}
