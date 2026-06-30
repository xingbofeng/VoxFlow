import CoreServices
import Foundation
import UniformTypeIdentifiers

protocol PaletteFileSearching: AnyObject {
    @MainActor
    func search(_ request: PaletteFileSearchRequest) async -> PaletteFileSearchResponse
}

struct PaletteFileMetadataRecord: Equatable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let contentTypeIdentifier: String?
    let lastUsedAt: Date?
    let modifiedAt: Date?

    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        contentTypeIdentifier: String?,
        lastUsedAt: Date? = nil,
        modifiedAt: Date?
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.contentTypeIdentifier = contentTypeIdentifier
        self.lastUsedAt = lastUsedAt
        self.modifiedAt = modifiedAt
    }

    static func fromMetadataValues(
        urlValue: Any?,
        pathValue: Any?,
        nameValue: Any?,
        contentTypeValue: Any?,
        lastUsedAtValue: Any? = nil,
        modifiedAtValue: Any?
    ) -> PaletteFileMetadataRecord? {
        let url: URL?
        if let value = urlValue as? URL {
            url = value
        } else if let value = urlValue as? String {
            url = URL(string: value) ?? URL(fileURLWithPath: value)
        } else if let value = pathValue as? String {
            url = URL(fileURLWithPath: value)
        } else {
            url = nil
        }
        guard let url else { return nil }

        let name = nameValue as? String ?? url.lastPathComponent
        let contentType = contentTypeValue as? String
        let modifiedAt = modifiedAtValue as? Date
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return PaletteFileMetadataRecord(
            url: url,
            name: name,
            isDirectory: isDirectory,
            contentTypeIdentifier: contentType,
            lastUsedAt: lastUsedAtValue as? Date,
            modifiedAt: modifiedAt
        )
    }
}

enum PaletteMetadataQueryResult: Equatable, Sendable {
    case completed([PaletteFileMetadataRecord])
    case timedOut([PaletteFileMetadataRecord])
    case cancelled

    var records: [PaletteFileMetadataRecord] {
        switch self {
        case let .completed(records), let .timedOut(records):
            return records
        case .cancelled:
            return []
        }
    }

    var completion: PaletteFileSearchCompletion {
        switch self {
        case .completed:
            return .completed
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        }
    }
}

protocol PaletteMetadataQueryRunning: AnyObject {
    @MainActor
    func run(
        predicate: NSPredicate,
        scope: PaletteFileSearchScope,
        limit: Int,
        timeoutMilliseconds: Int,
        sortDescriptors: [NSSortDescriptor]
    ) async -> PaletteMetadataQueryResult
}

extension PaletteMetadataQueryRunning {
    @MainActor
    func run(
        predicate: NSPredicate,
        scope: PaletteFileSearchScope,
        limit: Int,
        timeoutMilliseconds: Int
    ) async -> PaletteMetadataQueryResult {
        await run(
            predicate: predicate,
            scope: scope,
            limit: limit,
            timeoutMilliseconds: timeoutMilliseconds,
            sortDescriptors: []
        )
    }
}

struct PaletteFileSearchLogEvent: Equatable, Sendable {
    let queryLength: Int
    let scope: PaletteFileSearchScope
    let strategy: PaletteFileSearchStrategy
    let resultCount: Int
    let completion: PaletteFileSearchCompletion
    let elapsedMilliseconds: Int
}

@MainActor
protocol PaletteFileSearchLogging: AnyObject {
    func record(_ event: PaletteFileSearchLogEvent)
}

@MainActor
final class OSLogPaletteFileSearchLogger: PaletteFileSearchLogging {
    func record(_ event: PaletteFileSearchLogEvent) {
        AppLogger.general.debug(
            "palette_file_search queryLength=\(event.queryLength) scope=\(event.scope) strategy=\(event.strategy) resultCount=\(event.resultCount) completion=\(event.completion) elapsedMs=\(event.elapsedMilliseconds)"
        )
    }
}

@MainActor
final class SystemPaletteFileSearchService: PaletteFileSearching {
    private let runner: any PaletteMetadataQueryRunning
    private let logger: (any PaletteFileSearchLogging)?

