import Foundation

extension L10n {
    static var bundle: Bundle {
        if let languageBundle = explicitInterfaceLanguageBundle {
            return languageBundle
        }
        if let testBundle = testInterfaceLanguageBundle {
            return testBundle
        }
        return defaultBundle
    }

    static var locale: Locale {
        guard let languageCode = activeInterfaceLanguageCode else {
            return .current
        }
        return Locale(identifier: localeIdentifier(for: languageCode))
    }

    private static var defaultBundle: Bundle {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }
        return sourceResourcesBundle ?? .main
    }

    static func localize(_ key: String, comment: String = "") -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private static var explicitInterfaceLanguageBundle: Bundle? {
        guard let rawValue = explicitInterfaceLanguageCode else {
            return nil
        }
        return localizedBundle(for: rawValue)
    }

    private static var testInterfaceLanguageBundle: Bundle? {
        guard let languageCode = testInterfaceLanguageCode else {
            return nil
        }
        return localizedBundle(for: languageCode)
    }

    private static var activeInterfaceLanguageCode: String? {
        explicitInterfaceLanguageCode ?? testInterfaceLanguageCode
    }

    private static var explicitInterfaceLanguageCode: String? {
        let defaultsKey = "VoxFlow_InterfaceLanguage"
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              rawValue != AppLanguage.followSystem.rawValue else {
            return nil
        }
        return rawValue
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
        if let resourceURL = Bundle.main.resourceURL {
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
