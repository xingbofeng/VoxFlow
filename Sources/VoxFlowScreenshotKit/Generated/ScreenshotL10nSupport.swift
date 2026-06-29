import Foundation

extension ScreenshotL10n {
    static let resourceBundleName = "VoxFlowApp_VoxFlowScreenshotKit.bundle"

    static var bundle: Bundle {
        if let testBundle = testInterfaceLanguageBundle {
            return testBundle
        }
        return defaultBundle
    }

    static var locale: Locale {
        guard let languageCode = testInterfaceLanguageCode else {
            return .current
        }
        return Locale(identifier: localeIdentifier(for: languageCode))
    }

    private static var defaultBundle: Bundle {
        if let packagedBundle = packagedResourceBundle {
            return packagedBundle
        }
        return sourceResourcesBundle ?? .main
    }

    private static var testInterfaceLanguageBundle: Bundle? {
        guard let languageCode = testInterfaceLanguageCode else {
            return nil
        }
        return localizedBundle(for: languageCode)
    }

    private static var testInterfaceLanguageCode: String? {
        guard let languageCode = ProcessInfo.processInfo.environment["VOXFLOW_TEST_INTERFACE_LANGUAGE"],
              !languageCode.isEmpty else {
            return nil
        }
        return languageCode
    }

    private static func localizedBundle(for languageCode: String) -> Bundle? {
        for resourceRoot in resourceRoots {
            for directoryName in localizedDirectoryNames(for: languageCode) {
                let localizedDirectory = resourceRoot
                    .appendingPathComponent(directoryName, isDirectory: true)
                if FileManager.default.fileExists(atPath: localizedDirectory.path),
                   let bundle = Bundle(path: localizedDirectory.path) {
                    return bundle
                }
            }
        }
        return nil
    }

    private static func localizedDirectoryNames(for languageCode: String) -> [String] {
        let exactName = "\(languageCode).lproj"
        let lowercasedName = "\(languageCode.lowercased()).lproj"
        return exactName == lowercasedName ? [exactName] : [exactName, lowercasedName]
    }

    private static func localeIdentifier(for languageCode: String) -> String {
        switch languageCode {
        case "zh-Hans":
            return "zh_Hans"
        case "zh-Hant":
            return "zh_Hant"
        default:
            return languageCode
        }
    }

    private static var resourceRoots: [URL] {
        var urls: [URL] = []
        if let packagedBundle = packagedResourceBundle {
            urls.append(packagedBundle.resourceURL ?? packagedBundle.bundleURL)
        }
        urls.append(URL(fileURLWithPath: sourceResourcesPath, isDirectory: true))
        return urls
    }

    static func packagedResourceBundle(mainBundleURL: URL, mainResourceURL: URL?) -> Bundle? {
        let candidates = [
            mainResourceURL?.appendingPathComponent(resourceBundleName, isDirectory: true),
            mainBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(resourceBundleName, isDirectory: true),
            mainBundleURL.appendingPathComponent(resourceBundleName, isDirectory: true),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            guard let bundle = Bundle(path: candidate.path),
                  bundle.path(forResource: "ScreenshotKit", ofType: "strings") != nil else {
                continue
            }
            return bundle
        }
        return nil
    }

    private static var packagedResourceBundle: Bundle? {
        packagedResourceBundle(mainBundleURL: Bundle.main.bundleURL, mainResourceURL: Bundle.main.resourceURL)
    }

    private static var sourceResourcesBundle: Bundle? {
        Bundle(path: sourceResourcesPath)
    }

    private static var sourceResourcesPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .path
    }
}