    init(
        runner: any PaletteMetadataQueryRunning = SystemPaletteMetadataQueryRunner(),
        logger: (any PaletteFileSearchLogging)? = OSLogPaletteFileSearchLogger()
    ) {
        self.runner = runner
        self.logger = logger
    }

    @MainActor
    func search(_ request: PaletteFileSearchRequest) async -> PaletteFileSearchResponse {
        let startedAt = Date()
        let normalizedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: PaletteFileSearchResponse
        if normalizedQuery.isEmpty || request.strategy == .recentOnly {
            response = PaletteFileSearchResponse(query: normalizedQuery, items: [], completion: .completed)
        } else {
            let directRecords = Self.directPathRecords(for: normalizedQuery)
            switch request.strategy {
            case .recentOnly:
                response = PaletteFileSearchResponse(query: normalizedQuery, items: [], completion: .completed)
            case .contains:
                let result = await runContains(query: normalizedQuery, request: request)
                response = self.response(
                    query: normalizedQuery,
                    records: directRecords + result.records,
                    completion: result.completion,
                    limit: request.limit
                )
            case .prefixThenContains:
                response = await searchPrefixThenContains(
                    query: normalizedQuery,
                    request: request,
                    directRecords: directRecords
                )
            }
        }
        recordSearch(request: request, query: normalizedQuery, response: response, startedAt: startedAt)
        return response
    }

    private func searchPrefixThenContains(
        query: String,
        request: PaletteFileSearchRequest,
        directRecords: [PaletteFileMetadataRecord]
    ) async -> PaletteFileSearchResponse {
        let prefixResult = await runner.run(
            predicate: Self.predicate(query: query, match: .beginsWith),
            scope: request.scope,
            limit: request.limit,
            timeoutMilliseconds: request.timeoutMilliseconds
        )
        guard prefixResult.completion == .completed,
              prefixResult.records.count < request.limit else {
            return response(
                query: query,
                records: directRecords + prefixResult.records,
                completion: prefixResult.completion,
                limit: request.limit
            )
        }

        let containsResult = await runContains(query: query, request: request)
        let combined = directRecords + prefixResult.records + containsResult.records
        return response(
            query: query,
            records: combined,
            completion: containsResult.completion,
            limit: request.limit
        )
    }

    private func runContains(
        query: String,
        request: PaletteFileSearchRequest
    ) async -> PaletteMetadataQueryResult {
        await runner.run(
            predicate: Self.predicate(query: query, match: .contains),
            scope: request.scope,
            limit: request.limit,
            timeoutMilliseconds: request.timeoutMilliseconds
        )
    }

    private func response(
        query: String,
        records: [PaletteFileMetadataRecord],
        completion: PaletteFileSearchCompletion,
        limit: Int
    ) -> PaletteFileSearchResponse {
        var seenURLs = Set<URL>()
        let items = records.compactMap { record -> PaletteFileItem? in
            guard seenURLs.insert(record.url).inserted else { return nil }
            return PaletteFileItem(
                url: record.url,
                name: record.name,
                displayPath: Self.abbreviateHome(in: record.url.deletingLastPathComponent().path),
                isDirectory: record.isDirectory,
                contentTypeIdentifier: record.contentTypeIdentifier,
                lastUsedAt: record.lastUsedAt,
                modifiedAt: record.modifiedAt
            )
        }
        .prefix(limit)
        return PaletteFileSearchResponse(query: query, items: Array(items), completion: completion)
    }

    private enum PredicateMatch {
        case beginsWith
        case contains
    }

    private static func predicate(query: String, match: PredicateMatch) -> NSPredicate {
        switch match {
        case .beginsWith:
            return NSPredicate(format: "%K BEGINSWITH[cd] %@", kMDItemFSName as String, query)
        case .contains:
            guard query.count > 1 else {
                return NSPredicate(format: "%K CONTAINS[cd] %@", kMDItemFSName as String, query)
            }
            return NSPredicate(
                format: "(%K CONTAINS[cd] %@) OR (%K CONTAINS[cd] %@)",
                kMDItemFSName as String,
                query,
                kMDItemPath as String,
                query
            )
        }
    }

