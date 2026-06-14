import Foundation

// MARK: - AppSystemCategory

enum AppSystemCategory: String, Codable, Equatable {
    case userApplication    // /Applications
    case userLocal          // ~/Applications
    case systemApplication  // /System/Applications
}

// MARK: - InstalledApplication

struct InstalledApplication: Identifiable, Equatable, Hashable, Sendable {
    let id: String          // Bundle ID or path-based ID
    let name: String
    let bundleID: String?
    let iconPath: String?
    let path: String
    let systemCategory: AppSystemCategory
}

// MARK: - InstalledApplicationProviding

protocol InstalledApplicationProviding: Sendable {
    func scanInstalledApplications() -> [InstalledApplication]
}

// MARK: - FileSystemInstalledApplicationProvider

struct FileSystemInstalledApplicationProvider: InstalledApplicationProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationsRootPath: String?
    private let userHomePath: String?

    init(
        fileManager: FileManager = .default,
        applicationsRootPath: String? = nil,
        userHomePath: String? = nil
    ) {
        self.fileManager = fileManager
        self.applicationsRootPath = applicationsRootPath
        self.userHomePath = userHomePath
    }

    func scanInstalledApplications() -> [InstalledApplication] {
        var results: [InstalledApplication] = []
        var seenBundleIDs: Set<String> = []

        let scanTargets: [(path: String, category: AppSystemCategory)]

        if let root = applicationsRootPath {
            // Testable mode: only scan under the injected root
            var targets: [(String, AppSystemCategory)] = [
                ("\(root)/Applications", .userApplication),
                ("\(root)/System/Applications", .systemApplication),
            ]
            if let home = userHomePath {
                targets.insert(("\(home)/Applications", .userLocal), at: 1)
            }
            scanTargets = targets
        } else {
            // Production mode: scan real system directories
            var targets: [(String, AppSystemCategory)] = [
                ("/Applications", .userApplication),
                ("/System/Applications", .systemApplication),
            ]
            if let home = userHomePath ?? ProcessInfo.processInfo.environment["HOME"] {
                targets.insert(("\(home)/Applications", .userLocal), at: 1)
            }
            scanTargets = targets
        }

        for (path, category) in scanTargets {
            scanDirectory(at: path, category: category, results: &results, seenBundleIDs: &seenBundleIDs)
        }

        return results
    }

    // MARK: - Directory scanning

    private func scanDirectory(
        at path: String,
        category: AppSystemCategory,
        results: inout [InstalledApplication],
        seenBundleIDs: inout Set<String>
    ) {
        // Scan apps at this level
        scanAppBundlelications(
            in: path,
            category: category,
            results: &results,
            seenBundleIDs: &seenBundleIDs
        )

        // Scan one level of subdirectories
        guard let subdirs = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        for subdir in subdirs {
            let subdirPath = (path as NSString).appendingPathComponent(subdir)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subdirPath, isDirectory: &isDir),
                  isDir.boolValue,
                  (subdir as NSString).pathExtension != "app"
            else { continue }
            scanAppBundlelications(
                in: subdirPath,
                category: category,
                results: &results,
                seenBundleIDs: &seenBundleIDs
            )
        }
    }

    private func scanAppBundlelications(
        in directoryPath: String,
        category: AppSystemCategory,
        results: inout [InstalledApplication],
        seenBundleIDs: inout Set<String>
    ) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directoryPath) else { return }
        for entry in entries where (entry as NSString).pathExtension == "app" {
            let appPath = (directoryPath as NSString).appendingPathComponent(entry)
            guard let app = readApp(at: appPath, category: category) else { continue }
            if let bundleID = app.bundleID {
                let key = bundleID.lowercased()
                guard !seenBundleIDs.contains(key) else { continue }
                seenBundleIDs.insert(key)
            }
            results.append(app)
        }
    }

    // MARK: - Info.plist reading

    private func readApp(at path: String, category: AppSystemCategory) -> InstalledApplication? {
        let contentsPath = (path as NSString).appendingPathComponent("Contents")
        let infoPlistPath = (contentsPath as NSString).appendingPathComponent("Info.plist")

        var bundleID: String?
        var name = ((path as NSString).deletingPathExtension as NSString).lastPathComponent
        var iconPath: String?

        if let data = fileManager.contents(atPath: infoPlistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            bundleID = plist["CFBundleIdentifier"] as? String
            if let cfName = plist["CFBundleName"] as? String, !cfName.isEmpty {
                name = cfName
            }
            if let iconFile = plist["CFBundleIconFile"] as? String {
                let iconFileWithExt = iconFile.hasSuffix(".icns") ? iconFile : "\(iconFile).icns"
                let candidate = (contentsPath as NSString)
                    .appendingPathComponent("Resources")
                    .appending("/" + iconFileWithExt)
                iconPath = candidate
            } else if let resources = try? fileManager.contentsOfDirectory(
                atPath: (contentsPath as NSString).appendingPathComponent("Resources")
            ) {
                iconPath = resources
                    .first { $0.hasSuffix(".icns") }
                    .map { (contentsPath as NSString).appendingPathComponent("Resources").appending("/" + $0) }
            }
        }

        let id: String = {
            if let bundleID, !bundleID.isEmpty { return bundleID }
            return "path:\(path.lowercased())"
        }()

        return InstalledApplication(
            id: id,
            name: name,
            bundleID: bundleID?.isEmpty == false ? bundleID : nil,
            iconPath: iconPath,
            path: path,
            systemCategory: category
        )
    }
}
