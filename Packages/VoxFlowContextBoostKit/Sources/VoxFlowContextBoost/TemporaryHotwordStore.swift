import Foundation

public actor TemporaryHotwordStore {
    private var hotwordsByScope: [HotwordScope: [TemporaryHotword]] = [:]

    public init() {}

    public func put(
        _ hotwords: [TemporaryHotword],
        scope: HotwordScope,
        now: Date = Date()
    ) {
        hotwordsByScope[scope] = hotwords
            .filter { $0.expiresAt > now }
            .sorted(by: Self.sortHotwords)
    }

    public func topK(
        scope: HotwordScope,
        limit: Int,
        now: Date = Date()
    ) -> [TemporaryHotword] {
        purgeExpired(now: now)
        let scoped = hotwordsByScope[scope] ?? []
        let source = scoped.isEmpty && scope != .global
            ? hotwordsByScope[.global] ?? []
            : scoped
        return Array(source.sorted(by: Self.sortHotwords).prefix(max(0, limit)))
    }

    public func purgeExpired(now: Date = Date()) {
        for (scope, hotwords) in hotwordsByScope {
            let fresh = hotwords.filter { $0.expiresAt > now }
            if fresh.isEmpty {
                hotwordsByScope.removeValue(forKey: scope)
            } else {
                hotwordsByScope[scope] = fresh
            }
        }
    }

    private static func sortHotwords(_ lhs: TemporaryHotword, _ rhs: TemporaryHotword) -> Bool {
        if lhs.score == rhs.score {
            return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
        }
        return lhs.score > rhs.score
    }
}
