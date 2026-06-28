import Foundation

extension ScreenshotL10n {
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
        if Bundle.module.path(forResource: "ScreenshotKit", ofType: "strings") != nil {
            return Bundle.module
        }
        return sourceResourcesBundle ?? Bundle.module
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
            let localizedDirectory = resourceRoot
                .appendingPathComponent("\(languageCode).lproj", isDirectory: true)
            if FileManager.default.fileExists(atPath: localizedDirectory.path),
               let bundle = Bundle(path: localizedDirectory.path) {
                return bundle
            }
        }
        return nil
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
        if let resourceURL = Bundle.module.resourceURL {
            urls.append(resourceURL)
        }
        urls.append(URL(fileURLWithPath: sourceResourcesPath, isDirectory: true))
        return urls
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
