import Foundation

/// 组合静态 root items（命令/应用）与动态 root items（URL/问 AI/Quicklinks），
/// 按 Palette 排序规则产出 sections。
///
/// 排序规则：
/// 1. URL 检测结果（仅当输入可规范化为 URL 时出现）排第一。
/// 2. 对本地应用/命令的强匹配优先于泛搜索动作，避免 `vscode` 这类查询被搜索站点盖住。
/// 3. `问 AI` 作为普通文本查询的高优先级动作；空输入时作为默认建议。
/// 4. Quicklinks：输入命中具体站点 alias 时该站点排 Quicklinks 第一，
///    否则按 favorite、frequency、默认顺序综合排序。
///
/// `includesDynamic == false` 时不注入动态项，回退到纯静态搜索行为，
/// 保留未启用新能力时的原 Palette 体验。
struct PaletteRootComposer {
    private let searchIndex: PaletteRootSearchIndex
    private let quicklinks: [PaletteQuicklink]
    private let now: () -> Date

    init(
        searchIndex: PaletteRootSearchIndex = PaletteRootSearchIndex(),
        quicklinks: [PaletteQuicklink] = PaletteQuicklinkCatalog.all,
        now: @escaping () -> Date = Date.init
    ) {
        self.searchIndex = searchIndex
        self.quicklinks = quicklinks
        self.now = now
    }

    func sections(
        for staticItems: [PaletteRootItem],
        query: String,
        favoriteIDs: [PaletteRootItemID],
        usageStore: any PaletteUsageStoring,
        includesDynamic: Bool
    ) -> [PaletteRootSection] {
        guard includesDynamic else {
            return searchIndex.sections(
                for: staticItems,
                query: query,
                favoriteIDs: favoriteIDs,
                usageStore: usageStore,
                now: now()
            )
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            let dynamicItems = favoriteURLItems(from: favoriteIDs)
                + [PaletteRootItem.askAI(prompt: "")]
                + quicklinks.map { PaletteRootItem.quicklink($0, query: "") }
            return searchIndex.sections(
                for: dynamicItems + staticItems,
                query: "",
                favoriteIDs: favoriteIDs,
                usageStore: usageStore,
                now: now()
            )
        }

        let staticRanked = searchIndex.sections(
            for: staticItems,
            query: normalized,
            favoriteIDs: favoriteIDs,
            usageStore: usageStore,
            now: now()
        ).flatMap(\.items)
        let quicklinkRanked = rankedQuicklinks(query: normalized, favoriteIDs: favoriteIDs, usageStore: usageStore)

        var items: [PaletteRootItem] = []
        if let url = PaletteURLDetector.normalizedURL(for: normalized) {
            items.append(PaletteRootItem.openURL(normalizedURL: url))
        }

        if let firstStatic = staticRanked.first, isStrongStaticMatch(firstStatic, query: normalized) {
            items.append(contentsOf: staticRanked)
            items.append(PaletteRootItem.askAI(prompt: normalized))
            items.append(PaletteRootItem.translate(text: translationText(from: normalized)))
            items.append(contentsOf: quicklinkRanked)
        } else {
            items.append(PaletteRootItem.askAI(prompt: normalized))
            items.append(PaletteRootItem.translate(text: translationText(from: normalized)))
            items.append(contentsOf: quicklinkRanked)
            items.append(contentsOf: staticRanked)
        }
        return [PaletteRootSection(kind: .searchResults, items: items)]
    }

    private func isStrongStaticMatch(_ item: PaletteRootItem, query: String) -> Bool {
        guard item.kind == .application || item.kind == .command else { return false }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return false }

        return ([item.title, item.subtitle] + item.aliases).contains { candidate in
            let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedCandidate.isEmpty else { return false }
            return normalizedCandidate == normalizedQuery
                || normalizedCandidate.localizedCaseInsensitiveContains(normalizedQuery)
                || normalizedQuery.localizedCaseInsensitiveContains(normalizedCandidate)
        }
    }

    private func rankedQuicklinks(
        query: String,
        favoriteIDs: [PaletteRootItemID],
        usageStore: any PaletteUsageStoring
    ) -> [PaletteRootItem] {
        let queryTokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let tokenSet = Set(queryTokens)
        let favorites = Set(favoriteIDs)
        let now = self.now()
        let ranked = quicklinks.map { link -> RankedQuicklink in
            let aliasHit = link.aliases.contains { tokenSet.contains($0.lowercased()) }
            let quicklinkQuery = aliasHit ? refinedAliasQuery(query: query, link: link) : query
            let id = PaletteRootItemID.quicklink(link)
            return RankedQuicklink(
                item: PaletteRootItem.quicklink(link, query: quicklinkQuery),
                aliasHit: aliasHit,
                favorite: favorites.contains(id),
                usage: usageScore(for: id, usageStore: usageStore, now: now)
            )
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.aliasHit != rhs.aliasHit { return lhs.aliasHit }
                if lhs.favorite != rhs.favorite { return lhs.favorite }
                if lhs.usage != rhs.usage { return lhs.usage > rhs.usage }
                return false
            }
            .map(\.item)
    }

    private func refinedAliasQuery(query: String, link: PaletteQuicklink) -> String {
        let aliases = Set(link.aliases.map { $0.lowercased() })
        return query
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !aliases.contains(String($0).lowercased()) }
            .joined(separator: " ")
    }

    private func translationText(from query: String) -> String {
        let aliases: Set<String> = ["translate", "translation", "翻译", "译"]
        let tokens = query.split(whereSeparator: { $0.isWhitespace })
        guard let first = tokens.first,
              aliases.contains(String(first).lowercased()) else {
            return query
        }
        return tokens.dropFirst().joined(separator: " ")
    }

    private func favoriteURLItems(from favoriteIDs: [PaletteRootItemID]) -> [PaletteRootItem] {
        favoriteIDs.compactMap { id in
            guard let url = id.openURLString else { return nil }
            return PaletteRootItem.openURL(normalizedURL: url)
        }
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

    private struct RankedQuicklink {
        let item: PaletteRootItem
        let aliasHit: Bool
        let favorite: Bool
        let usage: Double
    }
}
