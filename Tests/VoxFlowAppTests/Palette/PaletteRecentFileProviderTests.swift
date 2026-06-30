import CoreServices
import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteRecentFileProviderTests: XCTestCase {
    func testRecentFilesFallBackToSpotlightRecentRecordsWhenDocumentControllerIsEmpty() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runner = CapturingRecentMetadataQueryRunner(result: .completed([
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("Library/Caches/cache.db"),
                name: "cache.db",
                isDirectory: false,
                contentTypeIdentifier: "public.database",
                modifiedAt: Date(timeIntervalSince1970: 300)
            ),
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent(".hidden"),
                name: ".hidden",
                isDirectory: false,
                contentTypeIdentifier: "public.data",
                modifiedAt: Date(timeIntervalSince1970: 250)
            ),
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("workspace/project/node_modules/package/index.js"),
                name: "index.js",
                isDirectory: false,
                contentTypeIdentifier: "public.javascript",
                modifiedAt: Date(timeIntervalSince1970: 240)
            ),
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("workspace/project"),
                name: "project",
                isDirectory: true,
                contentTypeIdentifier: "public.folder",
                modifiedAt: Date(timeIntervalSince1970: 230)
            ),
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("Documents/Newer.md"),
                name: "Newer.md",
                isDirectory: false,
                contentTypeIdentifier: "net.daringfireball.markdown",
                modifiedAt: Date(timeIntervalSince1970: 200)
            ),
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("Documents/Older.md"),
                name: "Older.md",
                isDirectory: false,
                contentTypeIdentifier: "net.daringfireball.markdown",
                modifiedAt: Date(timeIntervalSince1970: 100)
            ),
        ]))
        let searchLocations = [home.appendingPathComponent("Documents", isDirectory: true)]
        let provider = SystemPaletteRecentFileProvider(
            documentURLs: { [] },
            searchLocations: { searchLocations },
            runner: runner
        )

        let files = await provider.recentFiles(limit: 1)

        XCTAssertEqual(files.map(\.name), ["Newer.md"])
        XCTAssertEqual(runner.requests.count, 2)
        XCTAssertEqual(runner.requests.first?.scope, .locations(searchLocations))
        XCTAssertEqual(runner.requests.first?.limit, 40)
        XCTAssertEqual(runner.requests.first?.timeoutMilliseconds, 1_200)
        XCTAssertEqual(
            runner.requests.first?.sortDescriptors.map(\.key),
            [kMDItemLastUsedDate as String]
        )
        XCTAssertTrue(
            runner.requests[0].predicate.evaluate(
                with: [kMDItemLastUsedDate as String: Date(timeIntervalSince1970: 400)]
            )
        )
        XCTAssertFalse(
            runner.requests[0].predicate.evaluate(
                with: [
                    kMDItemLastUsedDate as String: Date(timeIntervalSince1970: 400),
                    kMDItemPath as String: home.appendingPathComponent("workspace/project/node_modules/package/index.js").path,
                    kMDItemFSName as String: "index.js",
                ]
            )
        )
        XCTAssertFalse(
            runner.requests[0].predicate.evaluate(
                with: [
                    kMDItemLastUsedDate as String: Date(timeIntervalSince1970: 400),
                    kMDItemPath as String: home.appendingPathComponent(".config/token").path,
                    kMDItemFSName as String: "token",
                ]
            )
        )
    }

    func testRecentFilesSortByLastUsedDateBeforeModifiedDate() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runner = CapturingRecentMetadataQueryRunner(result: .completed([
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("Documents/Modified.md"),
                name: "Modified.md",
                isDirectory: false,
                contentTypeIdentifier: "net.daringfireball.markdown",
                modifiedAt: Date(timeIntervalSince1970: 300)
            ),
            PaletteFileMetadataRecord(
                url: home.appendingPathComponent("Documents/Opened.md"),
                name: "Opened.md",
                isDirectory: false,
                contentTypeIdentifier: "net.daringfireball.markdown",
                lastUsedAt: Date(timeIntervalSince1970: 500),
                modifiedAt: Date(timeIntervalSince1970: 100)
            ),
        ]))
        let provider = SystemPaletteRecentFileProvider(
            documentURLs: { [] },
            searchLocations: { [home.appendingPathComponent("Documents", isDirectory: true)] },
            runner: runner
        )

        let files = await provider.recentFiles(limit: 2)

        XCTAssertEqual(files.map(\.name), ["Opened.md", "Modified.md"])
        XCTAssertEqual(files.first?.lastUsedAt, Date(timeIntervalSince1970: 500))
    }

    func testRecentFilesFallsBackToModifiedDateWhenLastUsedIsInsufficient() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runner = CapturingRecentMetadataQueryRunner(results: [
            .completed([
                PaletteFileMetadataRecord(
                    url: home.appendingPathComponent("Documents/Opened.md"),
                    name: "Opened.md",
                    isDirectory: false,
                    contentTypeIdentifier: "net.daringfireball.markdown",
                    lastUsedAt: Date(timeIntervalSince1970: 500),
                    modifiedAt: Date(timeIntervalSince1970: 100)
                )
            ]),
            .completed([
                PaletteFileMetadataRecord(
                    url: home.appendingPathComponent("Documents/Modified.md"),
                    name: "Modified.md",
                    isDirectory: false,
                    contentTypeIdentifier: "net.daringfireball.markdown",
                    modifiedAt: Date(timeIntervalSince1970: 300)
                )
            ]),
        ])
        let provider = SystemPaletteRecentFileProvider(
            documentURLs: { [] },
            searchLocations: { [home.appendingPathComponent("Documents", isDirectory: true)] },
            runner: runner
        )

        let files = await provider.recentFiles(limit: 2)

        XCTAssertEqual(files.map(\.name), ["Opened.md", "Modified.md"])
        XCTAssertEqual(runner.requests.count, 2)
        XCTAssertEqual(runner.requests[0].sortDescriptors.map(\.key), [kMDItemLastUsedDate as String])
        XCTAssertEqual(runner.requests[1].sortDescriptors.map(\.key), [kMDItemFSContentChangeDate as String])
        XCTAssertEqual(runner.requests[0].limit, 40)
        XCTAssertEqual(runner.requests[1].limit, 60)
    }
}

