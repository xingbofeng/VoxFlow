import Foundation

public struct RimeDataDirectories: Equatable, Sendable {
    public var appGroupRoot: URL
    public var sandboxRoot: URL

    public init(appGroupRoot: URL, sandboxRoot: URL) {
        self.appGroupRoot = appGroupRoot
        self.sandboxRoot = sandboxRoot
    }

    public var appGroupSharedSupport: URL {
        appGroupRoot.appendingPathComponent("SharedSupport", isDirectory: true)
    }

    public var appGroupUserData: URL {
        appGroupRoot.appendingPathComponent("UserData", isDirectory: true)
    }

    public var sandboxSharedSupport: URL {
        sandboxRoot.appendingPathComponent("SharedSupport", isDirectory: true)
    }

    public var sandboxUserData: URL {
        sandboxRoot.appendingPathComponent("UserData", isDirectory: true)
    }

    public var futureImportedSchemas: URL {
        appGroupUserData.appendingPathComponent("ImportedSchemas", isDirectory: true)
    }
}

public struct RimeSchemaDeploymentPlan: Equatable, Sendable {
    private static let deploymentMarkerName = ".mashangxie-rime-schema-deployment"

    public static let requiredPrebuiltBuildResourceNames = [
        "default.yaml",
        "rime_ice.schema.yaml",
        "rime_ice.table.bin",
        "rime_ice.prism.bin",
        "rime_ice.reverse.bin",
        "t9.schema.yaml",
        "t9.prism.bin",
        "melt_eng.schema.yaml",
        "melt_eng.table.bin",
        "melt_eng.prism.bin",
        "melt_eng.reverse.bin",
        "radical_pinyin.schema.yaml",
        "radical_pinyin.table.bin",
        "radical_pinyin.prism.bin",
        "radical_pinyin.reverse.bin",
    ]

    public static let requiredSchemaResourceNames = [
        "default.yaml",
        "rime_ice.schema.yaml",
        "rime_ice.dict.yaml",
        "t9.schema.yaml",
        "melt_eng.schema.yaml",
        "melt_eng.dict.yaml",
        "radical_pinyin.schema.yaml",
        "radical_pinyin.dict.yaml",
    ]

    public var directories: RimeDataDirectories
    public var bundledSchemaNames: [String]

    public init(directories: RimeDataDirectories, bundledSchemaNames: [String]) {
        self.directories = directories
        self.bundledSchemaNames = bundledSchemaNames
    }

    public var missingRequiredSchemaNames: [String] {
        Self.requiredSchemaResourceNames.filter { !bundledSchemaNames.contains($0) }
    }

    public var canDeployBuiltInSchemas: Bool {
        missingRequiredSchemaNames.isEmpty
    }

    public func createDirectories(fileManager: FileManager = .default) throws {
        for url in [
            directories.appGroupSharedSupport,
            directories.appGroupUserData,
            directories.sandboxSharedSupport,
            directories.sandboxUserData,
            directories.futureImportedSchemas,
        ] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func deployBuiltInSchemas(from bundle: Bundle, fileManager: FileManager = .default) throws {
        try createDirectories(fileManager: fileManager)

        let sourceDirectory = try bundledSchemasDirectory(in: bundle)
        for targetDirectory in [directories.appGroupSharedSupport, directories.sandboxSharedSupport] {
            try deploySharedSupport(
                from: sourceDirectory,
                to: targetDirectory,
                fileManager: fileManager
            )
        }

        let sourceLuaDirectory = sourceDirectory.appendingPathComponent("lua", isDirectory: true)
        if fileManager.fileExists(atPath: sourceLuaDirectory.path) {
            for userDataDirectory in [directories.appGroupUserData, directories.sandboxUserData] {
                try deployLuaResources(
                    from: sourceLuaDirectory,
                    to: userDataDirectory,
                    fileManager: fileManager
                )
            }
        }

        if let sourceBuildDirectory = prebuiltBuildDirectory(in: sourceDirectory, fileManager: fileManager) {
            for userDataDirectory in [directories.appGroupUserData, directories.sandboxUserData] {
                try deployPrebuiltBuild(
                    from: sourceBuildDirectory,
                    sourceSchemasDirectory: sourceDirectory,
                    to: userDataDirectory,
                    fileManager: fileManager
                )
            }
        }
    }

    public func deployBuiltInSchemas(
        from bundle: Bundle,
        sharedSupportDirectory: URL,
        userDataDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: sharedSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userDataDirectory, withIntermediateDirectories: true)

        let sourceDirectory = try bundledSchemasDirectory(in: bundle)
        try deploySharedSupport(
            from: sourceDirectory,
            to: sharedSupportDirectory,
            fileManager: fileManager
        )

        let sourceLuaDirectory = sourceDirectory.appendingPathComponent("lua", isDirectory: true)
        if fileManager.fileExists(atPath: sourceLuaDirectory.path) {
            try deployLuaResources(
                from: sourceLuaDirectory,
                to: userDataDirectory,
                fileManager: fileManager
            )
        }

        if let sourceBuildDirectory = prebuiltBuildDirectory(in: sourceDirectory, fileManager: fileManager) {
            try deployPrebuiltBuild(
                from: sourceBuildDirectory,
                sourceSchemasDirectory: sourceDirectory,
                to: userDataDirectory,
                fileManager: fileManager
            )
        }
    }

    private func bundledSchemasDirectory(in bundle: Bundle) throws -> URL {
        if let sourceDirectory = bundle.url(forResource: "Schemas", withExtension: nil) {
            return sourceDirectory
        }

        if let marker = bundledResourceURL(named: Self.requiredSchemaResourceNames[0], in: bundle),
           marker.deletingLastPathComponent().lastPathComponent == "Schemas" {
            return marker.deletingLastPathComponent()
        }

        throw RimeSchemaDeploymentError.missingBundledResource("Schemas")
    }

