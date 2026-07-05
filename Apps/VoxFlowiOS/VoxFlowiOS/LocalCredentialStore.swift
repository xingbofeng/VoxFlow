import Foundation

/// iOS V1 本地凭证存储：写入 App sandbox 的明文 JSON 文件。
///
/// V1 明确不做 Keychain、加密、导入导出或服务端代理；仅用于个人调试 key。
/// 文件位置：`Application Support/VoxFlow/credentials.json`。
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

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = support.appendingPathComponent("VoxFlow", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("credentials.json")
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
                result[provider] = value
            }
        }
        return result
    }

    func values(for provider: Provider) -> CredentialValues {
        loadAll()[provider] ?? [:]
    }

    func save(provider: Provider, values: CredentialValues) throws {
        var all = loadAll()
        all[provider] = values
        try write(all)
    }

    func clear(provider: Provider) throws {
        var all = loadAll()
        all[provider] = nil
        try write(all)
    }

    func isComplete(_ provider: Provider) -> Bool {
        let values = self.values(for: provider)
        return provider.fieldDefinitions.allSatisfy { field in
            !(values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private func write(_ all: [Provider: CredentialValues]) throws {
        var dict: [String: CredentialValues] = [:]
        for (provider, values) in all {
            dict[provider.rawValue] = values
        }
        let data = try JSONEncoder().encode(dict)
        try data.write(to: fileURL, options: .atomic)
    }
}
