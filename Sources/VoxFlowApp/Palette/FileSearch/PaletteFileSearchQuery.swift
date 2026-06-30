import Foundation

enum PaletteFileSearchScope: Hashable, Sendable {
    case userHome
    case locations([URL])
}

enum PaletteFileSearchStrategy: Hashable, Sendable {
    case recentOnly
    case prefixThenContains
    case contains
}

struct PaletteFileSearchPlan: Equatable, Sendable {
    let normalizedQuery: String
    let scope: PaletteFileSearchScope
    let strategy: PaletteFileSearchStrategy
    let limit: Int
    let timeoutMilliseconds: Int
}

struct PaletteFileSearchRequest: Equatable, Sendable {
    let query: String
    let scope: PaletteFileSearchScope
    let strategy: PaletteFileSearchStrategy
    let limit: Int
    let timeoutMilliseconds: Int
}

enum PaletteFileSearchCompletion: Equatable, Sendable {
    case completed
    case timedOut
    case cancelled
}

struct PaletteFileSearchResponse: Equatable, Sendable {
    let query: String
    let items: [PaletteFileItem]
    let completion: PaletteFileSearchCompletion
}

enum PaletteFileSearchState: Equatable, Sendable {
    case idle
    case showingRecent
    case searching
    case completed
    case timedOut
    case failed
}

enum PaletteFileSearchQuery {
    static let recentLimit = 20
    static let singleCharacterLimit = 30
    static let multiCharacterLimit = 50
    static let standardTimeoutMilliseconds = 1_000

    static func plan(
        for query: String,
        scope: PaletteFileSearchScope = .userHome
    ) -> PaletteFileSearchPlan {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return PaletteFileSearchPlan(
                normalizedQuery: "",
                scope: scope,
                strategy: .recentOnly,
                limit: recentLimit,
                timeoutMilliseconds: 0
            )
        }

        let isSingleCharacter = normalized.count == 1
        return PaletteFileSearchPlan(
            normalizedQuery: normalized,
            scope: scope,
            strategy: isSingleCharacter ? .prefixThenContains : .contains,
            limit: isSingleCharacter ? singleCharacterLimit : multiCharacterLimit,
            timeoutMilliseconds: standardTimeoutMilliseconds
        )
    }
}
