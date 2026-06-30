import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteFileSearchServiceTests: XCTestCase {
    func testContainsSearchUsesContainsPredicateAndConfiguredBudget() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [
            .completed([makeRecord(name: "README.md")])
        ])
        let service = SystemPaletteFileSearchService(runner: runner)
        let request = PaletteFileSearchRequest(
            query: "README",
            scope: .userHome,
            strategy: .contains,
            limit: 50,
            timeoutMilliseconds: 1_000
        )

        let response = await service.search(request)

        XCTAssertEqual(response.items.map(\.name), ["README.md"])
        XCTAssertEqual(response.completion, .completed)
        XCTAssertEqual(runner.requests.count, 1)
        XCTAssertEqual(runner.requests[0].scope, .userHome)
        XCTAssertEqual(runner.requests[0].limit, 50)
        XCTAssertEqual(runner.requests[0].timeoutMilliseconds, 1_000)
        XCTAssertTrue(
            runner.requests[0].predicate.evaluate(with: [kMDItemFSName as String: "my-readme.md"])
        )
        XCTAssertFalse(
            runner.requests[0].predicate.evaluate(with: [kMDItemFSName as String: "notes.txt"])
        )
    }

    func testContainsSearchMatchesFilePathWhenNameDoesNotMatch() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [
            .completed([makeRecord(name: "6C0C114A-54C8-44A8-97B8-6150601488D5.mp4")])
        ])
        let service = SystemPaletteFileSearchService(runner: runner)

        _ = await service.search(
            PaletteFileSearchRequest(
                query: "ScreenRecordings/6C0C114A-54C8-44A8-97B8-6150601488D5.mp4",
                scope: .userHome,
                strategy: .contains,
                limit: 50,
                timeoutMilliseconds: 1_000
            )
        )

        XCTAssertEqual(runner.requests.count, 1)
        XCTAssertTrue(
            runner.requests[0].predicate.evaluate(
                with: [
                    kMDItemFSName as String: "6C0C114A-54C8-44A8-97B8-6150601488D5.mp4",
                    kMDItemPath as String: "/Users/counter/Library/Application Support/VoxFlow/ScreenRecordings/6C0C114A-54C8-44A8-97B8-6150601488D5.mp4",
                ]
            )
        )
        XCTAssertFalse(
            runner.requests[0].predicate.evaluate(
                with: [
                    kMDItemFSName as String: "notes.txt",
                    kMDItemPath as String: "/Users/counter/Documents/notes.txt",
                ]
            )
        )
    }

    func testExistingAbsolutePathIsReturnedEvenWhenMetadataSearchIsEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("direct-path.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = CapturingPaletteMetadataQueryRunner(results: [.completed([])])
        let service = SystemPaletteFileSearchService(runner: runner)

        let response = await service.search(
            PaletteFileSearchRequest(
                query: file.path,
                scope: .userHome,
                strategy: .contains,
                limit: 50,
                timeoutMilliseconds: 1_000
            )
        )

        XCTAssertEqual(response.items.map(\.url), [file])
        XCTAssertEqual(response.items.first?.name, "direct-path.txt")
        XCTAssertEqual(response.items.first?.displayPath, directory.path)
        XCTAssertEqual(response.completion, .completed)
    }

    func testSingleCharacterSearchRunsPrefixBeforeContainsAndDeduplicatesResults() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [
            .completed([makeRecord(name: "126")]),
            .completed([makeRecord(name: "126"), makeRecord(name: "doc-1.txt")]),
        ])
        let service = SystemPaletteFileSearchService(runner: runner)

        let response = await service.search(
            PaletteFileSearchRequest(
                query: "1",
                scope: .userHome,
                strategy: .prefixThenContains,
                limit: 30,
                timeoutMilliseconds: 1_000
            )
        )

        XCTAssertEqual(response.items.map(\.name), ["126", "doc-1.txt"])
        XCTAssertEqual(runner.requests.count, 2)
        XCTAssertTrue(
            runner.requests[0].predicate.evaluate(with: [kMDItemFSName as String: "126"])
        )
        XCTAssertFalse(
            runner.requests[0].predicate.evaluate(with: [kMDItemFSName as String: "doc-1.txt"])
        )
        XCTAssertTrue(
            runner.requests[1].predicate.evaluate(with: [kMDItemFSName as String: "doc-1.txt"])
        )
    }

    func testRecentOnlyRequestDoesNotInvokeRunner() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [])
        let service = SystemPaletteFileSearchService(runner: runner)

        let response = await service.search(
            PaletteFileSearchRequest(
                query: "",
                scope: .userHome,
                strategy: .recentOnly,
                limit: 20,
                timeoutMilliseconds: 0
            )
        )

        XCTAssertTrue(response.items.isEmpty)
        XCTAssertEqual(response.completion, .completed)
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func testTimedOutRunnerResponsePropagatesTimeoutCompletion() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [
            .timedOut([makeRecord(name: "slow.txt")])
        ])
        let service = SystemPaletteFileSearchService(runner: runner)

        let response = await service.search(
            PaletteFileSearchRequest(
                query: "slow",
                scope: .userHome,
                strategy: .contains,
                limit: 50,
                timeoutMilliseconds: 1
            )
        )

        XCTAssertEqual(response.items.map(\.name), ["slow.txt"])
        XCTAssertEqual(response.completion, .timedOut)
    }

    func testRecordMappingUsesHomeAbbreviatedParentPath() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [
            .completed([
                PaletteFileMetadataRecord(
                    url: FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Documents/Notes.md"),
                    name: "Notes.md",
                    isDirectory: false,
                    contentTypeIdentifier: "net.daringfireball.markdown",
                    modifiedAt: Date(timeIntervalSince1970: 123)
                )
            ])
        ])
        let service = SystemPaletteFileSearchService(runner: runner)

        let response = await service.search(
            PaletteFileSearchRequest(
                query: "notes",
                scope: .userHome,
                strategy: .contains,
                limit: 50,
                timeoutMilliseconds: 1_000
            )
        )

        XCTAssertEqual(response.items.first?.displayPath, "~/Documents")
    }

    func testMetadataRecordFallsBackToPathWhenURLAttributeIsMissing() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/126")
            .path

        let record = PaletteFileMetadataRecord.fromMetadataValues(
            urlValue: nil,
            pathValue: path,
            nameValue: "126",
            contentTypeValue: "public.data",
            modifiedAtValue: Date(timeIntervalSince1970: 456)
        )

        XCTAssertEqual(record?.url, URL(fileURLWithPath: path))
        XCTAssertEqual(record?.name, "126")
        XCTAssertEqual(record?.contentTypeIdentifier, "public.data")
        XCTAssertEqual(record?.modifiedAt, Date(timeIntervalSince1970: 456))
    }

    func testSearchLoggerReceivesOnlySanitizedPerformanceMetadata() async {
        let runner = CapturingPaletteMetadataQueryRunner(results: [
            .completed([makeRecord(name: "secret-file.txt")])
        ])
        let logger = CapturingPaletteFileSearchLogger()
        let service = SystemPaletteFileSearchService(runner: runner, logger: logger)

        _ = await service.search(
            PaletteFileSearchRequest(
                query: "secret",
                scope: .userHome,
                strategy: .contains,
                limit: 50,
                timeoutMilliseconds: 1_000
            )
        )

        XCTAssertEqual(logger.events.count, 1)
        XCTAssertEqual(logger.events[0].queryLength, 6)
        XCTAssertEqual(logger.events[0].strategy, .contains)
        XCTAssertEqual(logger.events[0].scope, .userHome)
        XCTAssertEqual(logger.events[0].resultCount, 1)
        XCTAssertEqual(logger.events[0].completion, .completed)
    }

    private func makeRecord(name: String) -> PaletteFileMetadataRecord {
        PaletteFileMetadataRecord(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: false,
            contentTypeIdentifier: "public.data",
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
    }
}

@MainActor
private final class CapturingPaletteFileSearchLogger: PaletteFileSearchLogging {
    private(set) var events: [PaletteFileSearchLogEvent] = []

    func record(_ event: PaletteFileSearchLogEvent) {
        events.append(event)
    }
}

@MainActor
private final class CapturingPaletteMetadataQueryRunner: PaletteMetadataQueryRunning {
    struct CapturedRequest {
        let predicate: NSPredicate
        let scope: PaletteFileSearchScope
        let limit: Int
        let timeoutMilliseconds: Int
        let sortDescriptors: [NSSortDescriptor]
    }

    private var results: [PaletteMetadataQueryResult]
    private(set) var requests: [CapturedRequest] = []

    init(results: [PaletteMetadataQueryResult]) {
        self.results = results
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
        return results.isEmpty ? .completed([]) : results.removeFirst()
    }
}
