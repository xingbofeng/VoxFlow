import AppKit
import Foundation

@MainActor
protocol PaletteRecentFileProviding: AnyObject {
    func recentFiles(limit: Int) async -> [PaletteFileItem]
}

@MainActor
final class SystemPaletteRecentFileProvider: PaletteRecentFileProviding {
    private enum SpotlightBudget {
        static let lastUsedMinimumLimit = 40
        static let modifiedMinimumLimit = 60
        static let candidateMultiplier = 2
        static let timeoutMilliseconds = 1_200
    }

    private let documentURLs: () -> [URL]
    private let searchLocations: () -> [URL]
    private let runner: any PaletteMetadataQueryRunning

    init(
        documentURLs: @escaping () -> [URL] = { NSDocumentController.shared.recentDocumentURLs },
        searchLocations: @escaping () -> [URL] = { SystemPaletteRecentFileProvider.defaultSearchLocations() },
        runner: any PaletteMetadataQueryRunning = SystemPaletteMetadataQueryRunner()
    ) {
        self.documentURLs = documentURLs
        self.searchLocations = searchLocations
        self.runner = runner
    }

    func recentFiles(limit: Int) async -> [PaletteFileItem] {
        let limit = max(limit, 0)
        guard limit > 0 else { return [] }

        let documentItems = Array(documentURLs().prefix(limit)).compactMap(item(for:))
        guard documentItems.count < limit else { return documentItems }

        var items = deduplicated(documentItems)
        let missingCount = limit - items.count
        let lastUsedItems = await spotlightRecentFiles(
            dateAttribute: kMDItemLastUsedDate as String,
            limit: max(missingCount * SpotlightBudget.candidateMultiplier, SpotlightBudget.lastUsedMinimumLimit)
        )
        items = deduplicated(items + lastUsedItems)

        if items.count < limit {
            let modifiedItems = await spotlightRecentFiles(
                dateAttribute: kMDItemFSContentChangeDate as String,
                limit: max((limit - items.count) * SpotlightBudget.candidateMultiplier, SpotlightBudget.modifiedMinimumLimit)
            )
            items = deduplicated(items + modifiedItems)
        }

        return items
            .sorted(by: recentSort)
            .prefix(limit)
            .map(\.self)
    }

    private func spotlightRecentFiles(dateAttribute: String, limit: Int) async -> [PaletteFileItem] {
        let locations = searchLocations()
        guard !locations.isEmpty else { return [] }
        let result = await runner.run(
            predicate: recentSpotlightPredicate(dateAttribute: dateAttribute),
            scope: .locations(locations),
            limit: limit,
            timeoutMilliseconds: SpotlightBudget.timeoutMilliseconds,
            sortDescriptors: [
                NSSortDescriptor(key: dateAttribute, ascending: false),
            ]
        )
        return result.records.compactMap { record in
            guard isDisplayableSpotlightRecent(record.url) else { return nil }
            guard record.isDirectory == false else { return nil }
            return PaletteFileItem(
                url: record.url,
                name: record.name,
                displayPath: abbreviateHome(in: record.url.deletingLastPathComponent().path),
                isDirectory: record.isDirectory,
                contentTypeIdentifier: record.contentTypeIdentifier,
                lastUsedAt: record.lastUsedAt,
                modifiedAt: record.modifiedAt
            )
        }
    }

    private func recentSpotlightPredicate(dateAttribute: String) -> NSPredicate {
        let date = Date(timeIntervalSince1970: 0) as NSDate
        return NSPredicate(
            format: "(%K > %@) AND NOT (%K BEGINSWITH %@) AND NOT (%K CONTAINS %@) AND NOT (%K CONTAINS %@) AND NOT (%K CONTAINS %@) AND NOT (%K CONTAINS %@) AND NOT (%K CONTAINS %@)",
            dateAttribute,
            date,
            kMDItemFSName as String,
            ".",
            kMDItemPath as String,
            "/.",
            kMDItemPath as String,
            "/node_modules/",
            kMDItemPath as String,
            "/.git/",
            kMDItemPath as String,
            "/.build/",
            kMDItemPath as String,
            "/DerivedData/"
        )
    }

    private static func defaultSearchLocations(fileManager: FileManager = .default) -> [URL] {
        let commonDirectories: [FileManager.SearchPathDirectory] = [
            .desktopDirectory,
            .documentDirectory,
            .downloadsDirectory,
            .moviesDirectory,
            .musicDirectory,
            .picturesDirectory,
        ]
        let commonURLs = commonDirectories.compactMap { directory in
            fileManager.urls(for: directory, in: .userDomainMask).first
        }
        let home = fileManager.homeDirectoryForCurrentUser
        let workspaceURL = home.appendingPathComponent("workspace", isDirectory: true)

        let voxFlowURLs: [URL]
        if let paths = try? ApplicationSupportPaths.live(fileManager: fileManager) {
            voxFlowURLs = [
                paths.exportsDirectory,
                paths.screenshotsDirectory,
                paths.screenRecordingsDirectory,
                paths.clipboardAssetsDirectory,
                paths.voiceTaskAudioDirectory,
            ]
        } else {
            voxFlowURLs = []
        }

        return deduplicatedURLs(commonURLs + [workspaceURL] + voxFlowURLs)
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    private func isDisplayableSpotlightRecent(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        if path.contains("/.Trash/") { return false }
        if isDependencyOrBuildPath(path) { return false }
        return true
    }

    private func isDependencyOrBuildPath(_ path: String) -> Bool {
        let excludedComponents: Set<String> = [
            "node_modules",
            ".git",
            ".build",
            "DerivedData",
        ]
        return path.split(separator: "/").contains { excludedComponents.contains(String($0)) }
    }

    private func item(for url: URL) -> PaletteFileItem? {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .contentTypeKey,
            .contentModificationDateKey,
        ])
        return PaletteFileItem(
            url: url,
            name: url.lastPathComponent,
            displayPath: abbreviateHome(in: url.deletingLastPathComponent().path),
            isDirectory: values?.isDirectory ?? false,
            contentTypeIdentifier: values?.contentType?.identifier,
            lastUsedAt: nil,
            modifiedAt: values?.contentModificationDate
        )
    }

    private func deduplicated(_ items: [PaletteFileItem]) -> [PaletteFileItem] {
        var seenURLs = Set<URL>()
        return items.filter { item in
            seenURLs.insert(item.url).inserted
        }
    }

    private func recentSort(_ lhs: PaletteFileItem, _ rhs: PaletteFileItem) -> Bool {
        switch (lhs.lastUsedAt ?? lhs.modifiedAt, rhs.lastUsedAt ?? rhs.modifiedAt) {
        case let (lhsDate?, rhsDate?):
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func abbreviateHome(in path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