@MainActor
private final class CapturingRecentMetadataQueryRunner: PaletteMetadataQueryRunning {
    struct CapturedRequest {
        let predicate: NSPredicate
        let scope: PaletteFileSearchScope
        let limit: Int
        let timeoutMilliseconds: Int
        let sortDescriptors: [NSSortDescriptor]
    }

    private var results: [PaletteMetadataQueryResult]
    private let repeatsSingleResult: Bool
    private(set) var requests: [CapturedRequest] = []

    init(result: PaletteMetadataQueryResult) {
        self.results = [result]
        self.repeatsSingleResult = true
    }

    init(results: [PaletteMetadataQueryResult]) {
        self.results = results
        self.repeatsSingleResult = false
    }

    func run(
        predicate: NSPredicate,
        scope: PaletteFileSearchScope,
        limit: Int,
        timeoutMilliseconds: Int,
        sortDescriptors: [NSSortDescriptor]
    ) async -> PaletteMetadataQueryResult {
        requests.append(
            CapturedRequest(
                predicate: predicate,
                scope: scope,
                limit: limit,
                timeoutMilliseconds: timeoutMilliseconds,
                sortDescriptors: sortDescriptors
            )
        )
        let result: PaletteMetadataQueryResult
        if repeatsSingleResult {
            result = results.first ?? .completed([])
        } else {
            result = results.isEmpty ? .completed([]) : results.removeFirst()
        }
        return filtered(result, predicate: predicate, scope: scope)
    }

    private func filtered(
        _ result: PaletteMetadataQueryResult,
        predicate: NSPredicate,
        scope: PaletteFileSearchScope
    ) -> PaletteMetadataQueryResult {
        switch result {
        case let .completed(records):
            return .completed(records.filter { matches($0, predicate: predicate, scope: scope) })
        case let .timedOut(records):
            return .timedOut(records.filter { matches($0, predicate: predicate, scope: scope) })
        case .cancelled:
            return .cancelled
        }
    }

    private func matches(
        _ record: PaletteFileMetadataRecord,
        predicate: NSPredicate,
        scope: PaletteFileSearchScope
    ) -> Bool {
        switch scope {
        case .userHome:
            break
        case let .locations(urls):
            let path = record.url.standardizedFileURL.path
            guard urls.contains(where: { url in
                let scopePath = url.standardizedFileURL.path
                return path == scopePath || path.hasPrefix(scopePath + "/")
            }) else {
                return false
            }
        }
        return predicate.evaluate(
            with: [
                kMDItemURL as String: record.url,
                kMDItemPath as String: record.url.path,
                kMDItemFSName as String: record.name,
                kMDItemContentType as String: record.contentTypeIdentifier as Any,
                kMDItemLastUsedDate as String: record.lastUsedAt as Any,
                kMDItemFSContentChangeDate as String: record.modifiedAt as Any,
            ]
        )
    }
}