    private static func directPathRecords(for query: String) -> [PaletteFileMetadataRecord] {
        guard query.hasPrefix("/") || query.hasPrefix("~") else { return [] }
        let expandedPath = (query as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }

        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .contentTypeKey,
            .isDirectoryKey,
        ])
        return [
            PaletteFileMetadataRecord(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory ?? isDirectory.boolValue,
                contentTypeIdentifier: values?.contentType?.identifier,
                lastUsedAt: nil,
                modifiedAt: values?.contentModificationDate
            )
        ]
    }

    private static func abbreviateHome(in path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func recordSearch(
        request: PaletteFileSearchRequest,
        query: String,
        response: PaletteFileSearchResponse,
        startedAt: Date
    ) {
        logger?.record(
            PaletteFileSearchLogEvent(
                queryLength: query.count,
                scope: request.scope,
                strategy: request.strategy,
                resultCount: response.items.count,
                completion: response.completion,
                elapsedMilliseconds: max(Int(Date().timeIntervalSince(startedAt) * 1_000), 0)
            )
        )
    }
}

final class SystemPaletteMetadataQueryRunner: PaletteMetadataQueryRunning {
    @MainActor
    func run(
        predicate: NSPredicate,
        scope: PaletteFileSearchScope,
        limit: Int,
        timeoutMilliseconds: Int,
        sortDescriptors: [NSSortDescriptor]
    ) async -> PaletteMetadataQueryResult {
        let session = PaletteMetadataQuerySession(
            predicate: predicate,
            scope: scope,
            limit: limit,
            timeoutMilliseconds: timeoutMilliseconds,
            sortDescriptors: sortDescriptors
        )
        return await session.start()
    }
}

@MainActor
private final class PaletteMetadataQuerySession {
    private let predicate: NSPredicate
    private let scope: PaletteFileSearchScope
    private let limit: Int
    private let timeoutMilliseconds: Int
    private let sortDescriptors: [NSSortDescriptor]
    private let query = NSMetadataQuery()
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<PaletteMetadataQueryResult, Never>?
    private var didFinish = false

    init(
        predicate: NSPredicate,
        scope: PaletteFileSearchScope,
        limit: Int,
        timeoutMilliseconds: Int,
        sortDescriptors: [NSSortDescriptor]
    ) {
        self.predicate = predicate
        self.scope = scope
        self.limit = limit
        self.timeoutMilliseconds = timeoutMilliseconds
        self.sortDescriptors = sortDescriptors
    }

    func start() async -> PaletteMetadataQueryResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.startQuery()
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(.cancelled)
            }
        }
    }

    private func startQuery() {
        query.predicate = predicate
        query.searchScopes = searchScopes(for: scope)
        query.sortDescriptors = sortDescriptors
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishWithCurrentResults(completion: .completed)
            }
        }
        query.start()
        guard timeoutMilliseconds > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeoutMilliseconds) * 1_000_000)
            self.finishWithCurrentResults(completion: .timedOut)
        }
    }

    private func finishWithCurrentResults(completion: PaletteFileSearchCompletion) {
        let records = Array(query.results.prefix(limit)).compactMap { result -> PaletteFileMetadataRecord? in
            guard let item = result as? NSMetadataItem else { return nil }
            return Self.record(from: item)
        }
        switch completion {
        case .completed:
            finish(.completed(records))
        case .timedOut:
            finish(.timedOut(records))
        case .cancelled:
            finish(.cancelled)
        }
    }

    private func finish(_ result: PaletteMetadataQueryResult) {
        guard !didFinish else { return }
        didFinish = true
        query.stop()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func searchScopes(for scope: PaletteFileSearchScope) -> [Any] {
        switch scope {
        case .userHome:
            return [NSMetadataQueryUserHomeScope]
        case let .locations(urls):
            return urls
        }
    }

    private static func record(from item: NSMetadataItem) -> PaletteFileMetadataRecord? {
        PaletteFileMetadataRecord.fromMetadataValues(
            urlValue: item.value(forAttribute: kMDItemURL as String),
            pathValue: item.value(forAttribute: kMDItemPath as String),
            nameValue: item.value(forAttribute: kMDItemFSName as String),
            contentTypeValue: item.value(forAttribute: kMDItemContentType as String),
            lastUsedAtValue: item.value(forAttribute: kMDItemLastUsedDate as String),
            modifiedAtValue: item.value(forAttribute: kMDItemFSContentChangeDate as String)
        )
    }
}
