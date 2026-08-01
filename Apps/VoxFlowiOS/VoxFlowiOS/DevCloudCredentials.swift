import Foundation

enum DevCloudCredentials {
    private static let resourceName = "DevCloudCredentials"
    private static let legacyInfoKey = "MashangxieDevCloudCredentials"

    static func values(for provider: LocalCredentialStore.Provider) -> LocalCredentialStore.CredentialValues {
        guard let root = bundledCredentials() else {
            return [:]
        }

        return values(for: provider, root: root)
    }

    static func values(
        for provider: LocalCredentialStore.Provider,
        root: [String: Any]
    ) -> LocalCredentialStore.CredentialValues {
        switch provider {
        case .tencent:
            return [
                "appID": decodedString("TencentAppIDB64", in: root),
                "secretID": decodedString("TencentSecretIDB64", in: root),
                "secretKey": decodedString("TencentSecretKeyB64", in: root),
            ].filter { !$0.value.isEmpty }
        case .aliyun:
            return [
                "apiKey": decodedString("AliyunAPIKeyB64", in: root),
            ].filter { !$0.value.isEmpty }
        case .volcengine:
            return [
                "appID": decodedString("VolcengineAppIDB64", in: root),
                "accessToken": decodedString("VolcengineAccessTokenB64", in: root),
                "secretKey": decodedString("VolcengineSecretKeyB64", in: root),
            ].filter { !$0.value.isEmpty }
        }
    }

    private static func bundledCredentials() -> [String: Any]? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let root = object as? [String: Any] {
            return root
        }
        return Bundle.main.object(forInfoDictionaryKey: legacyInfoKey) as? [String: Any]
    }

    private static func decodedString(_ key: String, in root: [String: Any]) -> String {
        let value = (root[key] as? String) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return "" }

        let normalized = normalizedBase64(trimmed)
        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        let result = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPlaceholderDecodedValue(result) ? "" : result
    }

    private static func isPlaceholderDecodedValue(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.isEmpty
            || lowercased.hasPrefix("sim-")
            || lowercased.contains("placeholder")
            || lowercased.contains("your-")
            || lowercased.contains("<")
    }

    private static func normalizedBase64(_ value: String) -> String {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return normalized
    }
}
