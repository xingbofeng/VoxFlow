import Foundation
import Shared

/// iOS V1 本地凭证存储：写入 App sandbox 的明文 JSON 文件。
///
/// V1 明确不做 Keychain、加密、导入导出或服务端代理；仅用于个人调试 key。
/// 文件位置：优先写入 App Group 容器，确保主 App 冷启动链路和后续扩展桥接都读同一份配置。
struct LocalCredentialStore {
    enum Provider: String, CaseIterable, Identifiable {
        case tencent
        case aliyun
        case volcengine

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tencent: return "腾讯云实时 ASR"
            case .aliyun: return "阿里云 DashScope"
            case .volcengine: return "火山云实时 ASR"
            }
        }

        var fieldDefinitions: [CredentialField] {
            switch self {
            case .tencent:
                return [
                    .init(key: "appID", label: "AppID"),
                    .init(key: "secretID", label: "SecretId"),
                    .init(key: "secretKey", label: "SecretKey", isSecret: true),
                ]
            case .aliyun:
                return [
                    .init(key: "apiKey", label: "API Key", isSecret: true),
                ]
            case .volcengine:
                return [
                    .init(key: "appID", label: "App ID"),
                    .init(key: "accessToken", label: "Access Token", isSecret: true),
                    .init(key: "secretKey", label: "Secret Key", isSecret: true),
                ]
            }
        }
    }

    struct CredentialField: Identifiable {
        let key: String
        let label: String
        var isSecret: Bool = false
        var id: String { key }
    }

    /// 某个 provider 的凭证字典。
    typealias CredentialValues = [String: String]

    private let fileURL: URL
    private let usesDevCloudCredentials: Bool

    init(
        fileURL: URL? = nil,
        legacyFileURL: URL? = nil,
        usesDevCloudCredentials: Bool = true
    ) {
        self.usesDevCloudCredentials = usesDevCloudCredentials
        let shouldMigrateLegacy = fileURL == nil || legacyFileURL != nil
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
        try? FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if shouldMigrateLegacy {
            migrateLegacyCredentialsIfNeeded(from: legacyFileURL ?? Self.legacySandboxFileURL())
        }
    }

    func loadAll() -> [Provider: CredentialValues] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: CredentialValues].self, from: data)
        else {
            return [:]
        }
        var result: [Provider: CredentialValues] = [:]
        for (key, value) in dict {
            if let provider = Provider(rawValue: key) {
                result[provider] = normalized(value)
            }
        }
        return result
    }

    func values(for provider: Provider) -> CredentialValues {
        loadAll()[provider] ?? [:]
    }

    func effectiveValues(for provider: Provider) -> CredentialValues {
        let manualValues = values(for: provider)
        if isComplete(provider: provider, values: manualValues) {
            return manualValues
        }
        guard usesDevCloudCredentials else {
            return [:]
        }
        return DevCloudCredentials.values(for: provider)
    }

    func save(provider: Provider, values: CredentialValues) throws {
        var all = loadAll()
        all[provider] = normalized(values)
        try write(all)
    }

    func clear(provider: Provider) throws {
        var all = loadAll()
        all[provider] = nil
        try write(all)
    }

    func isComplete(_ provider: Provider) -> Bool {
        isComplete(provider: provider, values: values(for: provider))
    }

    func isEffectivelyComplete(_ provider: Provider) -> Bool {
        isComplete(provider: provider, values: effectiveValues(for: provider))
    }

    private func isComplete(provider: Provider, values: CredentialValues) -> Bool {
        return provider.fieldDefinitions.allSatisfy { field in
            !(values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private func normalized(_ values: CredentialValues) -> CredentialValues {
        Dictionary(uniqueKeysWithValues: values.compactMap { key, rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isPlaceholderValue(value) else { return nil }
            return (key, value)
        })
    }

    private static func isPlaceholderValue(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.isEmpty
            || lowercased.hasPrefix("sim-")
            || lowercased.contains("placeholder")
            || lowercased.contains("your-")
            || lowercased.contains("<")
    }

    private func write(_ all: [Provider: CredentialValues]) throws {
        var dict: [String: CredentialValues] = [:]
        for (provider, values) in all {
            dict[provider.rawValue] = values
        }
        let data = try JSONEncoder().encode(dict)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let root = AppGroup.containerURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = root.appendingPathComponent("VoxFlow", isDirectory: true)
        return dir.appendingPathComponent("credentials.json")
    }

    private static func legacySandboxFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("VoxFlow", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private func migrateLegacyCredentialsIfNeeded(from legacyURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path),
              FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let decoded = try? JSONDecoder().decode([String: CredentialValues].self, from: data),
              !decoded.isEmpty
        else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