    private func bundledResourceURL(named name: String, in bundle: Bundle) -> URL? {
        let resource = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return bundle.url(forResource: resource, withExtension: ext, subdirectory: "Schemas")
            ?? bundle.url(forResource: resource, withExtension: ext)
    }

    private func copyContents(
        from sourceDirectory: URL,
        to targetDirectory: URL,
        excluding excludedNames: Set<String> = [],
        fileManager: FileManager
    ) throws {
        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )
        for sourceURL in sourceItems {
            guard !excludedNames.contains(sourceURL.lastPathComponent) else {
                continue
            }
            try fileManager.copyItem(
                at: sourceURL,
                to: targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            )
        }
    }

    private func deploySharedSupport(from sourceDirectory: URL, to targetDirectory: URL, fileManager: FileManager) throws {
        let marker = try deploymentMarker(for: sourceDirectory)
        if deploymentIsCurrent(
            in: targetDirectory,
            marker: marker,
            requiredNames: bundledSchemaNames,
            fileManager: fileManager
        ) {
            return
        }

        if fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.removeItem(at: targetDirectory)
        }
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try copyContents(from: sourceDirectory, to: targetDirectory, excluding: ["build"], fileManager: fileManager)
        try marker.write(
            to: targetDirectory.appendingPathComponent(Self.deploymentMarkerName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func prebuiltBuildDirectory(in sourceDirectory: URL, fileManager: FileManager) -> URL? {
        let sourceBuildDirectory = sourceDirectory.appendingPathComponent("build", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceBuildDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return sourceBuildDirectory
    }

    private func deployPrebuiltBuild(
        from sourceBuildDirectory: URL,
        sourceSchemasDirectory: URL,
        to userDataDirectory: URL,
        fileManager: FileManager
    ) throws {
        let targetBuildDirectory = userDataDirectory.appendingPathComponent("build", isDirectory: true)
        let marker = try prebuiltBuildMarker(
            for: sourceBuildDirectory,
            sourceSchemasDirectory: sourceSchemasDirectory,
            fileManager: fileManager
        )
        if deploymentIsCurrent(
            in: targetBuildDirectory,
            marker: marker,
            requiredNames: Self.requiredPrebuiltBuildResourceNames,
            fileManager: fileManager
        ) {
            return
        }

        if fileManager.fileExists(atPath: targetBuildDirectory.path) {
            try fileManager.removeItem(at: targetBuildDirectory)
        }
        try fileManager.createDirectory(at: targetBuildDirectory, withIntermediateDirectories: true)
        try linkContents(
            from: sourceBuildDirectory,
            to: targetBuildDirectory,
            fileManager: fileManager
        )
        try marker.write(
            to: targetBuildDirectory.appendingPathComponent(Self.deploymentMarkerName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func deployLuaResources(from sourceLuaDirectory: URL, to userDataDirectory: URL, fileManager: FileManager) throws {
        let targetLuaDirectory = userDataDirectory.appendingPathComponent("lua", isDirectory: true)
        let marker = try deploymentMarker(for: sourceLuaDirectory)
        if deploymentIsCurrent(
            in: targetLuaDirectory,
            marker: marker,
            requiredNames: ["lunar.db"],
            fileManager: fileManager
        ) {
            return
        }

        if fileManager.fileExists(atPath: targetLuaDirectory.path) {
            try fileManager.removeItem(at: targetLuaDirectory)
        }
        try fileManager.createDirectory(at: targetLuaDirectory, withIntermediateDirectories: true)
        try copyContents(from: sourceLuaDirectory, to: targetLuaDirectory, fileManager: fileManager)
        try marker.write(
            to: targetLuaDirectory.appendingPathComponent(Self.deploymentMarkerName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func deploymentIsCurrent(
        in targetDirectory: URL,
        marker: String,
        requiredNames: [String],
        fileManager: FileManager
    ) -> Bool {
        let markerURL = targetDirectory.appendingPathComponent(Self.deploymentMarkerName)
        guard
            let deployedMarker = try? String(contentsOf: markerURL, encoding: .utf8),
            deployedMarker == marker
        else {
            return false
        }

        return requiredNames.allSatisfy { name in
            fileManager.fileExists(atPath: targetDirectory.appendingPathComponent(name).path)
        }
    }

    private func deploymentMarker(for sourceDirectory: URL) throws -> String {
        let revisionURL = sourceDirectory.appendingPathComponent(".rime-ice-revision")
        if let revision = try? String(contentsOf: revisionURL, encoding: .utf8) {
            return revision.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return bundledSchemaNames.joined(separator: "\n")
    }

    private func prebuiltBuildMarker(
        for sourceBuildDirectory: URL,
        sourceSchemasDirectory: URL,
        fileManager: FileManager
    ) throws -> String {
        var marker = "prebuilt-rime-build-v1\n"
        marker += try deploymentMarker(for: sourceSchemasDirectory)
        marker += "\n"

        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceBuildDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let lines = try sourceItems
            .filter { $0.lastPathComponent != Self.deploymentMarkerName }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url -> String in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                return "\(url.lastPathComponent):\(size)"
            }
        marker += lines.joined(separator: "\n")
        return marker
    }

    private func linkContents(from sourceDirectory: URL, to targetDirectory: URL, fileManager: FileManager) throws {
        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for sourceURL in sourceItems {
            let targetURL = targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                continue
            }

            do {
                try fileManager.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            }
        }
    }
}

public enum RimeSchemaDeploymentError: Error, Equatable, Sendable {
    case missingBundledResource(String)
}
