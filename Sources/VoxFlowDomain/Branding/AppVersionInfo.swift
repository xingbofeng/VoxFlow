import Foundation

public struct AppVersionInfo: Equatable {
    public let version: String
    public let build: String

    public var displayText: String {
        version
    }

    public var detailedDisplayText: String {
        "\(version) (\(build))"
    }

    public static func current(bundle: Bundle = .main) -> AppVersionInfo {
        from(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func from(infoDictionary: [String: Any]) -> AppVersionInfo {
        AppVersionInfo(
            version: nonEmpty(infoDictionary["CFBundleShortVersionString"] as? String) ?? "开发版",
            build: nonEmpty(infoDictionary["CFBundleVersion"] as? String) ?? "0"
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
