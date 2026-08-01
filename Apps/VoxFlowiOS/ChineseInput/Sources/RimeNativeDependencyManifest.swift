import Foundation

public enum RimeNativeDependencyManifest {
    public static let sourceDescription = "amorphobia/LibrimeKit v0.1.0 Frameworks.tgz"
    public static let sourceURL = URL(string: "https://github.com/amorphobia/LibrimeKit/releases/download/v0.1.0/Frameworks.tgz")!

    public static let expectedFrameworkNames: [String] = [
        "boost_atomic",
        "boost_filesystem",
        "boost_regex",
        "boost_system",
        "libglog",
        "libleveldb",
        "libmarisa",
        "libopencc",
        "librime",
        "libyaml-cpp",
    ]

    public static func frameworkDirectoryNames(in frameworksDirectory: URL) throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: frameworksDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension == "xcframework" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public static func missingFrameworkNames(in frameworksDirectory: URL) throws -> [String] {
        let existing = Set(try frameworkDirectoryNames(in: frameworksDirectory))
        return expectedFrameworkNames.filter { !existing.contains($0) }
    }

    public static func supportsIOSDeviceArm64(frameworkURL: URL) -> Bool {
        availableLibraries(frameworkURL: frameworkURL).contains { library in
            library.supportedPlatform == "ios"
                && library.supportedPlatformVariant == nil
                && library.supportedArchitectures.contains("arm64")
        }
    }

    public static func supportsIOSSimulator(frameworkURL: URL) -> Bool {
        availableLibraries(frameworkURL: frameworkURL).contains { library in
            library.supportedPlatform == "ios"
                && library.supportedPlatformVariant == "simulator"
        }
    }

    public static func availableLibraries(frameworkURL: URL) -> [XCFrameworkLibrary] {
        let plistURL = frameworkURL.appendingPathComponent("Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              let libraries = plist["AvailableLibraries"] as? [[String: Any]] else {
            return []
        }
        return libraries.compactMap(XCFrameworkLibrary.init)
    }
}

public struct XCFrameworkLibrary: Equatable, Sendable {
    public let identifier: String
    public let supportedPlatform: String
    public let supportedPlatformVariant: String?
    public let supportedArchitectures: [String]

    init?(dictionary: [String: Any]) {
        guard let identifier = dictionary["LibraryIdentifier"] as? String,
              let supportedPlatform = dictionary["SupportedPlatform"] as? String,
              let supportedArchitectures = dictionary["SupportedArchitectures"] as? [String] else {
            return nil
        }
        self.identifier = identifier
        self.supportedPlatform = supportedPlatform
        self.supportedPlatformVariant = dictionary["SupportedPlatformVariant"] as? String
        self.supportedArchitectures = supportedArchitectures
    }
}
