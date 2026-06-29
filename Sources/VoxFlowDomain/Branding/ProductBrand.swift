import Foundation

public enum ProductBrand {
    public static var englishName: String {
        localizedName(forKey: "product.brand.english_name", defaultValue: "VoxFlow")
    }

    public static var chineseDisplayName: String {
        localizedName(forKey: "product.brand.chinese_display_name", defaultValue: "码上写")
    }
    public static let bundleIdentifier = "com.voxflow.app"

    public static var displayName: String {
        localeName(for: Bundle.main.preferredLocalizations.first ?? "en")
    }

    private static func localeName(for localeIdentifier: String) -> String {
        localeIdentifier.lowercased().hasPrefix("zh") ? chineseDisplayName : englishName
    }

    private static func localizedName(forKey key: String, defaultValue: String) -> String {
        Bundle.main.localizedString(forKey: key, value: defaultValue, table: "Localizable")
    }
}
