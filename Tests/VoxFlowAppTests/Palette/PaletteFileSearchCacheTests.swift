import XCTest
@testable import VoxFlowApp

final class PaletteFileSearchCacheTests: XCTestCase {
    func testCacheReturnsStoredResultsForSameKeyBeforeTTLExpires() {
        let cache = PaletteFileSearchCache(
            capacity: 20,
            ttl: 300,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let key = PaletteFileSearchCacheKey(
            normalizedQuery: "readme",
            scope: .userHome,
            strategy: .contains
        )
        let item = makeFileItem(name: "README.md")

        cache.store([item], for: key)

        XCTAssertEqual(cache.results(for: key), [item])
    }

    func testCacheExpiresResultsAfterTTL() {
        var currentTime = Date(timeIntervalSince1970: 100)
        let cache = PaletteFileSearchCache(
            capacity: 20,
            ttl: 5,
            now: { currentTime }
        )
        let key = PaletteFileSearchCacheKey(
            normalizedQuery: "readme",
            scope: .userHome,
            strategy: .contains
        )

        cache.store([makeFileItem(name: "README.md")], for: key)
        currentTime = Date(timeIntervalSince1970: 106)

        XCTAssertNil(cache.results(for: key))
    }

    func testCacheEvictsLeastRecentlyUsedResultWhenCapacityIsExceeded() {
        let cache = PaletteFileSearchCache(
            capacity: 2,
            ttl: 300,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let first = cacheKey("one")
        let second = cacheKey("two")
        let third = cacheKey("three")

        cache.store([makeFileItem(name: "one.txt")], for: first)
        cache.store([makeFileItem(name: "two.txt")], for: second)
        _ = cache.results(for: first)
        cache.store([makeFileItem(name: "three.txt")], for: third)

        XCTAssertEqual(cache.results(for: first)?.first?.name, "one.txt")
        XCTAssertNil(cache.results(for: second))
        XCTAssertEqual(cache.results(for: third)?.first?.name, "three.txt")
    }

    func testCacheSeparatesScopeAndStrategy() {
        let cache = PaletteFileSearchCache(
            capacity: 20,
            ttl: 300,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let containsKey = PaletteFileSearchCacheKey(
            normalizedQuery: "1",
            scope: .userHome,
            strategy: .contains
        )
        let prefixKey = PaletteFileSearchCacheKey(
            normalizedQuery: "1",
            scope: .userHome,
            strategy: .prefixThenContains
        )

        cache.store([makeFileItem(name: "contains.txt")], for: containsKey)

        XCTAssertNil(cache.results(for: prefixKey))
    }

    private func cacheKey(_ query: String) -> PaletteFileSearchCacheKey {
        PaletteFileSearchCacheKey(
            normalizedQuery: query,
            scope: .userHome,
            strategy: .contains
        )
    }

    private func makeFileItem(name: String) -> PaletteFileItem {
        PaletteFileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            displayPath: "/tmp/\(name)",
            isDirectory: false,
            contentTypeIdentifier: "public.plain-text",
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
    }
}
