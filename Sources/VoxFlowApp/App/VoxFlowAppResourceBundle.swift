import Foundation

enum VoxFlowAppResourceBundle {
    private static let bundleName = "VoxFlowApp_VoxFlowApp.bundle"

    static func url(
        forResource name: String,
        withExtension extensionName: String,
        subdirectory: String? = nil
    ) -> URL? {
        resourceBundle()?.url(
            forResource: name,
            withExtension: extensionName,
            subdirectory: subdirectory
        )
    }

    private static func resourceBundle(fileManager: FileManager = .default) -> Bundle? {
        for candidate in candidateURLs() where fileManager.fileExists(atPath: candidate.path) {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }
        urls.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(bundleName, isDirectory: true)
        )
        urls.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))
        urls.append(
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName, isDirectory: true)
        )

        if let packageRoot = packageRootURL() {
            urls.append(
                contentsOf: ["debug", "release"].flatMap { configuration in
                    [
                        packageRoot
                            .appendingPathComponent(".build", isDirectory: true)
                            .appendingPathComponent(swiftPMTriple, isDirectory: true)
                            .appendingPathComponent(configuration, isDirectory: true)
                            .appendingPathComponent(bundleName, isDirectory: true),
                        packageRoot
                            .appendingPathComponent(".build", isDirectory: true)
                            .appendingPathComponent(configuration, isDirectory: true)
                            .appendingPathComponent(bundleName, isDirectory: true)
                    ]
                }
            )
        }

        return urls
    }

    private static var swiftPMTriple: String {
        #if arch(arm64)
        return "arm64-apple-macosx"
        #else
        return "x86_64-apple-macosx"
        #endif
    }

    private static func packageRootURL(
        sourceFileURL: URL = URL(fileURLWithPath: #filePath),
        fileManager: FileManager = .default
    ) -> URL? {
        var directory = sourceFileURL.deletingLastPathComponent()
        while directory.path != "/" {
            let packageManifest = directory.appendingPathComponent("Package.swift", isDirectory: false)
            if fileManager.fileExists(atPath: packageManifest.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
